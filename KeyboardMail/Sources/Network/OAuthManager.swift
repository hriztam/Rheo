import Foundation
import AuthenticationServices
import AppKit

/// Handles OAuth 2.0 authentication with Gmail via ASWebAuthenticationSession.
/// Tokens are stored in the Keychain via KeychainManager.
final class OAuthManager: NSObject {
    static let shared = OAuthManager()

    // Gmail OAuth configuration
    private let clientID: String
    private let clientSecret: String
    private let redirectURI: String
    private let scopes = "https://www.googleapis.com/auth/gmail.modify https://www.googleapis.com/auth/gmail.readonly https://www.googleapis.com/auth/gmail.send"

    private var authSession: ASWebAuthenticationSession?
    private var continuation: CheckedContinuation<OAuthResult, Error>?

    override init() {
        // These should ideally come from an Info.plist / build configuration.
        // For the MVP we load from environment or bundled config.
        self.clientID = Bundle.main.object(forInfoDictionaryKey: "GMAIL_CLIENT_ID") as? String
            ?? ProcessInfo.processInfo.environment["GMAIL_CLIENT_ID"] ?? ""
        self.clientSecret = Bundle.main.object(forInfoDictionaryKey: "GMAIL_CLIENT_SECRET") as? String
            ?? ProcessInfo.processInfo.environment["GMAIL_CLIENT_SECRET"] ?? ""
        self.redirectURI = Bundle.main.object(forInfoDictionaryKey: "GMAIL_REDIRECT_URI") as? String
            ?? "com.keyboardmail.oauth://callback"
    }

    struct OAuthResult {
        let accessToken: String
        let refreshToken: String
        let expiresIn: Int
    }

    /// Starts the OAuth flow. Returns tokens on success.
    func authenticate() async throws -> OAuthResult {
        guard !clientID.isEmpty else {
            throw OAuthError.missingClientID
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
            components.queryItems = [
                URLQueryItem(name: "client_id", value: clientID),
                URLQueryItem(name: "redirect_uri", value: redirectURI),
                URLQueryItem(name: "response_type", value: "code"),
                URLQueryItem(name: "scope", value: scopes),
                URLQueryItem(name: "access_type", value: "offline"),
                URLQueryItem(name: "prompt", value: "consent"),
                URLQueryItem(name: "include_granted_scopes", value: "true")
            ]

            guard let authURL = components.url else {
                continuation.resume(throwing: OAuthError.invalidAuthURL)
                return
            }

            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: redirectURI.components(separatedBy: "://").first
            ) { [weak self] callbackURL, error in
                self?.handleAuthCallback(callbackURL: callbackURL, error: error)
            }

            session.presentationContextProvider = self
            self.authSession = session

            if !session.start() {
                continuation.resume(throwing: OAuthError.sessionStartFailed)
            }
        }
    }

    private func handleAuthCallback(callbackURL: URL?, error: Error?) {
        defer { self.continuation = nil; self.authSession = nil }

        if let error = error {
            continuation?.resume(throwing: error)
            return
        }

        guard let callbackURL = callbackURL,
              let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: true),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value
        else {
            continuation?.resume(throwing: OAuthError.missingAuthCode)
            return
        }

        Task {
            do {
                let result = try await exchangeCodeForTokens(code: code)
                continuation?.resume(returning: result)
            } catch {
                continuation?.resume(throwing: error)
            }
        }
    }

    /// Exchanges the authorization code for access + refresh tokens.
    private func exchangeCodeForTokens(code: String) async throws -> OAuthResult {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "code": code,
            "client_id": clientID,
            "client_secret": clientSecret,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code"
        ]
        request.httpBody = body.map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode)
        else {
            throw OAuthError.tokenExchangeFailed
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        guard let accessToken = json["access_token"] as? String,
              let refreshToken = json["refresh_token"] as? String
        else {
            throw OAuthError.invalidTokenResponse
        }

        let expiresIn = json["expires_in"] as? Int ?? 3600
        return OAuthResult(accessToken: accessToken, refreshToken: refreshToken, expiresIn: expiresIn)
    }

    /// Refreshes an access token using a stored refresh token.
    func refreshAccessToken(refreshToken: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "client_id": clientID,
            "client_secret": clientSecret,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]
        request.httpBody = body.map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode)
        else {
            throw OAuthError.tokenRefreshFailed
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        guard let accessToken = json["access_token"] as? String else {
            throw OAuthError.invalidTokenResponse
        }
        return accessToken
    }
}

extension OAuthManager: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApplication.shared.windows.first ?? NSWindow()
    }
}

enum OAuthError: Error {
    case missingClientID
    case invalidAuthURL
    case sessionStartFailed
    case missingAuthCode
    case tokenExchangeFailed
    case tokenRefreshFailed
    case invalidTokenResponse
}
