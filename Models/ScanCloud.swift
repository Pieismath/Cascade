//
//  ScanCloud.swift
//  MyPianoInstructor
//
//  Cascade's scan service: the deployed cascade-scan worker. Users sign in
//  with Apple, get a free scan tied to their account, and buy scan packs for
//  more. Recognition credentials live only on the server.
//

import Foundation
import AuthenticationServices
import Observation

enum ScanCloudConfig {
    /// The deployed cascade-scan worker. See server/cascade-scan-worker/README.md.
    /// nil turns scanning off (the scan screen says it's unavailable).
    static let baseURL: URL? = URL(string: "https://cascade-scan.jaydfds.workers.dev")

    /// Pages per scan the UI allows; matches the worker's MAX_PAGES_PER_SCAN.
    static let maxPagesPerScan = 12

    /// Hosted privacy policy, linked from scan settings and required by App
    /// Store Connect. Host docs/privacy-policy.md (GitHub Pages works), paste
    /// the public URL here, and the link appears in the app automatically.
    static let privacyPolicyURL: URL? = nil
}

enum ScanCloudError: LocalizedError {
    case notConfigured
    case appleSignInFailed
    case sessionExpired
    case outOfScans
    case insufficientCredits(needed: Int, remaining: Int, message: String)
    case rateLimited
    case invalidPurchase(String)
    case network(String)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Cloud scanning isn't configured in this build."
        case .appleSignInFailed:
            return "Sign in with Apple didn't return a usable credential. Please try again."
        case .sessionExpired:
            return "Your session expired. Please sign in again."
        case .outOfScans:
            return "You're out of scans."
        case .insufficientCredits(_, _, let message):
            return message
        case .rateLimited:
            return "Too many scan requests. Please wait a minute and try again."
        case .invalidPurchase(let message):
            return message
        case .network(let detail):
            return "Network error: \(detail)"
        case .server(let message):
            return message
        }
    }
}

// MARK: - Account (session + quota)

/// Owns the Cascade Cloud session: exchanges the Apple identity token for a
/// long-lived session token (Keychain), and tracks remaining free scans.
/// The worker's balance envelope, returned by every account endpoint.
nonisolated struct ScanBalance: Decodable, Sendable {
    let remainingScans: Int
    let freeScans: Int
    let freeRemaining: Int?
    let credits: Int?
    let pagesPerCredit: Int?
}

@MainActor
@Observable
final class ScanAccountManager {

    private(set) var isSignedIn: Bool
    private(set) var remainingScans: Int?
    private(set) var freeScans: Int?
    private(set) var freeRemaining: Int?
    private(set) var credits: Int?
    private(set) var pagesPerCredit: Int = 4

    /// Credits a scan of `pageCount` pages will cost.
    func creditsNeeded(forPages pageCount: Int) -> Int {
        max(1, Int((Double(max(1, pageCount)) / Double(max(1, pagesPerCredit))).rounded(.up)))
    }

    func apply(_ balance: ScanBalance) {
        remainingScans = balance.remainingScans
        freeScans = balance.freeScans
        freeRemaining = balance.freeRemaining
        credits = balance.credits
        if let p = balance.pagesPerCredit, p > 0 { pagesPerCredit = p }
    }

    private static let sessionAccount = "cloud-session-token"

    var sessionToken: String? { KeychainStore.get(Self.sessionAccount) }

    init() {
        isSignedIn = KeychainStore.get(Self.sessionAccount) != nil
    }

    /// Completes Sign in with Apple: sends the identity token to the worker,
    /// which verifies it with Apple and returns our own session token.
    func signIn(with authorization: ASAuthorization) async throws {
        guard let baseURL = ScanCloudConfig.baseURL else { throw ScanCloudError.notConfigured }
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let identityToken = String(data: tokenData, encoding: .utf8) else {
            throw ScanCloudError.appleSignInFailed
        }

        struct AuthResponse: Decodable {
            let sessionToken: String
            let remainingScans: Int
            let freeScans: Int
            let freeRemaining: Int?
            let credits: Int?
            let pagesPerCredit: Int?
        }

        var request = URLRequest(url: baseURL.appending(path: "v1/auth/apple"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONEncoder().encode(["identityToken": identityToken])

        let response: AuthResponse = try await ScanCloudAPI.send(request)
        KeychainStore.set(response.sessionToken, forKey: Self.sessionAccount)
        isSignedIn = true
        apply(ScanBalance(remainingScans: response.remainingScans, freeScans: response.freeScans,
                          freeRemaining: response.freeRemaining, credits: response.credits,
                          pagesPerCredit: response.pagesPerCredit))
    }

    /// Refreshes the remaining-scan count; silently signs out on a dead session.
    func refresh() async {
        guard let baseURL = ScanCloudConfig.baseURL, let token = sessionToken else { return }

        var request = URLRequest(url: baseURL.appending(path: "v1/me"))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")

        do {
            let me: ScanBalance = try await ScanCloudAPI.send(request)
            apply(me)
        } catch ScanCloudError.sessionExpired {
            signOut()
        } catch {
            // Transient network problems shouldn't log the user out.
        }
    }

    func signOut() {
        KeychainStore.set("", forKey: Self.sessionAccount)
        isSignedIn = false
        remainingScans = nil
        freeScans = nil
        freeRemaining = nil
        credits = nil
    }

    struct RedeemResult: Decodable {
        let added: Int
        let alreadyRedeemed: Bool
        let remainingScans: Int
        let freeScans: Int
        let freeRemaining: Int?
        let credits: Int?
        let pagesPerCredit: Int?
    }

    /// Sends a StoreKit 2 signed transaction to the worker, which verifies
    /// Apple's signature and grants the pack's credits (once per transaction).
    func redeem(signedTransaction: String) async throws -> RedeemResult {
        guard let baseURL = ScanCloudConfig.baseURL else { throw ScanCloudError.notConfigured }
        guard let token = sessionToken else { throw ScanCloudError.sessionExpired }

        var request = URLRequest(url: baseURL.appending(path: "v1/purchases/redeem"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
        request.httpBody = try JSONEncoder().encode(["signedTransaction": signedTransaction])

        let result: RedeemResult = try await ScanCloudAPI.send(request)
        apply(ScanBalance(remainingScans: result.remainingScans, freeScans: result.freeScans,
                          freeRemaining: result.freeRemaining, credits: result.credits,
                          pagesPerCredit: result.pagesPerCredit))
        return result
    }

    /// Deletes the server-side account record (scan usage) and signs out.
    /// Required by App Store guideline 5.1.1(v) for any app with sign-in.
    func deleteAccount() async throws {
        guard let baseURL = ScanCloudConfig.baseURL else { throw ScanCloudError.notConfigured }
        guard let token = sessionToken else {
            signOut()
            return
        }

        struct DeleteResponse: Decodable { let deleted: Bool }

        var request = URLRequest(url: baseURL.appending(path: "v1/account"))
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")

        do {
            let _: DeleteResponse = try await ScanCloudAPI.send(request)
        } catch ScanCloudError.sessionExpired {
            // Nothing server-side to delete for a dead session.
        }
        signOut()
    }
}

// MARK: - Cloud Recognizer

/// SheetMusicRecognizer backed by the cascade-scan worker.
struct CascadeCloudRecognizer: SheetMusicRecognizer {
    let baseURL: URL
    let sessionToken: String
    /// "standard" or "high" — the view escalates to "high" when a standard
    /// pass produces MusicXML that fails the app's own parser validation.
    var quality: String = "standard"

    nonisolated func recognize(pages: [Data], pageCount: Int, context: String?, jobID: String?) async throws -> String {
        struct RecognizeResponse: Decodable {
            let musicXML: String
        }

        var request = URLRequest(url: baseURL.appending(path: "v1/recognize"))
        request.httpMethod = "POST"
        request.timeoutInterval = 600
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "authorization")

        var body: [String: Any] = [
            "pages": pages.map { $0.base64EncodedString() },
            "pageCount": max(1, pageCount),
            "quality": quality
        ]
        if let context, !context.isEmpty { body["context"] = context }
        if let jobID { body["jobId"] = jobID }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let response: RecognizeResponse = try await ScanCloudAPI.send(request)
        return response.musicXML
    }
}

// MARK: - Shared request plumbing

enum ScanCloudAPI {

    private nonisolated struct APIErrorEnvelope: Decodable {
        nonisolated struct Payload: Decodable {
            let code: String
            let message: String
            let needed: Int?
            let remaining: Int?
        }
        let error: Payload
    }

    /// Sends a request and decodes the response, mapping the worker's error
    /// envelope onto typed errors the UI knows how to present.
    nonisolated static func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ScanCloudError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw ScanCloudError.network("invalid response")
        }

        if http.statusCode == 200 {
            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                throw ScanCloudError.server("Unexpected response from the scan service.")
            }
        }

        let envelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data)
        let message = envelope?.error.message ?? "The scan service returned an error (\(http.statusCode))."

        switch http.statusCode {
        case 401:
            throw ScanCloudError.sessionExpired
        case 402:
            if let payload = envelope?.error, payload.code == "insufficient_credits" {
                throw ScanCloudError.insufficientCredits(
                    needed: payload.needed ?? 1, remaining: payload.remaining ?? 0, message: payload.message)
            }
            throw ScanCloudError.outOfScans
        case 429:
            throw ScanCloudError.rateLimited
        case 400 where envelope?.error.code == "invalid_purchase" || envelope?.error.code == "unknown_product":
            throw ScanCloudError.invalidPurchase(message)
        case 503:
            throw ScanCloudError.server("Scanning is temporarily unavailable. Please try again later.")
        case 422:
            if envelope?.error.code == "too_long" {
                throw SheetMusicRecognitionError.truncatedResult
            }
            throw SheetMusicRecognitionError.unreadableScore(message)
        default:
            throw ScanCloudError.server(message)
        }
    }
}
