import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = MainViewModel()

    var body: some View {
        Group {
            if viewModel.accounts.isEmpty {
                AccountSetupView(viewModel: viewModel)
            } else {
                MainSplitView(viewModel: viewModel)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
    }
}

/// Three-column layout: Sidebar | Email List | Email Detail
struct MainSplitView: View {
    @ObservedObject var viewModel: MainViewModel

    var body: some View {
        NavigationSplitView {
            SidebarView(viewModel: viewModel)
        } content: {
            EmailListView(viewModel: viewModel)
        } detail: {
            EmailDetailView(viewModel: viewModel)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await viewModel.syncAllAccounts() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Sync (⌘K)")
                .keyboardShortcut("k", modifiers: .command)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await viewModel.addAccount() }
                } label: {
                    Image(systemName: "person.badge.plus")
                }
                .help("Add Account")
            }
        }
        .overlay(alignment: .bottom) {
            if !viewModel.syncStatusMessage.isEmpty {
                Text(viewModel.syncStatusMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(6)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 8)
                    .transition(.opacity)
            }
        }
        .animation(.default, value: viewModel.syncStatusMessage)
    }
}

/// Left sidebar: account switching + category filters
struct SidebarView: View {
    @ObservedObject var viewModel: MainViewModel

    var body: some View {
        List {
            Section("Accounts") {
                ForEach(viewModel.accounts) { account in
                    Button {
                        viewModel.selectedAccount = account
                        Task { await viewModel.loadEmails() }
                    } label: {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 30, height: 30)
                                .overlay(
                                    Text(account.displayName.prefix(1).uppercased())
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                )
                            Text(account.email)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            if viewModel.selectedAccount?.id == account.id {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                                    .font(.caption)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                Divider()
                Button("Add Account…") {
                    Task { await viewModel.addAccount() }
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])
            }

            Section("Categories") {
                CategoryRow(
                    title: "Inbox",
                    icon: "inbox",
                    isSelected: viewModel.categoryFilter == nil,
                    count: viewModel.unreadCount
                ) {
                    Task { await viewModel.setCategory(nil) }
                }
                CategoryRow(
                    title: "Important",
                    icon: "exclamationmark.circle.fill",
                    isSelected: viewModel.categoryFilter == .important,
                    count: 0
                ) {
                    Task { await viewModel.setCategory(.important) }
                }
                CategoryRow(
                    title: "Newsletters",
                    icon: "newspaper",
                    isSelected: viewModel.categoryFilter == .newsletters,
                    count: 0
                ) {
                    Task { await viewModel.setCategory(.newsletters) }
                }
                CategoryRow(
                    title: "Promotions",
                    icon: "tag",
                    isSelected: viewModel.categoryFilter == .promotions,
                    count: 0
                ) {
                    Task { await viewModel.setCategory(.promotions) }
                }
                CategoryRow(
                    title: "Spam",
                    icon: "exclamationmark.triangle.fill",
                    isSelected: viewModel.categoryFilter == .spam,
                    count: 0
                ) {
                    Task { await viewModel.setCategory(.spam) }
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 260)
    }
}

private struct CategoryRow: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .frame(width: 16)
                Text(title)
                Spacer()
                if count > 0 {
                    Text("\(count)")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.blue.opacity(0.15), in: Capsule())
                        .foregroundColor(.blue)
                }
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(.accentColor)
                        .font(.caption)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

/// Account setup / OAuth sign-in view (shown when no accounts exist).
struct AccountSetupView: View {
    @ObservedObject var viewModel: MainViewModel

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "envelope.fill")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)
            Text("Rheo")
                .font(.largeTitle).fontWeight(.bold)
            Text("Connect your Gmail account to get started.")
                .foregroundColor(.secondary)
            Button {
                Task { await viewModel.addAccount() }
            } label: {
                Text("Add Gmail Account")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.blue, in: RoundedRectangle(cornerRadius: 8))
                    .foregroundColor(.white)
            }
            .frame(width: 260)
            .keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
