import AppKit
import FlashCardsCore
import SwiftUI

/// Shared app objects, reachable from the app delegate for saving on quit.
@MainActor
final class AppModel {
    static let shared = AppModel()

    let store: ProgressStore
    let session: StudySession
    let timer: CardTimer
    let notifier: SessionNotifier
    private var heartbeat: Task<Void, Never>?

    private init() {
        // FLASHCARDSQA_PROGRESS_DIR lets testing use a scratch folder instead of your real progress.
        if let dir = ProcessInfo.processInfo.environment["FLASHCARDSQA_PROGRESS_DIR"], !dir.isEmpty {
            store = ProgressStore(folder: URL(fileURLWithPath: dir, isDirectory: true))
        } else {
            store = ProgressStore()
        }
        session = StudySession(progress: store)
        timer = CardTimer(store: store, session: session)
        notifier = SessionNotifier(session: session, store: store)
        session.onPlanChanged = { [weak notifier] in notifier?.scheduleSoon() }
        // Once a minute: refresh session status and carry over sessions that just ended.
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard let self else { return }
                self.session.minuteTick += 1
                self.session.ensureToday()
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when run via `swift run` (no app bundle); harmless inside the .app.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        // Pause so the remaining time is kept, and time while closed is never counted.
        MainActor.assumeIsolated {
            AppModel.shared.timer.pause()
            AppModel.shared.store.saveNow()
        }
    }
}

@main
struct FlashCardsQAApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let model = AppModel.shared

    var body: some Scene {
        Window("FlashCard Q/A Bank", id: "main") {
            ContentView()
                .environment(model.session)
                .environment(model.timer)
                .environment(model.store)
                .environment(model.notifier)
        }
        .defaultSize(width: 1060, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Import Excel…") { openImportPanel(model.session) }
                    .keyboardShortcut("o")
                Button("Refresh Workbook") { Task { await model.session.refresh() } }
                    .keyboardShortcut("r")
                Divider()
                Button("Study Plan") { model.session.openPlan() }
                    .keyboardShortcut("l")
            }
            CommandMenu("Timer") {
                Button("Start / Pause Card Timer") { model.timer.toggle() }
                    .keyboardShortcut(.space, modifiers: .option)
                Button("Reset Card Timer") { model.timer.reset() }
            }
        }

        Settings {
            SettingsView()
                .environment(model.session)
                .environment(model.timer)
                .environment(model.store)
                .environment(model.notifier)
        }
    }
}
