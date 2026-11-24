import AppKit
import FlashCardsCore
import Foundation
import Observation

/// Timer for the card on screen. Each card gets a time box (5 min Q&A, 20 min C programs);
/// you start it yourself, and past the limit it keeps counting overtime.
/// Running time is logged as studying or revising per category and survives relaunches.
@MainActor @Observable
final class CardTimer {
    private let store: ProgressStore
    private let session: StudySession
    private let clock = DayClock()

    private(set) var card: Card?
    private(set) var elapsed: Double = 0
    private(set) var isRunning = false
    /// Shown after 50 minutes of timed work without a 5-minute pause.
    var showBreakNudge = false

    @ObservationIgnored private var lastTick: Date?
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var secondsSinceSave: Double = 0
    @ObservationIgnored private var alertedOvertime = false
    @ObservationIgnored private var workStreak: Double = 0
    @ObservationIgnored private var pausedAt: Date?
    @ObservationIgnored private var modeAtStart: Mode = .study

    static let breakAfter: Double = 50 * 60
    static let breakResetsAfter: Double = 5 * 60

    init(store: ProgressStore, session: StudySession) {
        self.store = store
        self.session = session
    }

    var limitMinutes: Int {
        CardTiming.minutes(for: card?.topic ?? "", overrides: store.data.categoryMinutes)
    }
    var remaining: Double { CardTiming.remaining(limitMinutes: limitMinutes, elapsed: elapsed) }
    var isOvertime: Bool { remaining < 0 }
    var fraction: Double { min(1, elapsed / Double(limitMinutes * 60)) }

    var todayTotal: Double { store.data.timeLog.total(day: clock.key(Date())) }

    // MARK: Card changes

    /// Called whenever the card on screen changes (or nil when leaving study/practice).
    func show(_ next: Card?) {
        guard next?.key != card?.key else { return }
        pause()
        recordTiming()
        card = next
        alertedOvertime = false
        if let next, let saved = store.data.activeCard, saved.key == next.key, saved.day == clock.key(Date()) {
            elapsed = saved.elapsed
        } else {
            elapsed = 0
        }
        modeAtStart = session.mode
    }

    /// Adds this card's time to the per-category averages used to size session targets.
    private func recordTiming() {
        guard let card, elapsed >= 10 else { return }
        var stats = store.data.timing[card.topic] ?? TimingStats()
        if modeAtStart == .study {
            stats.newSeconds += elapsed
            stats.newCount += 1
        } else {
            stats.reviewSeconds += elapsed
            stats.reviewCount += 1
        }
        store.data.timing[card.topic] = stats
    }

    // MARK: Controls

    func toggle() { isRunning ? pause() : start() }

    func start() {
        guard !isRunning, card != nil else { return }
        if let pausedAt, Date().timeIntervalSince(pausedAt) >= Self.breakResetsAfter {
            workStreak = 0
            showBreakNudge = false
        }
        isRunning = true
        lastTick = Date()
        modeAtStart = session.mode
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                self?.tick()
            }
        }
    }

    func pause() {
        guard isRunning else { return }
        tick()
        isRunning = false
        loop?.cancel()
        loop = nil
        lastTick = nil
        pausedAt = Date()
        store.saveNow()
    }

    func reset() {
        pause()
        elapsed = 0
        alertedOvertime = false
        saveActive()
        store.saveNow()
    }

    // MARK: Ticking

    private func tick() {
        guard isRunning, let last = lastTick, let card else { return }
        let now = Date()
        lastTick = now
        let credit = TimeLog.creditable(now.timeIntervalSince(last)) // ignores gaps while the Mac slept
        guard credit > 0 else { return }

        elapsed += credit
        workStreak += credit
        var data = store.data
        data.timeLog.add(credit, day: clock.key(now), activity: session.lastActivity, category: card.topic)
        data.cardSeconds[card.key, default: 0] += credit
        data.activeCard = ActiveCardTimer(key: card.key, day: clock.key(now), elapsed: elapsed)
        store.data = data

        if isOvertime && !alertedOvertime {
            alertedOvertime = true
            NSSound(named: "Glass")?.play()
        }
        if workStreak >= Self.breakAfter && !showBreakNudge {
            showBreakNudge = true
            NSSound(named: "Tink")?.play()
        }
        secondsSinceSave += credit
        if secondsSinceSave >= 30 {
            secondsSinceSave = 0
            store.saveNow()
        }
    }

    private func saveActive() {
        guard let card else { return }
        store.data.activeCard = ActiveCardTimer(key: card.key, day: clock.key(Date()), elapsed: elapsed)
    }

    func dismissBreakNudge() {
        showBreakNudge = false
        workStreak = 0
    }
}
