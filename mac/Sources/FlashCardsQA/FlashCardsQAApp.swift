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
    let reminder: RevisionReminder
    private var heartbeat: Task<Void, Never>?
    private var lastDay = ""

    private init() {
        // FLASHCARDSQA_PROGRESS_DIR lets testing use a scratch folder instead of your real progress.
        if let dir = ProcessInfo.processInfo.environment["FLASHCARDSQA_PROGRESS_DIR"], !dir.isEmpty {
            store = ProgressStore(folder: URL(fileURLWithPath: dir, isDirectory: true))
        } else {
            store = ProgressStore()
        }
        // One-time switch-over to "fixed checkpoints, then FSRS": everything studied so far is
        // revised today and starts its checkpoints (and a fresh FSRS history) from today.
        if store.data.useCheckpoints && store.data.checkpointsRestartedDay == nil {
            let today = DayClock().key(Date())
            Scheduler.restartAll(&store.data, today: today)
            store.data.checkpointsRestartedDay = today
            store.saveNow()
        }
        if store.data.studyNotes == nil {
            store.data.studyNotes = StudyNotes.starter
            store.saveNow()
        }
        session = StudySession(progress: store)
        timer = CardTimer(store: store, session: session)
        reminder = RevisionReminder(session: session, store: store)
        session.onPlanChanged = { [weak reminder] in reminder?.scheduleSoon() }
        // Once a minute: refresh date-based views; after midnight, reschedule the reminders.
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard let self else { return }
                let day = self.session.today
                self.session.minuteTick += 1
                if day != self.lastDay { self.lastDay = day; self.reminder.scheduleSoon() }
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
                .environment(model.reminder)
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
                .environment(model.reminder)
        }
    }
}
