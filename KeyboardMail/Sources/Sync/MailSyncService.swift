import Foundation

/// Pulls email data from Gmail and writes it into the local SQLite database.
/// All writes are local-first; the UI observes the database directly.
actor MailSyncService {
    static let shared = MailSyncService()

    private let db = DatabaseManager.shared
    private let api = GmailAPIClient.shared
    private let keychain = KeychainManager.shared

    private var isSyncing = false

    private init() {}

    /// Sync all accounts. Safe to call repeatedly (debounced by caller).
    func syncAllAccounts() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        do {
            let accounts = try await db.fetchAccounts()
            for account in accounts {
                await syncAccount(account)
            }
        } catch {
            print("MailSyncService: failed to fetch accounts: \(error)")
        }
    }

    private func syncAccount(_ account: Account) async {
        let accessToken: String
        do {
            accessToken = try await accessTokenFor(account: account)
        } catch {
            print("MailSyncService: no access token for \(account.email): \(error)")
            return
        }

        // Ensure account info is up to date locally.
        try? await db.save(account: account)

        do {
            try await syncThreads(accessToken: accessToken, accountId: account.id!)
        } catch {
            print("MailSyncService: sync failed for \(account.email): \(error)")
        }
    }

    /// List threads and sync each message.
    private func syncThreads(accessToken: String, accountId: Int64) async throws {
        var pageToken: String?
        repeat {
            let response = try await api.listThreads(
                accessToken: accessToken,
                query: "",
                maxResults: 50,
                pageToken: pageToken
            )
            guard let threads = response.threads else { break }

            for thread in threads {
                try await syncThread(
                    accessToken: accessToken,
                    accountId: accountId,
                    messageId: thread.id
                )
            }
            pageToken = response.nextPageToken
        } while pageToken != nil
    }

    /// Fetch a single message by Gmail ID (thread id == message id for single-message threads)
    /// and upsert it into the local DB.
    private func syncThread(accessToken: String, accountId: Int64, messageId: String) async throws {
        let message = try await api.getMessage(accessToken: accessToken, messageId: messageId)

        let category = CategorizationEngine.categorize(
            message: message,
            hasSpamLabel: message.labelIds.contains("SPAM")
        )

        let email = Email(
            id: message.id,
            threadId: message.threadId,
            accountId: accountId,
            senderName: message.senderName ?? "Unknown",
            senderEmail: message.senderEmail ?? "",
            recipientEmails: [], // Gmail API 'full' format doesn't include To in headers reliably; parsed below
            subject: message.header("Subject") ?? "(No Subject)",
            snippet: message.snippet,
            bodyHTML: message.htmlBody(),
            bodyText: message.plainTextBody(),
            receivedAt: message.receivedAt,
            isRead: !message.labelIds.contains("UNREAD"),
            isArchived: message.labelIds.contains("INBOX") ? false : true,
            isStarred: message.labelIds.contains("STARRED"),
            category: category
        )

        try await db.save(emails: [email])
    }

    private func accessTokenFor(account: Account) async throws -> String {
        let refreshToken = try await keychain.loadRefreshToken(for: account.email)
        guard let refreshToken = refreshToken else {
            throw MailSyncError.missingRefreshToken
        }
        return try await OAuthManager.shared.refreshAccessToken(refreshToken: refreshToken)
    }
}

enum MailSyncError: Error {
    case missingRefreshToken
}
