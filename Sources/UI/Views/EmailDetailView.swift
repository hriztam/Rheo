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
                    VStack(alignment: .leading, spacing: 12) {
                        Text(email.displaySubject)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.primary)
                            .textSelection(.enabled)
                            .lineLimit(3)

                        HStack(alignment: .center, spacing: 10) {
                            // Sender Avatar
                            Circle()
                                .fill(LinearGradient(
                                    colors: [Color.blue.opacity(0.8), Color.indigo.opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ))
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Text(email.displaySenderName.prefix(1).uppercased())
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(.white)
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(email.displaySenderName)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.primary)
                                    Text("<\(email.senderEmail)>")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }

                                HStack(spacing: 8) {
                                    Label {
                                        Text(email.receivedAt, style: .date) + Text(", ") + Text(email.receivedAt, style: .time)
                                    } icon: {
                                        Image(systemName: "calendar")
                                    }
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                    CategoryBadge(category: email.category)
                                }
                            }

                            Spacer(minLength: 0)

                            // Quick actions
                            HStack(spacing: 6) {
                                DetailActionButton(icon: "archivebox", label: "Archive (E)") {
                                    Task { await viewModel.archive(emailID: email.id) }
                                }
                                DetailActionButton(icon: "trash", label: "Delete (⌫)") {
                                    Task { await viewModel.delete(emailID: email.id) }
                                }
                                DetailActionButton(icon: email.isRead ? "envelope" : "envelope.open", label: email.isRead ? "Mark as Unread" : "Mark as Read (M)") {
                                    Task { await viewModel.markRead(email.id) }
                                }
                                StarButton(email: email, viewModel: viewModel)
                            }
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 16)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                    .overlay(alignment: .bottom) {
                        Divider()
                    }

                    // Body: Full native WKWebView rendering
                    if let html = email.bodyHTML, !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        HTMLView(content: .html(html))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let text = email.bodyText, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        HTMLView(content: .plainText(text))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        HTMLView(content: .plainText(email.displaySnippet))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            } else {
                emptyState
            }
        }
        .frame(minWidth: 320)
    }

    var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "envelope.open")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(.secondary.opacity(0.6))
            Text("No Conversation Selected")
                .font(.title3)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            Text("Select an email from the list to read it.")
                .font(.subheadline)
                .foregroundColor(.secondary.opacity(0.8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
    }
}

/// A small colored badge showing the email category.
struct CategoryBadge: View {
    let category: EmailCategory

    var body: some View {
        Text(category.localizedTitle)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(categoryColor.opacity(0.12), in: Capsule())
            .foregroundColor(categoryColor)
    }

    var categoryColor: Color {
        switch category {
        case .important:    return .blue
        case .newsletters:  return .teal
        case .promotions:   return .purple
        case .spam:         return .red
        }
    }
}

/// A toolbar action button with nice hover and active state.
struct DetailActionButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(isHovered ? .primary : .secondary)
                .frame(width: 28, height: 28)
                .background(isHovered ? Color.secondary.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(label)
    }
}

/// Star toggle button in the detail view.
struct StarButton: View {
    let email: Email
    @ObservedObject var viewModel: MainViewModel
    @State private var isHovered = false

    var body: some View {
        Button {
            Task {
                await viewModel.toggleStarred(emailID: email.id, isStarred: email.isStarred)
            }
        } label: {
            Image(systemName: email.isStarred ? "star.fill" : "star")
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(email.isStarred ? .yellow : (isHovered ? .primary : .secondary))
                .frame(width: 28, height: 28)
                .background(isHovered ? Color.secondary.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(email.isStarred ? "Unstar" : "Star")
    }
}

/// Content representation for HTMLView
enum HTMLContent {
    case html(String)
    case plainText(String)
}

/// Renders HTML or linkified plain-text email content using WebKit.
struct HTMLView: NSViewRepresentable {
    let content: HTMLContent

    init(content: HTMLContent) {
        self.content = content
    }

    init(html: String) {
        self.content = .html(html)
    }

    init(plainText: String) {
        self.content = .plainText(plainText)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsLinkPreview = true
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground") // Transparent background matching system theme
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let htmlPayload: String
        switch content {
        case .html(let rawHtml):
            htmlPayload = wrapHTML(rawHtml)
        case .plainText(let text):
            htmlPayload = wrapPlainText(text)
        }
        webView.loadHTMLString(htmlPayload, baseURL: nil)
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
            // Open user clicked links externally in default browser (Safari, Chrome, etc.)
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

    private func wrapHTML(_ html: String) -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0, shrink-to-fit=no">
        <style>
          :root {
            color-scheme: light dark;
          }
          body {
            font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
            font-size: 14px;
            line-height: 1.6;
            margin: 20px 24px;
            word-wrap: break-word;
            overflow-wrap: break-word;
            color: -apple-system-label;
            background-color: transparent;
          }
          a {
            color: #007aff;
            text-decoration: none;
            word-break: break-all;
          }
          a:hover {
            text-decoration: underline;
          }
          img {
            max-width: 100% !important;
            height: auto !important;
          }
          table {
            max-width: 100% !important;
          }
          pre, code {
            font-family: "SF Mono", Menlo, Consolas, Monaco, monospace;
            font-size: 13px;
            white-space: pre-wrap;
            word-wrap: break-word;
          }
          blockquote {
            margin: 12px 0;
            padding-left: 12px;
            border-left: 3px solid rgba(128, 128, 128, 0.4);
            color: -apple-system-secondary-label;
          }
        </style>
        </head>
        <body>
        \(html)
        </body>
        </html>
        """
    }

    private func wrapPlainText(_ text: String) -> String {
        // Convert URLs into clickable HTML links and preserve linebreaks
        let escaped = text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")

        // Linkify URLs: https?://...
        let pattern = "(https?:\\/\\/[^\\s<>\"]+)"
        let linkified: String
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let range = NSRange(location: 0, length: escaped.utf16.count)
            linkified = regex.stringByReplacingMatches(
                in: escaped,
                options: [],
                range: range,
                withTemplate: "<a href=\"$1\">$1</a>"
            )
        } else {
            linkified = escaped
        }

        let formatted = linkified.replacingOccurrences(of: "\n", with: "<br>\n")
        return wrapHTML("<div style=\"white-space: normal;\">\(formatted)</div>")
    }
}
