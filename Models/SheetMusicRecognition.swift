//
//  SheetMusicRecognition.swift
//  MyPianoInstructor
//
//  Optical music recognition: turns photographed or imported sheet-music pages
//  into MusicXML that feeds the existing parse → falling-notes pipeline.
//
//  Recognition runs behind the SheetMusicRecognizer protocol so the backend is
//  swappable (a self-hosted Audiveris server or an on-device model could slot
//  in later). The default backend sends page images to the Claude vision API,
//  which returns MusicXML constrained to the subset MusicXMLParser understands.
//

import UIKit
import Security

// MARK: - Errors

enum SheetMusicRecognitionError: LocalizedError {
    case missingAPIKey
    case imageEncodingFailed
    case network(String)
    case httpError(Int, String)
    case truncatedResult
    case unreadableScore(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No API key is set. Tap the gear icon and add your Anthropic API key to enable scanning."
        case .imageEncodingFailed:
            return "The page images could not be prepared for upload."
        case .network(let detail):
            return "Network error: \(detail)"
        case .httpError(let code, let message):
            if code == 401 { return "The API key was rejected. Check it in scan settings." }
            if code == 429 { return "The recognition service is rate-limiting requests. Wait a moment and try again." }
            return "The recognition service returned an error (\(code)): \(message)"
        case .truncatedResult:
            return "The piece is too long to transcribe in one pass. Try scanning fewer pages at a time."
        case .unreadableScore(let detail):
            return detail
        }
    }
}

// MARK: - Recognizer Protocol

protocol SheetMusicRecognizer {
    /// Converts sheet-music page images (JPEG data, in page order) to MusicXML.
    /// Nonisolated so encoding and network work stay off the main actor.
    nonisolated func recognize(pages: [Data]) async throws -> String
}

// MARK: - Validation

/// A recognition result that survived parsing, ready to preview and save.
struct RecognizedScore {
    let musicXML: String
    let playback: PlaybackData
}

enum SheetMusicValidator {
    /// Runs recognized MusicXML through the app's own parser and rejects
    /// results that produce no usable music, so garbage never reaches the
    /// library.
    static func validate(musicXML: String) throws -> RecognizedScore {
        let playback = MusicXMLParser.parse(data: Data(musicXML.utf8))
        guard playback.notes.count >= 4, playback.totalDuration > 1 else {
            throw SheetMusicRecognitionError.unreadableScore(
                "No readable music was found in the scan. Make sure the pages are sharp, well-lit, and right-side up, then try again."
            )
        }
        return RecognizedScore(musicXML: musicXML, playback: playback)
    }
}

// MARK: - Page Image Preparation

enum SheetPagePrep {
    /// Longest edge sent to the vision model — larger is wasted tokens,
    /// smaller loses beams and dots.
    static let maxDimension: CGFloat = 1568

    static func jpegData(from image: UIImage) -> Data? {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > 0 else { return nil }

        let scale = min(1.0, maxDimension / longest)
        let target = CGSize(width: size.width * scale, height: size.height * scale)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let rendered = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return rendered.jpegData(compressionQuality: 0.7)
    }
}

// MARK: - Claude Vision Backend

struct ClaudeSheetMusicRecognizer: SheetMusicRecognizer {

    var apiKey: String
    var model: String

    private nonisolated static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    /// Beyond this, output length becomes the limiting factor and results
    /// arrive truncated; the UI surfaces a friendly error instead.
    static let maxPagesPerRequest = 6

    nonisolated func recognize(pages: [Data]) async throws -> String {
        guard !apiKey.isEmpty else { throw SheetMusicRecognitionError.missingAPIKey }
        guard !pages.isEmpty else {
            throw SheetMusicRecognitionError.unreadableScore("No pages to recognize.")
        }

        var content: [[String: Any]] = pages.map { page in
            [
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": "image/jpeg",
                    "data": page.base64EncodedString()
                ]
            ]
        }
        content.append(["type": "text", "text": Self.transcriptionRequest(pageCount: pages.count)])

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 32000,
            "system": Self.systemPrompt,
            "messages": [["role": "user", "content": content]]
        ]

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        // Transcription of a full piece can take a while; the default 60s
        // request timeout is too tight for multi-page scores.
        request.timeoutInterval = 600
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw SheetMusicRecognitionError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw SheetMusicRecognitionError.network("invalid response")
        }
        guard http.statusCode == 200 else {
            let message = Self.apiErrorMessage(from: data) ?? "no details"
            throw SheetMusicRecognitionError.httpError(http.statusCode, message)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let contentBlocks = json["content"] as? [[String: Any]] else {
            throw SheetMusicRecognitionError.network("unexpected response format")
        }

        if let stopReason = json["stop_reason"] as? String, stopReason == "max_tokens" {
            throw SheetMusicRecognitionError.truncatedResult
        }

        let text = contentBlocks
            .compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
            .joined()

        return Self.extractMusicXML(from: text)
    }

    nonisolated private static func apiErrorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any] else { return nil }
        return error["message"] as? String
    }

    /// Defensive cleanup: strip markdown fences or stray prose around the
    /// document should the model add any despite instructions.
    nonisolated static func extractMusicXML(from text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if let fenceStart = result.range(of: "```") {
            let afterFence = result[fenceStart.upperBound...]
            if let fenceEnd = afterFence.range(of: "```") {
                var inner = String(afterFence[..<fenceEnd.lowerBound])
                if inner.hasPrefix("xml") { inner = String(inner.dropFirst(3)) }
                result = inner.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        if let xmlStart = result.range(of: "<?xml") ?? result.range(of: "<score-partwise") {
            result = String(result[xmlStart.lowerBound...])
        }
        if let end = result.range(of: "</score-partwise>", options: .backwards) {
            result = String(result[..<end.upperBound])
        }
        return result
    }

    // MARK: Prompts

    nonisolated static let systemPrompt = """
    You are an expert music engraver who transcribes piano sheet music images into MusicXML with perfect fidelity. You read key signatures, time signatures, clefs, accidentals, ties, dots, tuplets, dynamics, tempo markings, and pedal marks accurately, and you keep both staves rhythmically aligned. Your entire reply is always exactly one complete MusicXML document — no markdown fences, no commentary before or after.
    """

    nonisolated static func transcriptionRequest(pageCount: Int) -> String {
        """
        Transcribe the piano piece in \(pageCount == 1 ? "this image" : "these \(pageCount) images (pages in order)") into a single continuous MusicXML document.

        Format requirements — the consuming app reads a specific MusicXML subset:
        - `score-partwise` with exactly one part (id "P1") for piano.
        - Two staves: right hand on staff 1 with voice 1, left hand on staff 2 with voice 5. Every note carries <voice> and <staff>. Use <backup> to return to the start of the measure for the left hand.
        - Choose one <divisions> value for the whole piece that expresses every rhythm you see, including dots and tuplets (24 works for most music; use 480 if there are complex tuplets). Every <duration> must be a whole number.
        - Emit <sound tempo="N"/> in the first measure (from the printed tempo/metronome marking, or a musically sensible value for the style if none is printed). Add further <sound tempo> elements only where the score changes tempo.
        - Spell sounding pitches with <step>, <octave>, and <alter> (apply the key signature and accidentals; use <alter>1</alter> for sharps, -1 for flats).
        - Chords: subsequent chord tones carry <chord/>. Ties between same pitches use <tie type="start"/> and <tie type="stop"/>. Rests use <rest/> with a duration. Grace notes use <grace/> and no duration.
        - Pedal markings become <direction><direction-type><pedal type="start"/></direction-type></direction> and type "stop" where released.
        - Write out repeats literally: unfold repeat barlines, volta endings, D.C./D.S. instructions into the full played-through sequence.
        - If a detail is smudged or ambiguous, choose the most musically plausible reading and continue — never insert comments or placeholders.

        Reply with only the MusicXML document.
        """
    }
}

// MARK: - Scan Settings (API key in Keychain, model in defaults)

@Observable
final class ScanSettings {
    static let shared = ScanSettings()

    /// Models offered in scan settings. Sonnet is the cost/quality sweet spot
    /// for clean printed music; Fable helps on dense or handwritten scores.
    static let availableModels: [(id: String, label: String)] = [
        ("claude-sonnet-5", "Sonnet 5 — fast, recommended"),
        ("claude-fable-5", "Fable 5 — highest accuracy"),
    ]

    var apiKey: String {
        didSet { KeychainStore.set(apiKey, forKey: Self.apiKeyAccount) }
    }

    var model: String {
        didSet { UserDefaults.standard.set(model, forKey: Self.modelKey) }
    }

    var hasAPIKey: Bool { !apiKey.trimmingCharacters(in: .whitespaces).isEmpty }

    private static let apiKeyAccount = "anthropic-api-key"
    private static let modelKey = "scanModel"

    private init() {
        apiKey = KeychainStore.get(Self.apiKeyAccount) ?? ""
        model = UserDefaults.standard.string(forKey: Self.modelKey) ?? "claude-sonnet-5"
    }

    func makeRecognizer() -> SheetMusicRecognizer {
        ClaudeSheetMusicRecognizer(apiKey: apiKey.trimmingCharacters(in: .whitespaces), model: model)
    }
}

// MARK: - Keychain

/// Minimal generic-password storage — API keys don't belong in UserDefaults.
enum KeychainStore {
    private static let service = "com.cascade.pianoinstructor"

    static func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String, forKey account: String) {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if trimmed.isEmpty {
            SecItemDelete(base as CFDictionary)
            return
        }
        let data = Data(trimmed.utf8)
        let status = SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = base
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(add as CFDictionary, nil)
        }
    }
}
