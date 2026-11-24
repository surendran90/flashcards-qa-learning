import FlashCardsCore
import Foundation
import Observation
import UserNotifications

/// One reminder each morning for the next 7 days: how many cards FSRS wants revised that day,
/// plus your first tasks. macOS delivers them even when the app is closed.
@MainActor @Observable
final class RevisionReminder {
    static let idPrefix = "revision-"
    /// Reminders from the earlier session-based plan, removed on first run.
    static let oldPrefix = "session-"

    private let session: StudySession
    private let store: ProgressStore
    private(set) var authorized: Bool?
    private(set) var scheduledCount = 0
    @ObservationIgnored private var pending: Task<Void, Never>?

    init(session: StudySession, store: ProgressStore) {
        self.session = session
        self.store = store
    }

    private var available: Bool { Bundle.main.bundleIdentifier != nil }

    func requestPermission() {
        guard available else { return }
        Task {
            let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
            authorized = granted
            if granted { scheduleSoon() }
        }
    }

    /// Reschedules about 2 seconds after the last change.
    func scheduleSoon() {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self?.schedule()
        }
    }

    func schedule() async {
        guard available else { return }
        let center = UNUserNotificationCenter.current()
        let ours = await center.pendingNotificationRequests().map(\.identifier)
            .filter { $0.hasPrefix(Self.idPrefix) || $0.hasPrefix(Self.oldPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)

        let settings = await center.notificationSettings()
        authorized = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        guard authorized == true, store.data.reminderOn, !session.cards.isEmpty else { scheduledCount = 0; return }

        let clock = session.clock
        let now = Date()
        var count = 0
        for day in session.revisionOutlook(days: 7) {
            guard let fire = clock.date(day.day, minute: store.data.reminderMinute), fire > now else { continue }
            let tasks = session.tasks(on: day.day).filter { !$0.done }
            let content = UNMutableNotificationContent()
            content.title = day.count > 0 ? "🔁 \(day.count) card\(day.count == 1 ? "" : "s") to revise today" : "📝 Today's plan"
            var lines: [String] = []
            if day.count > 0 { lines.append("Revise first: ~\(Int(day.minutes.rounded())) min.") }
            if !tasks.isEmpty {
                let first = tasks.prefix(2).map(\.text).joined(separator: " · ")
                lines.append("Then: \(first)\(tasks.count > 2 ? " +\(tasks.count - 2) more" : "")")
            }
            guard !lines.isEmpty else { continue }
            content.body = lines.joined(separator: " ")
            content.sound = .default
            let parts = clock.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            try? await center.add(UNNotificationRequest(
                identifier: "\(Self.idPrefix)\(day.day)", content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
            count += 1
        }
        scheduledCount = count
    }
}
