import Foundation
import AppKit
import SwiftUI
import Combine

/// System-wide (app-scoped) keyboard shortcuts for the keyboard-first UI.
///
/// Registers an NSEvent local monitor so shortcuts work regardless of which
/// view has focus. Shortcuts:
///   Cmd+1 / Cmd+2 …   Switch account
///   E                 Archive selected email
///   Delete / Backspace Delete selected email
///   M                 Mark selected email as read
///   /                 Focus search (reserved)
///   G then I          Go to inbox (reserved)
@MainActor
final class KeyboardMonitor: NSObject, ObservableObject {
    static let shared = KeyboardMonitor()

    /// The currently focused account index (1-based) for Cmd+N switching.
    @Published var selectedAccountIndex: Int = 1

    /// The ID of the currently selected email (for archive/delete/mark-read).
    @Published var selectedEmailID: String?

    /// Emitted when the user triggers archive on the selected email.
    let archiveRequested = PassthroughSubject<String, Never>()
    /// Emitted when the user triggers delete on the selected email.
    let deleteRequested = PassthroughSubject<String, Never>()
    /// Emitted when the user triggers mark-read on the selected email.
    let markReadRequested = PassthroughSubject<String, Never>()
    /// Emitted when the user requests account switch to a 1-based index.
    let switchAccountRequested = PassthroughSubject<Int, Never>()

    private var monitor: Any?

    private override init() {
        super.init()
        installMonitor()
    }

    private func installMonitor() {
        // Local monitor runs within this app; no accessibility permissions needed.
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            if self.handleKeyEvent(event) {
                return nil // consumed
            }
            return event
        }
    }

    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags
        let isCmd = flags.contains(.command)
        let isCmdOnly = flags == [.command]
        let characters = event.charactersIgnoringModifiers?.lowercased() ?? ""

        // Cmd+1 … Cmd+9 : switch account
        if isCmdOnly, let digit = Int(characters), digit >= 1, digit <= 9 {
            switchAccountRequested.send(digit)
            selectedAccountIndex = digit
            return true
        }

        // No modifier: single-key actions on the selected email
        guard !isCmd, flags.isEmpty else { return false }

        guard let emailID = selectedEmailID else { return false }

        switch characters {
        case "e":
            archiveRequested.send(emailID)
            return true
        case "\u{7f}", "\u{8}": // Delete / Backspace
            deleteRequested.send(emailID)
            return true
        case "m":
            markReadRequested.send(emailID)
            return true
        default:
            return false
        }
    }

    /// Set the currently selected email (called by the email list row).
    func select(email id: String?) {
        selectedEmailID = id
    }

    deinit {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

/// NSViewRepresentable that installs the keyboard monitor into the view hierarchy.
/// Place this once in your root view (e.g. inside ContentView).
@MainActor
struct KeyboardMonitorView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        // Ensure the shared monitor is instantiated.
        _ = KeyboardMonitor.shared
        return NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
