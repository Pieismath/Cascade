//
//  SheetMusicRecognition.swift
//  MyPianoInstructor
//
//  Optical music recognition: turns photographed or imported sheet-music pages
//  into MusicXML that feeds the existing parse → falling-notes pipeline.
//
//  Recognition runs behind the SheetMusicRecognizer protocol so the backend is
//  swappable. The app ships one backend, Cascade's own scan service
//  (CascadeCloudRecognizer in ScanCloud.swift); the service returns MusicXML
//  constrained to the subset MusicXMLParser understands.
//

import UIKit
import Security

// MARK: - Errors

enum SheetMusicRecognitionError: LocalizedError {
    case imageEncodingFailed
    case truncatedResult
    case unreadableScore(String)

    var errorDescription: String? {
        switch self {
        case .imageEncodingFailed:
            return "The page images could not be prepared for upload."
        case .truncatedResult:
            return "The piece is too long to transcribe in one pass. Try scanning fewer pages at a time."
        case .unreadableScore(let detail):
            return detail
        }
    }
}

// MARK: - Recognizer Protocol

protocol SheetMusicRecognizer {
    /// Converts sheet-music images (JPEG data, in reading order) to MusicXML.
    /// `context` carries continuation guidance for multi-request jobs and
    /// `jobID` groups those requests for quota purposes (cloud only).
    /// Nonisolated so encoding and network work stay off the main actor.
    /// `pageCount` is the number of source pages in the whole scan (credit cost).
    nonisolated func recognize(pages: [Data], pageCount: Int, context: String?, jobID: String?) async throws -> String
}

extension SheetMusicRecognizer {
    nonisolated func recognize(pages: [Data]) async throws -> String {
        try await recognize(pages: pages, pageCount: pages.count, context: nil, jobID: nil)
    }
}

// MARK: - Validation

/// A recognition result that survived parsing, ready to preview and save.
struct RecognizedScore {
    let musicXML: String
    let playback: PlaybackData
    /// Rhythm sanity report — which measures don't add up to the time signature.
    let measureReport: MeasureChecker.Report
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
        return RecognizedScore(
            musicXML: musicXML,
            playback: playback,
            measureReport: MeasureChecker.check(musicXML: musicXML)
        )
    }
}

// MARK: - Page Image Preparation

nonisolated enum SheetPagePrep {
    /// Longest edge uploaded for recognition — larger is wasted bandwidth,
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

// MARK: - Keychain

/// Minimal generic-password storage for the scan-service session token.
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
