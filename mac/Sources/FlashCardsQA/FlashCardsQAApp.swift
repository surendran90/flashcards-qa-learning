import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when run via `swift run` (no app bundle); harmless inside the .app.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct FlashCardsQAApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var session = StudySession()

    var body: some Scene {
        Window("FlashCard Q/A Bank", id: "main") {
            ContentView()
                .environment(session)
        }
        .defaultSize(width: 1060, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Import Excel…") { openImportPanel(session) }
                    .keyboardShortcut("o")
                Button("Refresh Workbook") { Task { await session.refresh() } }
                    .keyboardShortcut("r")
                    .disabled(session.loading)
            }
        }

        Settings {
            SettingsView().environment(session)
        }
    }
}
