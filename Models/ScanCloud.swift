//
//  ScanCloud.swift
//  MyPianoInstructor
//
//  Cascade Cloud: the deployed cascade-scan worker that holds provider API
//  keys server-side. Users sign in with Apple, get free scans tied to their
//  account, and never touch an API key. When `ScanCloudConfig.baseURL` is nil
//  the app behaves exactly as before (bring-your-own-key only).
//

import Foundation
import AuthenticationServices
import Observation

enum ScanCloudConfig {
    /// The deployed cascade-scan worker URL, e.g.
    /// `URL(string: "https://cascade-scan.yourname.workers.dev")`.
    /// See server/cascade-scan-worker/README.md for the 5-minute deploy.
    /// nil = cloud mode off; the scan screen falls back to bring-your-own-key.
    static let baseURL: URL? = nil
}

enum ScanCloudError: LocalizedError {
    case notConfigured
    case appleSignInFailed
    case sessionExpired
    case outOfScans
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
            return "You've used all your free scans."
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
@MainActor
@Observable
final class ScanAccountManager {

    private(set) var isSignedIn: Bool
    private(set) var remainingScans: Int?
    private(set) var freeScans: Int?

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
        }

        var request = URLRequest(url: baseURL.appending(path: "v1/auth/apple"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONEncoder().encode(["identityToken": identityToken])

        let response: AuthResponse = try await ScanCloudAPI.send(request)
        KeychainStore.set(response.sessionToken, forKey: Self.sessionAccount)
        isSignedIn = true
        remainingScans = response.remainingScans
        freeScans = response.freeScans
    }

    /// Refreshes the remaining-scan count; silently signs out on a dead session.
    func refresh() async {
        guard let baseURL = ScanCloudConfig.baseURL, let token = sessionToken else { return }

        struct MeResponse: Decodable {
            let remainingScans: Int
            let freeScans: Int
        }

        var request = URLRequest(url: baseURL.appending(path: "v1/me"))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")

        do {
            let me: MeResponse = try await ScanCloudAPI.send(request)
            remainingScans = me.remainingScans
            freeScans = me.freeScans
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
    }
}

// MARK: - Cloud Recognizer

/// SheetMusicRecognizer backed by the cascade-scan worker. Drop-in replacement
/// for the direct-API recognizer; the capture/preview UI doesn't know the
/// difference.
struct CascadeCloudRecognizer: SheetMusicRecognizer {
    let baseURL: URL
    let sessionToken: String
    /// "standard" or "high" — the view escalates to "high" when a standard
    /// pass produces MusicXML that fails the app's own parser validation.
    var quality: String = "standard"

    nonisolated func recognize(pages: [Data]) async throws -> String {
        struct RecognizeResponse: Decodable {
            let musicXML: String
            let provider: String
            let cached: Bool
            let remainingScans: Int
        }

        var request = URLRequest(url: baseURL.appending(path: "v1/recognize"))
        request.httpMethod = "POST"
        request.timeoutInterval = 600
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "authorization")

        let body: [String: Any] = [
            "pages": pages.map { $0.base64EncodedString() },
            "quality": quality
        ]
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
            throw ScanCloudError.outOfScans
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
