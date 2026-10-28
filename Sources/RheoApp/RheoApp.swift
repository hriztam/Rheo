import SwiftUI

@main
struct RheoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        Window("Rheo", id: "main") {
            ContentView()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

/// App delegate: handles lifecycle, starts background sync engine.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Start the background sync queue processor (cross-actor call).
        Task { await SyncEngine.shared.start() }

        // Ensure the app stays open even when windows close (menu-bar style behavior optional).
        NSApp.setActivationPolicy(.regular)
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task { try? await DatabaseManager.shared.close() }
    }
}
