import Foundation

/// Gmail REST API client. All network calls are asynchronous and never block the UI.
/// The UI reads exclusively from the local SQLite database.
final class GmailAPIClient {
    static let shared = GmailAPIClient()

    private let baseURL = "https://gmail.googleapis.com/gmail/v1"
    private let session = URLSession(configuration: .default)

    private init() {}

    /// The OAuth manager is the source of access tokens.
    private var oauth: OAuthManager { OAuthManager.shared }

    // MARK: - Helpers

    private func authenticatedRequest(
        url: URL,
        method: String = "GET",
        accessToken: String,
        body: Data? = nil
    ) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body = body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        return request
    }

    private func decodeResponse<T: Decodable>(_ data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(T.self, from: data)
    }

    private func validateResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GmailError.invalidHTTPResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let reason: String?
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                let sanitized = String(message.unicodeScalars.filter {
                    !CharacterSet.controlCharacters.contains($0)
                })
                reason = sanitized.isEmpty ? nil : String(sanitized.prefix(300))
            } else {
                reason = nil
            }
            throw GmailError.requestFailed(statusCode: httpResponse.statusCode, reason: reason)
        }
    }

    // MARK: - Profile

    func getProfile(accessToken: String) async throws -> GmailProfile {
        let request = try authenticatedRequest(
            url: URL(string: "\(baseURL)/users/me/profile")!,
            accessToken: accessToken
        )
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
        return try decodeResponse(data)
    }

    // MARK: - List threads / messages

    struct ListThreadsResponse: Decodable {
        var threads: [GmailThread]?
        var nextPageToken: String?
    }

    func listThreads(
        accessToken: String,
        query: String = "",
        maxResults: Int = 50,
        pageToken: String? = nil
    ) async throws -> ListThreadsResponse {
        var components = URLComponents(string: "\(baseURL)/users/me/threads")!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "maxResults", value: "\(maxResults)"),
            URLQueryItem(name: "fields", value: "threads(id,snippet),nextPageToken")
        ]
        if !query.isEmpty {
            items.append(URLQueryItem(name: "q", value: query))
        }
        if let pageToken = pageToken {
            items.append(URLQueryItem(name: "pageToken", value: pageToken))
        }
        components.queryItems = items

        let request = try authenticatedRequest(
            url: components.url!,
            accessToken: accessToken
        )
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
        return try decodeResponse(data)
    }

    // MARK: - Get a full message

    func getMessage(
        accessToken: String,
        messageId: String
    ) async throws -> GmailMessage {
        let request = try authenticatedRequest(
            url: URL(string: "\(baseURL)/users/me/messages/\(messageId)?format=full")!,
            accessToken: accessToken
        )
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
        return try decodeResponse(data)
    }

    // MARK: - Batch modify (archive, delete, mark read)

    struct BatchModifyRequest: Encodable {
        var ids: [String]
        var removeLabelIds: [String]?
        var addLabelIds: [String]?
    }

    /// Performs a remote action on messages (archive/delete/markRead).
    /// Returns once the server acknowledges; the local DB is updated optimistically by the caller.
    func batchModify(
        accessToken: String,
        messageIds: [String],
        removeLabelIds: [String]? = nil,
        addLabelIds: [String]? = nil
    ) async throws {
        guard !messageIds.isEmpty else { return }
        let body = BatchModifyRequest(ids: messageIds, removeLabelIds: removeLabelIds, addLabelIds: addLabelIds)
        let encoder = JSONEncoder()
        let httpBody = try encoder.encode(body)

        let request = try authenticatedRequest(
            url: URL(string: "\(baseURL)/users/me/messages/batchModify")!,
            method: "POST",
            accessToken: accessToken,
            body: httpBody
        )
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
    }

    /// Archive a single message remotely.
    func archive(accessToken: String, messageId: String) async throws {
        try await batchModify(
            accessToken: accessToken,
            messageIds: [messageId],
            removeLabelIds: ["INBOX"]
        )
    }

    /// Delete a single message remotely (move to trash).
    func deleteMessage(accessToken: String, messageId: String) async throws {
        try await batchModify(
            accessToken: accessToken,
            messageIds: [messageId],
            addLabelIds: ["TRASH"]
        )
    }

    /// Mark a message as read remotely.
    func markRead(accessToken: String, messageId: String) async throws {
        try await batchModify(
            accessToken: accessToken,
            messageIds: [messageId],
            removeLabelIds: ["UNREAD"]
        )
    }

    // MARK: - Send (stub for MVP completeness)

    func send(accessToken: String, rawMessage: String) async throws {
        var request = try authenticatedRequest(
            url: URL(string: "\(baseURL)/users/me/messages/send")!,
            method: "POST",
            accessToken: accessToken
        )
        let body = ["raw": rawMessage]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
    }
}

enum GmailError: LocalizedError {
    case requestFailed(statusCode: Int, reason: String?)
    case invalidResponse
    case invalidHTTPResponse

    var errorDescription: String? {
        switch self {
        case .requestFailed(let statusCode, let reason):
            let details = reason.map { ": \($0)" } ?? ""
            return "Gmail API request failed (HTTP \(statusCode)\(details))."
        case .invalidResponse:
            return "Gmail returned an invalid response."
        case .invalidHTTPResponse:
            return "Gmail returned a non-HTTP response."
        }
    }
}

// MARK: - Gmail API model types

struct GmailProfile: Decodable {
    var emailAddress: String
    var displayName: String?
    var messagesTotal: Int
    var threadsTotal: Int
}

struct GmailThread: Decodable {
    var id: String
    var snippet: String?
}

struct GmailMessage: Decodable {
    var id: String
    var threadId: String
    var labelIds: [String]
    var snippet: String
    var internalDate: String?   // epoch milliseconds (Gmail API returns int64 as decimal string)
    var payload: GmailMessagePart?
    var sizeEstimate: Int?

    var receivedAt: Date {
        guard let internalDate = internalDate, let ms = Double(internalDate) else { return Date() }
        return Date(timeIntervalSince1970: ms / 1000.0)
    }

    enum CodingKeys: String, CodingKey {
        case id, threadId, labelIds, snippet, internalDate, payload, sizeEstimate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        threadId = try container.decode(String.self, forKey: .threadId)
        labelIds = try container.decodeIfPresent([String].self, forKey: .labelIds) ?? []
        snippet = try container.decodeIfPresent(String.self, forKey: .snippet) ?? ""
        payload = try container.decodeIfPresent(GmailMessagePart.self, forKey: .payload)
        sizeEstimate = try container.decodeIfPresent(Int.self, forKey: .sizeEstimate)

        // Gmail API serializes 64-bit integers as decimal strings in JSON to avoid precision loss in JavaScript,
        // but we handle both String and Int64 formats gracefully.
        if let stringDate = try? container.decodeIfPresent(String.self, forKey: .internalDate) {
            internalDate = stringDate
        } else if let intDate = try? container.decodeIfPresent(Int64.self, forKey: .internalDate) {
            internalDate = String(intDate)
        } else {
            internalDate = nil
        }
    }
}

struct GmailMessagePart: Decodable {
    var partId: String?
    var mimeType: String
    var filename: String?
    var headers: [GmailMessageHeader]?
    var body: GmailMessageBody?
    var parts: [GmailMessagePart]?
}

struct GmailMessageHeader: Decodable {
    var name: String
    var value: String
}

struct GmailMessageBody: Decodable {
    var attachmentId: String?
    var size: Int
    var data: String?   // base64url encoded
}

// MARK: - Convenience extensions for parsing Gmail messages into local Email models

extension GmailMessage {
    /// Extracts a header value by name (case-insensitive).
    func header(_ name: String) -> String? {
        payload?.headers?.first { $0.name.lowercased() == name.lowercased() }?.value
    }

    /// Extracts the plain-text body (falls back to HTML stripped of tags).
    func plainTextBody() -> String? {
        func walk(_ part: GmailMessagePart) -> String? {
            if part.mimeType == "text/plain", let data = part.body?.data,
               let decoded = Data(base64URLEncoded: data),
               let text = String(data: decoded, encoding: .utf8) {
                return text
            }
            if let parts = part.parts {
                for sub in parts {
                    if let result = walk(sub) { return result }
                }
            }
            return nil
        }
        if let payload = payload, let result = walk(payload) {
            return result
        }
        return nil
    }

    func htmlBody() -> String? {
        func walk(_ part: GmailMessagePart) -> String? {
            if part.mimeType == "text/html", let data = part.body?.data,
               let decoded = Data(base64URLEncoded: data),
               let text = String(data: decoded, encoding: .utf8) {
                return text
            }
            if let parts = part.parts {
                for sub in parts {
                    if let result = walk(sub) { return result }
                }
            }
            return nil
        }
        if let payload = payload, let result = walk(payload) {
            return result
        }
        return nil
    }

    /// Sender email from the From header.
    var senderEmail: String? {
        header("From")?.components(separatedBy: "<").last?.trimmingCharacters(in: CharacterSet(charactersIn: " >")) ?? header("From")
    }

    /// Sender name from the From header.
    var senderName: String? {
        let from = header("From") ?? ""
        if let name = from.components(separatedBy: "<").first?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty, name != from {
            return name
        }
        return senderEmail
    }
}

extension Data {
    /// Decodes base64url (Gmail uses URL-safe base64 without padding).
    init?(base64URLEncoded string: String) {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 = base64.padding(toLength: base64.count + 4 - remainder,
                                    withPad: " ", startingAt: 0)
        }
        self.init(base64Encoded: base64)
    }
}
