import Foundation
import GRDB

/// A Gmail account connected to the app.
/// OAuth tokens are stored in the Keychain, not in the database.
struct Account: Codable, FetchableRecord, PersistableRecord, Identifiable {
    static var databaseTableName = "accounts"
    static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase
    static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase

    var id: Int64?
    var email: String
    var displayName: String
    var avatarURL: String?
    var createdAt: Date

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let email = Column(CodingKeys.email)
        static let displayName = Column("display_name")
        static let avatarURL = Column("avatar_url")
        static let createdAt = Column("created_at")
    }

    init(id: Int64? = nil, email: String, displayName: String, avatarURL: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.createdAt = createdAt
    }
}

/// An email message, stored locally for instant UI rendering.
struct Email: Codable, FetchableRecord, PersistableRecord, Identifiable {
    static var databaseTableName = "emails"
    static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase
    static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase

    /// Gmail message ID (unique within an account)
    var id: String
    var threadId: String
    var accountId: Int64
    var senderName: String
    var senderEmail: String
    var recipientEmails: String        // JSON-encoded array of recipient addresses
    var subject: String
    var snippet: String
    var bodyHTML: String?
    var bodyText: String?
    var receivedAt: Date
    var isRead: Bool
    var isArchived: Bool
    var isStarred: Bool
    var category: EmailCategory

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let threadId = Column("thread_id")
        static let accountId = Column("account_id")
        static let senderName = Column("sender_name")
        static let senderEmail = Column("sender_email")
        static let recipientEmails = Column("recipient_emails")
        static let subject = Column(CodingKeys.subject)
        static let snippet = Column(CodingKeys.snippet)
        static let bodyHTML = Column("body_html")
        static let bodyText = Column("body_text")
        static let receivedAt = Column("received_at")
        static let isRead = Column("is_read")
        static let isArchived = Column("is_archived")
        static let isStarred = Column("is_starred")
        static let category = Column(CodingKeys.category)
    }

    init(
        id: String,
        threadId: String,
        accountId: Int64,
        senderName: String,
        senderEmail: String,
        recipientEmails: [String] = [],
        subject: String,
        snippet: String,
        bodyHTML: String? = nil,
        bodyText: String? = nil,
        receivedAt: Date = Date(),
        isRead: Bool = false,
        isArchived: Bool = false,
        isStarred: Bool = false,
        category: EmailCategory = .important
    ) {
        self.id = id
        self.threadId = threadId
        self.accountId = accountId
        self.senderName = senderName
        self.senderEmail = senderEmail
        self.recipientEmails = recipientEmails.jsonEncoded ?? "[]"
        self.subject = subject
        self.snippet = snippet
        self.bodyHTML = bodyHTML
        self.bodyText = bodyText
        self.receivedAt = receivedAt
        self.isRead = isRead
        self.isArchived = isArchived
        self.isStarred = isStarred
        self.category = category
    }

    var recipientList: [String] {
        recipientEmails.jsonDecoded ?? []
    }
}

/// Smart email categories matching the Superhuman-inspired inbox.
enum EmailCategory: String, Codable, CaseIterable, DatabaseValueConvertible {
    case important      = "important"
    case newsletters    = "newsletters"
    case promotions     = "promotions"
    case spam           = "spam"

    var localizedTitle: String {
        switch self {
        case .important:    return "Important"
        case .newsletters:  return "Newsletters"
        case .promotions:   return "Promotions"
        case .spam:         return "Spam"
        }
    }
}

/// A pending offline action that must be synchronized with Gmail.
struct SyncQueueItem: Codable, FetchableRecord, PersistableRecord {
    static var databaseTableName = "sync_queue"
    static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase
    static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase

    var id: Int64?
    var accountId: Int64
    var actionType: SyncActionType
    var targetEmailId: String
    var status: SyncStatus
    var retryCount: Int
    var timestamp: Date

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let accountId = Column("account_id")
        static let actionType = Column("action_type")
        static let targetEmailId = Column("target_email_id")
        static let status = Column(CodingKeys.status)
        static let retryCount = Column("retry_count")
        static let timestamp = Column(CodingKeys.timestamp)
    }

    init(
        id: Int64? = nil,
        accountId: Int64,
        actionType: SyncActionType,
        targetEmailId: String,
        status: SyncStatus = .pending,
        retryCount: Int = 0,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.accountId = accountId
        self.actionType = actionType
        self.targetEmailId = targetEmailId
        self.status = status
        self.retryCount = retryCount
        self.timestamp = timestamp
    }
}

enum SyncActionType: String, Codable, DatabaseValueConvertible {
    case archive    = "archive"
    case delete     = "delete"
    case markRead   = "mark_read"
    case move       = "move"
}

enum SyncStatus: String, Codable, DatabaseValueConvertible {
    case pending  = "pending"
    case failed   = "failed"
}

// MARK: - Helpers

private extension String {
    /// JSON-encodes an array of strings for storage in a TEXT column.
    var jsonEncoded: String? {
        guard let data = try? JSONSerialization.data(
            withJSONObject: self.components(separatedBy: ",").filter { !$0.isEmpty },
            options: []
        ) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// JSON-decodes a TEXT column back into an array of strings.
    var jsonDecoded: [String]? {
        guard let data = self.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [String]
        else { return nil }
        return array
    }
}

// Provide a convenient jsonEncoded for [String]
extension Array where Element == String {
    var jsonEncoded: String? {
        guard let data = try? JSONSerialization.data(withJSONObject: self, options: []) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

extension String {
    var jsonDecodedArray: [String]? {
        guard let data = self.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [String]
        else { return nil }
        return array
    }
}
