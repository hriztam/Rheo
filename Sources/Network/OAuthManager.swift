import Foundation
import AppKit
import CryptoKit
import Network
import Security

/// Handles OAuth 2.0 authentication with Gmail using the installed-app loopback flow.
/// Tokens are stored in the Keychain via KeychainManager.
final class OAuthManager {
    static let shared = OAuthManager()

    // Gmail OAuth configuration
    private let clientID: String
    private let clientSecret: String?
    private let environmentFileError: Error?
    private let scopes = "https://www.googleapis.com/auth/gmail.modify https://www.googleapis.com/auth/gmail.readonly https://www.googleapis.com/auth/gmail.send"

    private init() {
        let envFileValues: [String: String]
        do {
            envFileValues = try Self.loadEnvironmentFile()
            self.environmentFileError = nil
        } catch {
            envFileValues = [:]
            self.environmentFileError = error
        }

        let environment = ProcessInfo.processInfo.environment
        self.clientID = environment["GMAIL_CLIENT_ID"]
            ?? envFileValues["GMAIL_CLIENT_ID"]
            ?? Bundle.main.object(forInfoDictionaryKey: "GMAIL_CLIENT_ID") as? String
            ?? ""
        let configuredClientSecret = environment["GMAIL_CLIENT_SECRET"]
            ?? envFileValues["GMAIL_CLIENT_SECRET"]
            ?? Bundle.main.object(forInfoDictionaryKey: "GMAIL_CLIENT_SECRET") as? String
        self.clientSecret = configuredClientSecret.flatMap { value in
            let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedValue.isEmpty ? nil : trimmedValue
        }
    }

    private static func loadEnvironmentFile() throws -> [String: String] {
        let fileManager = FileManager.default
        let startDirectories = [
            URL(fileURLWithPath: fileManager.currentDirectoryPath),
            Bundle.main.executableURL?.deletingLastPathComponent()
        ].compactMap { $0 }

        for startDirectory in startDirectories {
            var directory = startDirectory
            while true {
                let fileURL = directory.appendingPathComponent(".env")
                if fileManager.fileExists(atPath: fileURL.path) {
                    let contents = try String(contentsOf: fileURL, encoding: .utf8)
                    return try parseEnvironmentFile(contents)
                }

                let parent = directory.deletingLastPathComponent()
                guard parent.path != directory.path else { break }
                directory = parent
            }
        }

        return [:]
    }

    private static func parseEnvironmentFile(_ contents: String) throws -> [String: String] {
        var values: [String: String] = [:]

        for (index, line) in contents.components(separatedBy: .newlines).enumerated() {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            guard !trimmedLine.isEmpty, !trimmedLine.hasPrefix("#") else { continue }

            let assignment = trimmedLine.hasPrefix("export ")
                ? String(trimmedLine.dropFirst("export ".count))
                : trimmedLine
            guard let separator = assignment.firstIndex(of: "=") else {
                throw OAuthError.invalidEnvironmentFileLine(index + 1)
            }

            let key = assignment[..<separator].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else {
                throw OAuthError.invalidEnvironmentFileLine(index + 1)
            }

            var value = assignment[assignment.index(after: separator)...]
                .trimmingCharacters(in: .whitespaces)
            if value.count >= 2,
               (value.first == "\"" && value.last == "\"")
                   || (value.first == "'" && value.last == "'") {
                value.removeFirst()
                value.removeLast()
            }
            values[key] = value
        }

        return values
    }

    struct OAuthResult {
        let accessToken: String
        let refreshToken: String
        let expiresIn: Int
    }

    /// Starts the OAuth flow. Returns tokens on success.
    func authenticate() async throws -> OAuthResult {
        if let environmentFileError {
            throw environmentFileError
        }
        guard !clientID.isEmpty else {
            throw OAuthError.missingClientID
        }

        let verifier = try Self.randomBase64URLString(byteCount: 32)
        let challenge = Self.base64URLString(Data(SHA256.hash(data: Data(verifier.utf8))))
        let state = try Self.randomBase64URLString(byteCount: 32)
        let callbackServer = try LoopbackOAuthCallbackServer(expectedState: state)
        let port = try await callbackServer.start()
        defer { callbackServer.stop() }

        let redirectURI = "http://127.0.0.1:\(port)"
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "include_granted_scopes", value: "true"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state)
        ]
        guard let authURL = components.url else {
            throw OAuthError.invalidAuthURL
        }

        let callbackTask = Task {
            try await callbackServer.waitForCallback()
        }
        guard NSWorkspace.shared.open(authURL) else {
            callbackServer.stop(with: OAuthError.browserOpenFailed)
            throw OAuthError.browserOpenFailed
        }

        let callbackURL = try await callbackTask.value
        guard let callbackComponents = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let code = callbackComponents.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw OAuthError.missingAuthCode
        }

        return try await exchangeCodeForTokens(
            code: code,
            redirectURI: redirectURI,
            codeVerifier: verifier
        )
    }

    private static func randomBase64URLString(byteCount: Int) throws -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw OAuthError.randomGenerationFailed
        }
        return base64URLString(Data(bytes))
    }

    private static func base64URLString(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Exchanges the authorization code for access + refresh tokens.
    private func exchangeCodeForTokens(
        code: String,
        redirectURI: String,
        codeVerifier: String
    ) async throws -> OAuthResult {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var parameters = [
            "code": code,
            "client_id": clientID,
            "redirect_uri": redirectURI,
            "code_verifier": codeVerifier,
            "grant_type": "authorization_code"
        ]
        if let clientSecret {
            parameters["client_secret"] = clientSecret
        }
        request.httpBody = Self.formBody(parameters)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OAuthError.invalidTokenHTTPResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw OAuthError.tokenExchangeFailed(
                statusCode: httpResponse.statusCode,
                reason: Self.oauthErrorReason(from: data)
            )
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

    private static func formBody(_ values: [String: String]) -> Data {
        var components = URLComponents()
        components.queryItems = values.map { URLQueryItem(name: $0.key, value: $0.value) }
        return Data((components.percentEncodedQuery ?? "").utf8)
    }

    private static func oauthErrorReason(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let details = ["error", "error_description"].compactMap { key -> String? in
            guard let value = json[key] as? String else { return nil }
            let sanitized = String(value.unicodeScalars.filter {
                !CharacterSet.controlCharacters.contains($0)
            })
            guard !sanitized.isEmpty else { return nil }
            return String(sanitized.prefix(300))
        }
        return details.isEmpty ? nil : details.joined(separator: ": ")
    }

    /// Refreshes an access token using a stored refresh token.
    func refreshAccessToken(refreshToken: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var parameters = [
            "client_id": clientID,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]
        if let clientSecret {
            parameters["client_secret"] = clientSecret
        }
        request.httpBody = Self.formBody(parameters)

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

private final class LoopbackOAuthCallbackServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "com.keyboardmail.oauth-callback")
    private let expectedState: String
    private var startupContinuation: CheckedContinuation<UInt16, Error>?
    private var callbackContinuation: CheckedContinuation<URL, Error>?
    private var callbackResult: Result<URL, Error>?

    init(expectedState: String) throws {
        self.expectedState = expectedState
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(
            host: NWEndpoint.Host("127.0.0.1"),
            port: .any
        )
        self.listener = try NWListener(using: parameters)
    }

    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                self.startupContinuation = continuation
                self.listener.stateUpdateHandler = { [weak self] state in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        guard let port = self.listener.port?.rawValue else {
                            self.resumeStartup(throwing: OAuthError.callbackServerFailed)
                            return
                        }
                        self.resumeStartup(returning: port)
                    case .failed:
                        self.resumeStartup(throwing: OAuthError.callbackServerFailed)
                        self.finishCallback(throwing: OAuthError.callbackServerFailed)
                    case .cancelled:
                        self.finishCallback(throwing: OAuthError.callbackServerStopped)
                    default:
                        break
                    }
                }
                self.listener.newConnectionHandler = { [weak self] connection in
                    self?.handle(connection)
                }
                self.listener.start(queue: self.queue)
            }
        }
    }

    func waitForCallback() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                if let result = self.callbackResult {
                    continuation.resume(with: result)
                } else {
                    self.callbackContinuation = continuation
                }
            }
        }
    }

    func stop(with error: Error = OAuthError.callbackServerStopped) {
        queue.async {
            self.listener.cancel()
            self.finishCallback(throwing: error)
        }
    }

    private func resumeStartup(returning port: UInt16) {
        startupContinuation?.resume(returning: port)
        startupContinuation = nil
    }

    private func resumeStartup(throwing error: Error) {
        startupContinuation?.resume(throwing: error)
        startupContinuation = nil
    }

    private func finishCallback(returning url: URL) {
        finishCallback(with: .success(url))
    }

    private func finishCallback(throwing error: Error) {
        finishCallback(with: .failure(error))
    }

    private func finishCallback(with result: Result<URL, Error>) {
        guard callbackResult == nil else { return }
        callbackResult = result
        callbackContinuation?.resume(with: result)
        callbackContinuation = nil
        listener.cancel()
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(on: connection, data: Data())
    }

    private func receiveRequest(on connection: NWConnection, data: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] receivedData, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }

            var requestData = data
            if let receivedData {
                requestData.append(receivedData)
            }

            if let headerEnd = requestData.range(of: Data("\r\n\r\n".utf8)) {
                self.processRequest(requestData.prefix(upTo: headerEnd.lowerBound), on: connection)
            } else if isComplete || error != nil || requestData.count >= 16_384 {
                self.sendResponse(
                    status: "400 Bad Request",
                    message: "Invalid OAuth callback request.",
                    on: connection
                )
            } else {
                self.receiveRequest(on: connection, data: requestData)
            }
        }
    }

    private func processRequest(_ data: Data, on connection: NWConnection) {
        guard let headers = String(data: data, encoding: .utf8),
              let requestLine = headers.components(separatedBy: "\r\n").first else {
            sendResponse(
                status: "400 Bad Request",
                message: "Invalid OAuth callback request. You can close this tab.",
                on: connection,
                completion: { self.finishCallback(throwing: OAuthError.invalidOAuthCallback) }
            )
            return
        }

        let requestParts = requestLine.split(separator: " ")
        guard requestParts.count == 3,
              requestParts[0] == "GET",
              let target = requestParts.dropFirst().first,
              let url = URL(string: "http://127.0.0.1\(target)"),
              url.path == "/",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.queryItems?.first(where: { $0.name == "state" })?.value == expectedState else {
            sendResponse(
                status: "400 Bad Request",
                message: "OAuth callback validation failed. You can close this tab.",
                on: connection,
                completion: { self.finishCallback(throwing: OAuthError.invalidOAuthCallback) }
            )
            return
        }

        if let error = components.queryItems?.first(where: { $0.name == "error" })?.value {
            sendResponse(
                status: "200 OK",
                message: "Google sign-in was not completed. You can close this tab.",
                on: connection,
                completion: { self.finishCallback(throwing: OAuthError.authorizationDenied(error)) }
            )
            return
        }

        guard components.queryItems?.contains(where: { $0.name == "code" && $0.value != nil }) == true else {
            sendResponse(
                status: "400 Bad Request",
                message: "Google did not return an authorization code. You can close this tab.",
                on: connection,
                completion: { self.finishCallback(throwing: OAuthError.missingAuthCode) }
            )
            return
        }

        sendResponse(
            status: "200 OK",
            message: "Sign-in complete. You can close this tab and return to Rheo.",
            on: connection,
            completion: { self.finishCallback(returning: url) }
        )
    }

    private func sendResponse(
        status: String,
        message: String,
        on connection: NWConnection,
        completion: @escaping () -> Void = {}
    ) {
        let body = """
        <!doctype html><html><head><meta charset="utf-8"><title>Rheo</title></head>
        <body><p>\(message)</p></body></html>
        """
        let response = [
            "HTTP/1.1 \(status)",
            "Content-Type: text/html; charset=utf-8",
            "Content-Length: \(body.utf8.count)",
            "Connection: close",
            "",
            body
        ].joined(separator: "\r\n")
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
            completion()
        })
    }
}

enum OAuthError: LocalizedError {
    case missingClientID
    case invalidEnvironmentFileLine(Int)
    case invalidAuthURL
    case randomGenerationFailed
    case browserOpenFailed
    case callbackServerFailed
    case callbackServerStopped
    case invalidOAuthCallback
    case authorizationDenied(String)
    case missingAuthCode
    case invalidTokenHTTPResponse
    case tokenExchangeFailed(statusCode: Int, reason: String?)
    case tokenRefreshFailed
    case invalidTokenResponse

    var errorDescription: String? {
        switch self {
        case .missingClientID:
            return "GMAIL_CLIENT_ID is missing. Add your Google Desktop OAuth client ID to .env."
        case .invalidEnvironmentFileLine(let line):
            return ".env has an invalid entry on line \(line). Use KEY=value format."
        case .invalidAuthURL:
            return "Could not create the Google sign-in URL."
        case .randomGenerationFailed:
            return "Could not securely initialize the Google sign-in request."
        case .browserOpenFailed:
            return "Could not open the system browser for Google sign-in."
        case .callbackServerFailed:
            return "Could not start the local OAuth callback server."
        case .callbackServerStopped:
            return "The local OAuth callback server stopped before sign-in completed."
        case .invalidOAuthCallback:
            return "Google sign-in returned an invalid callback. Please try again."
        case .authorizationDenied(let reason):
            return "Google sign-in was not completed: \(reason)."
        case .missingAuthCode:
            return "Google did not return an authorization code."
        case .invalidTokenHTTPResponse:
            return "Google returned an invalid response while exchanging the authorization code."
        case .tokenExchangeFailed(let statusCode, let reason):
            let details = reason.map { ": \($0)" } ?? ""
            return "Google rejected the authorization code (HTTP \(statusCode)\(details)). Check that the OAuth client is a Desktop app and try again."
        case .tokenRefreshFailed:
            return "Google rejected the saved refresh token. Sign in to the account again."
        case .invalidTokenResponse:
            return "Google returned an incomplete token response. Check the OAuth client configuration."
        }
    }
}
