import FlashCardsCore
import Foundation
import Observation
import UserNotifications

/// Schedules a reminder before each study session for the next 14 days, saying what to cover.
/// macOS delivers them even when the app is closed.
@MainActor @Observable
final class SessionNotifier {
    static let idPrefix = "session-"

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
            let center = UNUserNotificationCenter.current()
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            authorized = granted
            if granted { scheduleSoon() }
        }
    }

    func refreshAuthorization() {
        guard available else { return }
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            authorized = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
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
        guard available, !session.cards.isEmpty else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        authorized = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        guard authorized == true else { return }

        let old = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(Self.idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: old)

        let clock = session.clock
        let lead = store.data.notifyLeadMinutes
        let slots = session.studySlots
        let forecast = session.forecast(days: 14)
        let now = Date()
        var count = 0
        for day in forecast.days {
            for (slot, plan) in zip(slots, day.slots) {
                guard plan.newCount + plan.reviewCount > 0,
                      let fire = clock.date(day.day, minute: slot.start - lead), fire > now else { continue }
                let content = UNMutableNotificationContent()
                content.title = "\(slot.emoji) \(slot.name) session at \(StudySlot.timeLabel(slot.start))"
                content.body = body(slot: slot, plan: plan, isToday: day.day == session.today)
                content.sound = .default
                let parts = clock.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
                let request = UNNotificationRequest(
                    identifier: "\(Self.idPrefix)\(day.day)-\(slot.id)", content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
                try? await center.add(request)
                count += 1
            }
        }
        scheduledCount = count
    }

    private func body(slot: StudySlot, plan: SlotForecast, isToday: Bool) -> String {
        var parts: [String] = []
        if isToday {
            let left = session.remaining(slot)
            if !left.new.isEmpty { parts.append("learn \(left.new.count) new (\(breakdown(left.new)))") }
            if !left.review.isEmpty { parts.append("revise \(left.review.count) (\(breakdown(left.review)))") }
        } else {
            if plan.newCount > 0 { parts.append("learn \(plan.newCount) new") }
            if plan.reviewCount > 0 { parts.append("revise \(plan.reviewCount) cards") }
        }
        if plan.carried > 0 { parts.append("incl. \(plan.carried) carried over") }
        let text = parts.joined(separator: ", ")
        return (text.prefix(1).uppercased() + text.dropFirst()) + ". ~\(Int(plan.minutes.rounded())) min."
    }

    private func breakdown(_ keys: [String]) -> String {
        let counts = Dictionary(grouping: session.cards(for: keys), by: \.topic).mapValues(\.count)
        return counts.sorted { $0.value > $1.value }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
    }
}
