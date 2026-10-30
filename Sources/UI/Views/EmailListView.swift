import SwiftUI

/// The email list (message list) in the middle column.
struct EmailListView: View {
    @ObservedObject var viewModel: MainViewModel

    var body: some View {
        Group {
            if viewModel.emails.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.system(size: 44, weight: .light))
                        .foregroundColor(.secondary.opacity(0.7))
                    Text("No emails")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    if viewModel.categoryFilter != nil {
                        Button("View All Categories") {
                            Task { await viewModel.setCategory(nil) }
                        }
                        .buttonStyle(.plain)
                        .font(.subheadline)
                        .foregroundColor(.accentColor)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(viewModel.emails) { email in
                    EmailRowView(email: email, viewModel: viewModel)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 8))
                        .listRowBackground(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(viewModel.selectedEmail?.id == email.id
                                      ? Color.accentColor.opacity(0.14)
                                      : Color.clear)
                        )
                        .onTapGesture {
                            viewModel.select(email: email)
                        }
                }
                .listStyle(.plain)
            }
        }
        .frame(minWidth: 320)
    }
}

/// A single row in the email list.
struct EmailRowView: View {
    let email: Email
    @ObservedObject var viewModel: MainViewModel

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Unread / Star column
            VStack(spacing: 8) {
                // Star
                Image(systemName: email.isStarred ? "star.fill" : "star")
                    .foregroundColor(email.isStarred ? .yellow : .secondary.opacity(0.4))
                    .font(.system(size: 11))
                    .onTapGesture {
                        Task {
                            await viewModel.toggleStarred(emailID: email.id, isStarred: email.isStarred)
                        }
                    }

                // Unread dot indicator
                if !email.isRead {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 7, height: 7)
                } else {
                    Spacer().frame(height: 7)
                }
            }
            .frame(width: 14)
            .padding(.top, 4)

            // Avatar / sender initial
            Circle()
                .fill(avatarColor(for: email.displaySenderName))
                .frame(width: 34, height: 34)
                .overlay(
                    Text(email.displaySenderName.prefix(1).uppercased())
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                )

            // Content
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(email.displaySenderName)
                        .font(.system(size: 13, weight: email.isRead ? .medium : .bold))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    Text(email.receivedAt, style: .relative)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Text(email.displaySubject)
                    .font(.system(size: 12.5, weight: email.isRead ? .regular : .semibold))
                    .foregroundColor(email.isRead ? .primary.opacity(0.85) : .primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: 6) {
                    Text(email.displaySnippet)
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 4)

                    // Category tag
                    Text(email.category.localizedTitle)
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(categoryColor(email.category).opacity(0.12), in: Capsule())
                        .foregroundColor(categoryColor(email.category))
                }
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Archive") {
                Task { await viewModel.archive(emailID: email.id) }
            }
            .keyboardShortcut("e")
            Button("Delete") {
                Task { await viewModel.delete(emailID: email.id) }
            }
            .keyboardShortcut(.delete)
            Button(email.isRead ? "Mark as Unread" : "Mark as Read") {
                Task { await viewModel.markRead(email.id) }
            }
            .keyboardShortcut("m")
        }
    }

    private func avatarColor(for name: String) -> LinearGradient {
        let colors: [[Color]] = [
            [.blue, .cyan],
            [.purple, .pink],
            [.indigo, .blue],
            [.teal, .green],
            [.orange, .pink]
        ]
        let hash = abs(name.hashValue) % colors.count
        let pair = colors[hash]
        return LinearGradient(colors: pair, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private func categoryColor(_ category: EmailCategory) -> Color {
        switch category {
        case .important:    return .blue
        case .newsletters:  return .teal
        case .promotions:   return .purple
        case .spam:         return .red
        }
    }
}
