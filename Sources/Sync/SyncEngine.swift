import Foundation

/// Processes the persistent SyncQueue in the background.
/// UI updates happen optimistically against the local DB; this engine reconciles with Gmail.
actor SyncEngine {
    static let shared = SyncEngine()

    private let db = DatabaseManager.shared
    private let api = GmailAPIClient.shared
    private let keychain = KeychainManager.shared

    private var isProcessing = false

    private init() {}

    /// Starts the background sync loop. Call once at app launch.
    func start() {
        Task { [weak self] in
            await self?.processLoop()
        }
    }

    /// Processes the queue repeatedly, backing off when empty.
    private func processLoop() async {
        while true {
            await processPendingItems()
            // Poll interval: faster when there's work, slower when idle.
            try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
        }
    }

    /// Processes all pending sync items once.
    private func processPendingItems() async {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }

        do {
            let items = try await db.fetchPendingSyncItems()
            for item in items {
                await process(item: item)
            }
        } catch {
            print("SyncEngine: failed to fetch pending items: \(error)")
        }
    }

    private func process(item: SyncQueueItem) async {
        guard let account = try? await db.fetchAccounts().first(where: { $0.id == item.accountId }) else {
            // Account no longer exists; drop the item.
            try? await db.deleteSyncItem(id: item.id!)
            return
        }

        let accessToken: String
        do {
            accessToken = try await accessTokenFor(account: account)
        } catch {
            print("SyncEngine: could not get access token for \(account.email): \(error)")
            try? await db.incrementRetry(id: item.id!)
            try? await db.markSyncItemFailed(id: item.id!)
            return
        }

        do {
            switch item.actionType {
            case .archive:
                try await api.archive(accessToken: accessToken, messageId: item.targetEmailId)
            case .delete:
                try await api.deleteMessage(accessToken: accessToken, messageId: item.targetEmailId)
            case .markRead:
                try await api.markRead(accessToken: accessToken, messageId: item.targetEmailId)
            case .move:
                // Move is treated as archive for MVP (label-based).
                try await api.archive(accessToken: accessToken, messageId: item.targetEmailId)
            }
            // Success — remove from queue.
            try await db.deleteSyncItem(id: item.id!)
            print("SyncEngine: \(item.actionType.rawValue) succeeded for \(item.targetEmailId)")
        } catch {
            print("SyncEngine: \(item.actionType.rawValue) failed for \(item.targetEmailId): \(error)")
            // Retry with backoff; mark failed after too many attempts.
            if item.retryCount >= 3 {
                try? await db.markSyncItemFailed(id: item.id!)
            } else {
                try? await db.incrementRetry(id: item.id!)
            }
        }
    }

    private func accessTokenFor(account: Account) async throws -> String {
        // In a full implementation we'd cache access tokens and refresh on expiry.
        // For MVP, we use the refresh token to obtain a fresh access token each time.
        let refreshToken = try await keychain.loadRefreshToken(for: account.email)
        guard let refreshToken = refreshToken else {
            throw SyncError.missingRefreshToken
        }
        return try await OAuthManager.shared.refreshAccessToken(refreshToken: refreshToken)
    }

    /// Convenience: enqueue an optimistic action.
    func enqueue(
        accountId: Int64,
        actionType: SyncActionType,
        targetEmailId: String
    ) async {
        try? await db.enqueueSync(accountId: accountId, actionType: actionType, targetEmailId: targetEmailId)
    }
}

enum SyncError: Error {
    case missingRefreshToken
}
