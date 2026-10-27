import Foundation
import GRDB

/// Central database manager. All reads and writes happen against the local SQLite
/// database so the UI never blocks on the network.
actor DatabaseManager {
    /// Shared instance
    static let shared = DatabaseManager()

    /// The GRDB database connection
    private var dbQueue: DatabaseQueue!

    /// Path to the SQLite file
    private let dbPath: String

    private init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let appDir = appSupport.appendingPathComponent("KeyboardMail", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: appDir,
            withIntermediateDirectories: true,
            attributes: nil
        )
        self.dbPath = appDir.appendingPathComponent("keyboardmail.sqlite").path

        // Open the database and run migrations during initialization.
        do {
            self.dbQueue = try DatabaseQueue(path: self.dbPath)
            try self.migrator.migrate(self.dbQueue)
        } catch {
            fatalError("Failed to open database: \(error)")
        }
    }

    /// The GRDB migrator with all schema versions.
    private var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()

        // v1 — Initial schema
        m.registerMigration("v1InitialSchema") { db in
            try db.create(table: "accounts") { t in
                t.column("id", .integer).primaryKey()
                t.column("email", .text).notNull().unique()
                t.column("display_name", .text).notNull()
                t.column("avatar_url", .text)
                t.column("created_at", .datetime).notNull()
            }

            try db.create(table: "emails") { t in
                t.column("id", .text).primaryKey()
                t.column("thread_id", .text).notNull()
                t.column("account_id", .integer).notNull()
                t.column("sender_name", .text).notNull()
                t.column("sender_email", .text).notNull()
                t.column("recipient_emails", .text).notNull()
                t.column("subject", .text).notNull()
                t.column("snippet", .text).notNull()
                t.column("body_html", .text)
                t.column("body_text", .text)
                t.column("received_at", .datetime).notNull()
                t.column("is_read", .boolean).notNull().defaults(to: false)
                t.column("is_archived", .boolean).notNull().defaults(to: false)
                t.column("is_starred", .boolean).notNull().defaults(to: false)
                t.column("category", .text).notNull().defaults(to: "important")
            }
            try db.create(index: "idx_emails_thread_id", on: "emails", columns: ["thread_id"])
            try db.create(index: "idx_emails_account_id", on: "emails", columns: ["account_id"])
            try db.create(index: "idx_emails_category", on: "emails", columns: ["category"])
            try db.create(index: "idx_emails_is_archived", on: "emails", columns: ["is_archived"])
            try db.create(index: "idx_emails_received_at", on: "emails", columns: ["received_at"])

            try db.create(table: "sync_queue") { t in
                t.column("id", .integer).primaryKey()
                t.column("account_id", .integer).notNull()
                t.column("action_type", .text).notNull()
                t.column("target_email_id", .text).notNull()
                t.column("status", .text).notNull().defaults(to: "pending")
                t.column("retry_count", .integer).notNull().defaults(to: 0)
                t.column("timestamp", .datetime).notNull()
            }
            try db.create(index: "idx_sync_queue_status", on: "sync_queue", columns: ["status"])
            try db.create(index: "idx_sync_queue_account_id", on: "sync_queue", columns: ["account_id"])
        }

        return m
    }

    // MARK: - Writes (instant, never wait for network)

    /// Insert or update an account.
    func save(account: Account) throws {
        try dbQueue.write { db in
            try account.insert(db)
        }
    }

    /// Insert or replace a batch of emails (used during sync).
    func save(emails: [Email]) throws {
        try dbQueue.write { db in
            for email in emails {
                try email.insert(db, onConflict: .replace)
            }
        }
    }

    /// Mark a single email's read/archived/starred state optimistically.
    func updateEmailFlags(
        id: String,
        isRead: Bool? = nil,
        isArchived: Bool? = nil,
        isStarred: Bool? = nil
    ) throws {
        try dbQueue.write { db in
            guard var email = try Email.fetchOne(db, key: id) else { return }
            if let isRead { email.isRead = isRead }
            if let isArchived { email.isArchived = isArchived }
            if let isStarred { email.isStarred = isStarred }
            try email.update(db)
        }
    }

    /// Archive an email (optimistic UI update).
    func archive(emailId: String) throws {
        try updateEmailFlags(id: emailId, isArchived: true)
    }

    /// Delete an email (removes from local DB immediately).
    func delete(emailId: String) throws {
        _ = try dbQueue.write { db in
            try Email.deleteOne(db, key: emailId)
        }
    }

    /// Mark an email as read.
    func markRead(emailId: String) throws {
        try updateEmailFlags(id: emailId, isRead: true)
    }

    /// Add an item to the sync queue (executed asynchronously in background).
    func enqueueSync(
        accountId: Int64,
        actionType: SyncActionType,
        targetEmailId: String
    ) throws {
        try dbQueue.write { db in
            let item = SyncQueueItem(
                accountId: accountId,
                actionType: actionType,
                targetEmailId: targetEmailId
            )
            try item.insert(db)
        }
    }

    // MARK: - Reads

    /// Fetch all accounts.
    func fetchAccounts() throws -> [Account] {
        try dbQueue.read { db in
            try Account.fetchAll(db)
        }
    }

    /// Fetch the default (first) account.
    func fetchDefaultAccount() throws -> Account? {
        try dbQueue.read { db in
            try Account.fetchAll(db).first
        }
    }

    /// Fetch non-archived emails for an account, ordered by received date desc.
    func fetchInboxEmails(accountId: Int64, category: EmailCategory? = nil) throws -> [Email] {
        try dbQueue.read { db in
            var sql = """
                SELECT * FROM emails
                WHERE account_id = ? AND is_archived = 0
            """
            var args: [DatabaseValueConvertible?] = [accountId]
            if let category = category {
                sql += " AND category = ?"
                args.append(category.rawValue)
            }
            sql += " ORDER BY received_at DESC"
            return try Email.fetchAll(db, sql: sql, arguments: StatementArguments(args))
        }
    }

    /// Fetch a single email by ID.
    func fetchEmail(id: String) throws -> Email? {
        try dbQueue.read { db in
            try Email.fetchOne(db, key: id)
        }
    }

    /// Fetch all pending sync queue items.
    func fetchPendingSyncItems() throws -> [SyncQueueItem] {
        try dbQueue.read { db in
            try SyncQueueItem.filter(Column("status") == SyncStatus.pending.rawValue)
                .order(Column("timestamp"))
                .fetchAll(db)
        }
    }

    /// Mark a sync item as failed.
    func markSyncItemFailed(id: Int64) throws {
        try dbQueue.write { db in
            var item = try SyncQueueItem.fetchOne(db, key: id)
            item?.status = .failed
            try item?.update(db)
        }
    }

    /// Delete a successfully-synced queue item.
    func deleteSyncItem(id: Int64) throws {
        _ = try dbQueue.write { db in
            try SyncQueueItem.deleteOne(db, key: id)
        }
    }

    /// Increment retry count on a failed sync item.
    func incrementRetry(id: Int64) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE sync_queue SET retry_count = retry_count + 1 WHERE id = ?",
                arguments: [id]
            )
        }
    }

    /// Count non-archived emails for an account (for unread badge).
    func countInbox(accountId: Int64) throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM emails WHERE account_id = ? AND is_archived = 0",
                arguments: [accountId]
            ) ?? 0
        }
    }

    /// Count unread non-archived emails.
    func countUnread(accountId: Int64) throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM emails WHERE account_id = ? AND is_archived = 0 AND is_read = 0",
                arguments: [accountId]
            ) ?? 0
        }
    }

    /// Close the database connection.
    func close() throws {
        try dbQueue.close()
    }
}
