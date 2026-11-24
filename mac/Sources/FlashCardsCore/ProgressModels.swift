import CryptoKit
import Foundation

// MARK: - Days

/// Calendar days as "yyyy-MM-dd" strings in the user's time zone. Strings sort by date.
public struct DayClock: Sendable {
    public var calendar: Calendar

    public init(calendar: Calendar = .current) {
        var cal = calendar
        cal.locale = Locale(identifier: "en_US_POSIX")
        self.calendar = cal
    }

    public func key(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    public func date(_ key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    public func add(_ days: Int, to key: String) -> String {
        guard let d = date(key), let next = calendar.date(byAdding: .day, value: days, to: d) else { return key }
        return self.key(next)
    }

    /// Whole days from `from` to `to` (negative if `to` is earlier).
    public func days(from: String, to: String) -> Int {
        guard let a = date(from), let b = date(to) else { return 0 }
        return calendar.dateComponents([.day], from: a, to: b).day ?? 0
    }

    /// Minutes since midnight.
    public func minuteOfDay(_ date: Date) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    /// The moment `minute` minutes after midnight on `day`.
    public func date(_ day: String, minute: Int) -> Date? {
        date(day).flatMap { calendar.date(byAdding: .minute, value: minute, to: $0) }
    }
}

// MARK: - Card identity

public enum CardKey {
    /// Stable key from the question text, so history survives refreshes, imports and row moves.
    public static func make(_ question: String) -> String {
        let normalized = question.lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        let digest = SHA256.hash(data: Data(normalized.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}

extension Card {
    public var key: String { CardKey.make(question) }
}

// MARK: - Activities and timing

public enum Activity: String, Codable, Sendable, CaseIterable {
    case study, revise

    public var label: String { self == .study ? "Studying" : "Revising" }
}

/// Time box per card: 20 minutes for program and module-knowledge categories, 5 for other Q&A,
/// unless you pick another time for the category.
public enum CardTiming {
    /// Times offered on the card timer.
    public static let choices = [5, 10, 15, 20, 30]

    public static func defaultMinutes(for category: String) -> Int {
        let c = category.lowercased()
        return c.contains("program") || c.contains("module") ? 20 : 5
    }

    public static func minutes(for category: String, overrides: [String: Int]) -> Int {
        max(1, overrides[category] ?? defaultMinutes(for: category))
    }

    /// Remaining seconds (negative = overtime) for a card with `elapsed` seconds used.
    public static func remaining(limitMinutes: Int, elapsed: Double) -> Double {
        Double(limitMinutes * 60) - elapsed
    }

    /// "4:59", or "+1:20" in overtime.
    public static func display(remaining: Double) -> String {
        let over = remaining < 0
        let s = Int(abs(remaining).rounded(over ? .down : .up))
        return (over ? "+" : "") + String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Real seconds spent per card, used to calibrate session targets.
public struct TimingStats: Codable, Equatable, Sendable {
    public var newSeconds: Double = 0
    public var newCount = 0
    public var reviewSeconds: Double = 0
    public var reviewCount = 0

    public init() {}
}

/// The card timer's saved state, so the same card continues where it stopped.
public struct ActiveCardTimer: Codable, Equatable, Sendable {
    public var key: String
    public var day: String
    public var elapsed: Double

    public init(key: String, day: String, elapsed: Double) {
        self.key = key
        self.day = day
        self.elapsed = elapsed
    }
}

// MARK: - Reviews

public struct CardReview: Codable, Equatable, Sendable {
    public var dueDay: String
    public var lastReviewed: String
    public var reviews: Int
    public var lapses: Int
    public var topic: String
    /// Day the card was first practised.
    public var introducedDay: String?
    /// FSRS memory: days until recall falls to 90%, and difficulty 1–10.
    public var stability: Double
    public var difficulty: Double
    /// Last FSRS rating (1 Again … 4 Easy).
    public var lastRating: Int?
    /// Fixed checkpoints (revise 1, 3, 7, 14 days after studying): the day counting starts from,
    /// and how many checkpoint reviews are done. nil = the card is scheduled by FSRS alone.
    public var checkpointAnchor: String?
    public var checkpointsDone: Int?
    /// FSRS's own next date. It runs from the day you study, alongside the checkpoints;
    /// `dueDay` is whichever of the two comes first. nil = same as `dueDay` (FSRS-only cards).
    public var fsrsDueDay: String?

    public init(dueDay: String, lastReviewed: String, reviews: Int, lapses: Int, topic: String,
                stability: Double, difficulty: Double, introducedDay: String? = nil, lastRating: Int? = nil) {
        self.stability = stability
        self.difficulty = difficulty
        self.lastRating = lastRating
        self.dueDay = dueDay
        self.lastReviewed = lastReviewed
        self.reviews = reviews
        self.lapses = lapses
        self.topic = topic
        self.introducedDay = introducedDay
    }

    enum CodingKeys: String, CodingKey {
        case dueDay, lastReviewed, reviews, lapses, topic, introducedDay, stability, difficulty, lastRating, step,
             checkpointAnchor, checkpointsDone, fsrsDueDay
    }

    /// Reviews saved before FSRS have a ladder `step` instead of stability/difficulty; convert them once.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dueDay = try c.decode(String.self, forKey: .dueDay)
        lastReviewed = try c.decode(String.self, forKey: .lastReviewed)
        reviews = try c.decodeIfPresent(Int.self, forKey: .reviews) ?? 0
        lapses = try c.decodeIfPresent(Int.self, forKey: .lapses) ?? 0
        topic = try c.decodeIfPresent(String.self, forKey: .topic) ?? ""
        introducedDay = try c.decodeIfPresent(String.self, forKey: .introducedDay)
        lastRating = try c.decodeIfPresent(Int.self, forKey: .lastRating)
        checkpointAnchor = try c.decodeIfPresent(String.self, forKey: .checkpointAnchor)
        checkpointsDone = try c.decodeIfPresent(Int.self, forKey: .checkpointsDone)
        fsrsDueDay = try c.decodeIfPresent(String.self, forKey: .fsrsDueDay)
        if let s = try c.decodeIfPresent(Double.self, forKey: .stability),
           let d = try c.decodeIfPresent(Double.self, forKey: .difficulty) {
            stability = s
            difficulty = d
        } else {
            let legacy = FSRS.legacyMemory(step: try c.decodeIfPresent(Int.self, forKey: .step) ?? 0, lapses: lapses)
            stability = legacy.stability
            difficulty = legacy.difficulty
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(dueDay, forKey: .dueDay)
        try c.encode(lastReviewed, forKey: .lastReviewed)
        try c.encode(reviews, forKey: .reviews)
        try c.encode(lapses, forKey: .lapses)
        try c.encode(topic, forKey: .topic)
        try c.encodeIfPresent(introducedDay, forKey: .introducedDay)
        try c.encode(stability, forKey: .stability)
        try c.encode(difficulty, forKey: .difficulty)
        try c.encodeIfPresent(lastRating, forKey: .lastRating)
        try c.encodeIfPresent(checkpointAnchor, forKey: .checkpointAnchor)
        try c.encodeIfPresent(checkpointsDone, forKey: .checkpointsDone)
        try c.encodeIfPresent(fsrsDueDay, forKey: .fsrsDueDay)
    }
}

// MARK: - Daily tasks

/// What a task's ▶ Start opens: a whole category, or one section (divider) of it.
public struct TaskLink: Codable, Equatable, Hashable, Sendable {
    public var category: String
    /// Divider title inside the category; nil means the whole category.
    public var section: String?

    public init(category: String, section: String? = nil) {
        self.category = category
        self.section = section
    }

    public var label: String { section.map { "\(category) › \($0)" } ?? category }
}

/// A line in your own day plan, e.g. "Sorting + linked list + binary search" or "Apply in Coimbatore".
public struct PlanTask: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var text: String
    public var done: Bool
    public var link: TaskLink?

    public init(id: String = UUID().uuidString, text: String, done: Bool = false, link: TaskLink? = nil) {
        self.id = id
        self.text = text
        self.done = done
        self.link = link
    }
}

// MARK: - Stored data

public struct ProgressData: Codable, Equatable, Sendable {
    public static let currentVersion = 3

    public var version = ProgressData.currentVersion
    public var timeLog = TimeLog()
    public var cards: [String: CardReview] = [:]
    public var categoryMinutes: [String: Int] = [:]
    public var timing: [String: TimingStats] = [:]
    public var cardSeconds: [String: Double] = [:]
    public var activeCard: ActiveCardTimer?
    /// Your own tasks per day ("yyyy-MM-dd"), in the order you arranged them.
    public var tasks: [String: [PlanTask]] = [:]
    /// Morning revision reminder.
    public var reminderOn = true
    /// Minutes after midnight (default 9:00).
    public var reminderMinute = 9 * 60
    /// FSRS target recall probability at review time.
    public var desiredRetention = FSRS.defaultRetention
    /// Revise newly studied cards on fixed days (1, 3, 7, 14) before FSRS takes over.
    public var useCheckpoints = true
    /// Day all previously studied cards were restarted on the checkpoints (one-time switch-over).
    public var checkpointsRestartedDay: String?

    public init() {}

    enum CodingKeys: String, CodingKey {
        case version, timeLog, cards, categoryMinutes, timing, cardSeconds, activeCard,
             tasks, reminderOn, reminderMinute, desiredRetention, useCheckpoints, checkpointsRestartedDay
    }

    /// Reads every earlier version: missing fields get defaults; data from removed features
    /// (Pomodoro, study sessions and their targets) is dropped.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ProgressData()
        version = ProgressData.currentVersion
        timeLog = try c.decodeIfPresent(TimeLog.self, forKey: .timeLog) ?? d.timeLog
        cards = try c.decodeIfPresent([String: CardReview].self, forKey: .cards) ?? d.cards
        categoryMinutes = try c.decodeIfPresent([String: Int].self, forKey: .categoryMinutes) ?? d.categoryMinutes
        timing = try c.decodeIfPresent([String: TimingStats].self, forKey: .timing) ?? d.timing
        cardSeconds = try c.decodeIfPresent([String: Double].self, forKey: .cardSeconds) ?? d.cardSeconds
        activeCard = try c.decodeIfPresent(ActiveCardTimer.self, forKey: .activeCard)
        tasks = try c.decodeIfPresent([String: [PlanTask]].self, forKey: .tasks) ?? d.tasks
        reminderOn = try c.decodeIfPresent(Bool.self, forKey: .reminderOn) ?? d.reminderOn
        reminderMinute = try c.decodeIfPresent(Int.self, forKey: .reminderMinute) ?? d.reminderMinute
        desiredRetention = try c.decodeIfPresent(Double.self, forKey: .desiredRetention) ?? d.desiredRetention
        useCheckpoints = try c.decodeIfPresent(Bool.self, forKey: .useCheckpoints) ?? d.useCheckpoints
        checkpointsRestartedDay = try c.decodeIfPresent(String.self, forKey: .checkpointsRestartedDay)
    }

    /// Moves everything stored under a card key to a new key (the question text was edited).
    public mutating func renameCard(from old: String, to new: String) {
        guard old != new else { return }
        if let r = cards.removeValue(forKey: old) { cards[new] = r }
        if let s = cardSeconds.removeValue(forKey: old) { cardSeconds[new, default: 0] += s }
        if activeCard?.key == old { activeCard?.key = new }
    }
}
