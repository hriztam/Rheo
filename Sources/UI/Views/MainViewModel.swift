import Foundation
import Combine
import GRDB

/// Main application view model. Bridges the actor-based DatabaseManager to
/// SwiftUI on the main actor. Reads are always local (instant); network writes
/// are handled optimistically by SyncEngine.
@MainActor
final class MainViewModel: ObservableObject {
    @Published var accounts: [Account] = []
    @Published var selectedAccount: Account?
    @Published var emails: [Email] = []
    @Published var selectedEmail: Email?
    @Published var categoryFilter: EmailCategory? = nil
    @Published var isSyncing = false
    @Published var syncStatusMessage: String = ""

    var cancellables = Set<AnyCancellable>()
    let db = DatabaseManager.shared
    private let mailSync = MailSyncService.shared
    private let keyboard = KeyboardMonitor.shared
    private var accountsLoadGeneration = 0

    init() {
        Task {
            await loadAccounts()
            selectDefaultAccount()
        }

        // Wire keyboard shortcuts to actions.
        keyboard.switchAccountRequested
            .receive(on: RunLoop.main)
            .sink { [weak self] index in
                Task { await self?.switchAccount(toIndex: index) }
            }
            .store(in: &cancellables)

        keyboard.archiveRequested
            .receive(on: RunLoop.main)
            .sink { [weak self] emailID in
                Task { await self?.archive(emailID: emailID) }
            }
            .store(in: &cancellables)

        keyboard.deleteRequested
            .receive(on: RunLoop.main)
            .sink { [weak self] emailID in
                Task { await self?.delete(emailID: emailID) }
            }
            .store(in: &cancellables)

        keyboard.markReadRequested
            .receive(on: RunLoop.main)
            .sink { [weak self] emailID in
                Task { await self?.markRead(emailID) }
            }
            .store(in: &cancellables)

        // Periodic background sync (every 30 seconds).
        Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { await self?.syncAllAccounts() }
            }
            .store(in: &cancellables)
    }

    // MARK: - Accounts

    func loadAccounts() async {
        accountsLoadGeneration += 1
        let generation = accountsLoadGeneration

        do {
            let loadedAccounts = try await db.fetchAccounts()
            guard generation == accountsLoadGeneration else { return }
            accounts = loadedAccounts
        } catch {
            print("MainViewModel: failed to load accounts: \(error)")
        }
    }

    func selectDefaultAccount() {
        if let first = accounts.first {
            selectedAccount = first
            Task { await loadEmails() }
        }
    }

    func switchAccount(toIndex index: Int) async {
        guard index > 0, index <= accounts.count else { return }
        selectedAccount = accounts[index - 1]
        await loadEmails()
    }

    // MARK: - Emails

    func loadEmails() async {
        guard let account = selectedAccount else { return }
        do {
            emails = try await db.fetchInboxEmails(
                accountId: account.id!,
                category: categoryFilter
            )
        } catch {
            print("MainViewModel: failed to load emails: \(error)")
        }
    }

    func setCategory(_ category: EmailCategory?) async {
        categoryFilter = category
        await loadEmails()
    }

    func select(email: Email?) {
        selectedEmail = email
        keyboard.select(email: email?.id)
        // Mark as read on view (optimistic).
        if let email = email, !email.isRead {
            Task { await self.markRead(email.id) }
        }
    }

    // MARK: - Actions (optimistic)

    func archive(emailID: String) async {
        guard let account = selectedAccount else { return }
        do {
            try await db.archive(emailId: emailID)
            await loadEmails()
            if selectedEmail?.id == emailID { selectedEmail = nil }
            await SyncEngine.shared.enqueue(
                accountId: account.id!,
                actionType: .archive,
                targetEmailId: emailID
            )
            syncStatusMessage = "Archived"
        } catch {
            print("MainViewModel: archive failed: \(error)")
        }
    }

    func delete(emailID: String) async {
        guard let account = selectedAccount else { return }
        do {
            try await db.delete(emailId: emailID)
            await loadEmails()
            if selectedEmail?.id == emailID { selectedEmail = nil }
            await SyncEngine.shared.enqueue(
                accountId: account.id!,
                actionType: .delete,
                targetEmailId: emailID
            )
            syncStatusMessage = "Deleted"
        } catch {
            print("MainViewModel: delete failed: \(error)")
        }
    }

    func markRead(_ emailID: String) async {
        do {
            try await db.markRead(emailId: emailID)
            await loadEmails()
            await SyncEngine.shared.enqueue(
                accountId: selectedAccount?.id ?? 0,
                actionType: .markRead,
                targetEmailId: emailID
            )
        } catch {
            print("MainViewModel: mark read failed: \(error)")
        }
    }

    func toggleStarred(emailID: String, isStarred: Bool) async {
        do {
            try await db.updateEmailFlags(id: emailID, isStarred: !isStarred)
            await loadEmails()
        } catch {
            print("MainViewModel: toggle starred failed: \(error)")
        }
    }

    // MARK: - Sync

    func syncAllAccounts() async {
        isSyncing = true
        defer { isSyncing = false }
        syncStatusMessage = "Syncing..."
        await mailSync.syncAllAccounts()
        await loadAccounts()
        await loadEmails()
        syncStatusMessage = "Synced"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.syncStatusMessage = ""
        }
    }

    /// Add a new account via OAuth.
    func addAccount() async {
        do {
            let result = try await OAuthManager.shared.authenticate()
            // Save refresh token to keychain.
            let accessToken = result.accessToken
            let profile = try await GmailAPIClient.shared.getProfile(accessToken: accessToken)
            try await KeychainManager.shared.saveRefreshToken(
                result.refreshToken, for: profile.emailAddress
            )

            let account = Account(
                email: profile.emailAddress,
                displayName: profile.displayName ?? profile.emailAddress,
                avatarURL: nil,
                createdAt: Date()
            )
            let savedAccount = try await db.save(account: account)
            await loadAccounts()
            if !accounts.contains(where: { $0.email == savedAccount.email }) {
                accounts.append(savedAccount)
            }
            selectedAccount = accounts.first(where: { $0.email == savedAccount.email })
            await loadEmails()
            // Kick off initial sync.
            Task { await syncAllAccounts() }
        } catch {
            print("MainViewModel: add account failed: \(error.localizedDescription)")
            syncStatusMessage = "Auth failed: \(error.localizedDescription)"
        }
    }

    /// Unread count computed from the locally-loaded emails (instant, no actor hop).
    var unreadCount: Int {
        guard selectedAccount != nil else { return 0 }
        return emails.filter { !$0.isRead }.count
    }
}
