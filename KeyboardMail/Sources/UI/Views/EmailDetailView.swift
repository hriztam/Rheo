import SwiftUI
import WebKit

/// The detail view showing the full content of a selected email.
/// Keyboard shortcuts (handled globally by KeyboardMonitor):
///   E  — Archive
///   Delete — Delete
///   M  — Mark as read
struct EmailDetailView: View {
    @ObservedObject var viewModel: MainViewModel

    var body: some View {
        Group {
            if let email = viewModel.selectedEmail {
                VStack(alignment: .leading, spacing: 0) {
                    // Header bar
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(email.subject)
                                .font(.title2)
                                .fontWeight(.semibold)
                            HStack(spacing: 8) {
                                Text(email.senderName)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text(email.senderEmail)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            HStack(spacing: 8) {
                                Label {
                                    Text(email.receivedAt, style: .date)
                                } icon: {
                                    Image(systemName: "clock")
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)

                                CategoryBadge(category: email.category)

                                Spacer(minLength: 0)

                                HStack(spacing: 6) {
                                    DetailActionButton(icon: "archivebox", label: "Archive") {
                                        Task { await viewModel.archive(emailID: email.id) }
                                    }
                                    DetailActionButton(icon: "trash", label: "Delete") {
                                        Task { await viewModel.delete(emailID: email.id) }
                                    }
                                    DetailActionButton(icon: "envelope.open", label: "Read") {
                                        Task { await viewModel.markRead(email.id) }
                                    }
                                    StarButton(email: email, viewModel: viewModel)
                                }
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(20)
                    .background(.regularMaterial, in: Rectangle())
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.2))
                            .frame(height: 1)
                    }

                    // Body
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            if let html = email.bodyHTML, !html.isEmpty {
                                HTMLView(html: html)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else if let text = email.bodyText, !text.isEmpty {
                                Text(text)
                                    .font(.body)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            } else {
                                Text(email.snippet)
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(20)
                    }
                }
            } else {
                emptyState
            }
        }
        .frame(minWidth: 300)
    }

    var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "envelope")
                .font(.system(size: 56))
                .foregroundColor(.secondary)
            Text("Select an email to read it")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A small colored badge showing the email category.
struct CategoryBadge: View {
    let category: EmailCategory

    var body: some View {
        Text(category.localizedTitle)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(categoryColor.opacity(0.15), in: Capsule())
            .foregroundColor(categoryColor)
    }

    var categoryColor: Color {
        switch category {
        case .important:    return .blue
        case .newsletters:  return .green
        case .promotions:   return .orange
        case .spam:         return .red
        }
    }
}

/// A toolbar action button (global keyboard shortcuts are handled by KeyboardMonitor).
struct DetailActionButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.callout)
        }
        .buttonStyle(.plain)
        .help(label)
    }
}

/// Star toggle button in the detail view.
struct StarButton: View {
    let email: Email
    @ObservedObject var viewModel: MainViewModel

    var body: some View {
        Button {
            Task {
                await viewModel.toggleStarred(emailID: email.id, isStarred: email.isStarred)
            }
        } label: {
            Image(systemName: email.isStarred ? "star.fill" : "star")
                .font(.callout)
                .foregroundColor(email.isStarred ? .yellow : .secondary)
        }
        .buttonStyle(.plain)
        .help(email.isStarred ? "Unstar" : "Star")
    }
}

/// Renders HTML email content using WebKit (AppKit interop).
struct HTMLView: NSViewRepresentable {
    let html: String

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.allowsLinkPreview = false
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let wrapped = """
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <style>
          body { font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
                 font-size: 14px; line-height: 1.5; color: #1d1d1f; margin: 0; }
          a { color: #0066cc; text-decoration: none; }
          a:hover { text-decoration: underline; }
          img { max-width: 100%; height: auto; }
        </style>
        </head>
        <body>\(html)</body>
        </html>
        """
        webView.loadHTMLString(wrapped, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            // Open links externally rather than inside the web view.
            if navigationAction.navigationType == .linkActivated {
                decisionHandler(.cancel)
                if let url = navigationAction.request.url {
                    NSWorkspace.shared.open(url)
                }
                return
            }
            decisionHandler(.allow)
        }
    }
}
