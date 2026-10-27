import SwiftUI

/// The email list (message list) in the middle column.
struct EmailListView: View {
    @ObservedObject var viewModel: MainViewModel

    var body: some View {
        Group {
            if viewModel.emails.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No emails")
                        .foregroundColor(.secondary)
                    if viewModel.categoryFilter != nil {
                        Button("View All Categories") {
                            Task { await viewModel.setCategory(nil) }
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                List(viewModel.emails) { email in
                    EmailRowView(email: email, viewModel: viewModel)
                        .listRowSeparator(.hidden)
                        .listRowBackground(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(viewModel.selectedEmail?.id == email.id
                                      ? Color.accentColor.opacity(0.15)
                                      : Color.clear)
                                .padding(.vertical, 1)
                        )
                        .onTapGesture {
                            viewModel.select(email: email)
                        }
                }
                .listStyle(.plain)
            }
        }
        .frame(minWidth: 300)
    }
}

/// A single row in the email list.
struct EmailRowView: View {
    let email: Email
    @ObservedObject var viewModel: MainViewModel

    var body: some View {
        HStack(spacing: 8) {
            // Star
            Image(systemName: email.isStarred ? "star.fill" : "star")
                .foregroundColor(email.isStarred ? .yellow : .secondary)
                .font(.caption)
                .onTapGesture {
                    // Toggle starred (optimistic)
                    Task {
                        await viewModel.toggleStarred(emailID: email.id, isStarred: email.isStarred)
                    }
                }

            // Avatar / sender initial
            Circle()
                .fill(Color.blue.opacity(0.2))
                .frame(width: 36, height: 36)
                .overlay(
                    Text(email.senderName.prefix(1).uppercased())
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                )

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(email.senderName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    Spacer()
                    Text(email.receivedAt, style: .relative)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                HStack(spacing: 6) {
                    Text(email.subject)
                        .font(.subheadline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if !email.isRead {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 7, height: 7)
                    }
                    Spacer(minLength: 0)
                }
                Text(email.snippet)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            // Category tag
            Text(email.category.localizedTitle)
                .font(.caption2)
                .fontWeight(.medium)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(categoryColor(email.category).opacity(0.15), in: Capsule())
                .foregroundColor(categoryColor(email.category))
        }
        .padding(.vertical, 4)
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
            Button("Mark as Read") {
                Task { await viewModel.markRead(email.id) }
            }
            .keyboardShortcut("m")
        }
    }

    private func categoryColor(_ category: EmailCategory) -> Color {
        switch category {
        case .important:    return .blue
        case .newsletters:  return .green
        case .promotions:   return .orange
        case .spam:         return .red
        }
    }
}
