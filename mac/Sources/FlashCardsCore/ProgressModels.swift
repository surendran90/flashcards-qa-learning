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

/// Time box per card: 20 minutes for program categories, 5 for Q&A, unless overridden.
public enum CardTiming {
    public static func defaultMinutes(for category: String) -> Int {
        category.lowercased().contains("program") ? 20 : 5
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
        case dueDay, lastReviewed, reviews, lapses, topic, introducedDay, stability, difficulty, lastRating, step
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
    }
}

// MARK: - Sessions

public enum SlotFocus: String, Codable, Sendable, CaseIterable {
    case learnNew, review, jobSearch

    public var label: String {
        switch self {
        case .learnNew: return "Learn new cards"
        case .review: return "Review due cards"
        case .jobSearch: return "Job search (not study)"
        }
    }

    public var isStudy: Bool { self != .jobSearch }

    /// The old "lightReview" focus is the same as review under FSRS.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = SlotFocus(rawValue: raw) ?? .review
    }
}

public struct StudySlot: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var emoji: String
    /// Minutes since midnight.
    public var start: Int
    public var end: Int
    public var focus: SlotFocus
    public var enabled: Bool

    public init(id: String, name: String, emoji: String, start: Int, end: Int, focus: SlotFocus, enabled: Bool = true) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.start = start
        self.end = end
        self.focus = focus
        self.enabled = enabled
    }

    public var minutes: Int { max(0, end - start) }

    /// "9:30" style.
    public static func timeLabel(_ minute: Int) -> String {
        String(format: "%d:%02d", minute / 60, minute % 60)
    }

    public var timeRange: String { "\(Self.timeLabel(start))–\(Self.timeLabel(end))" }

    /// Balanced ~5.5 h study day with a midday block for job search.
    public static let defaults: [StudySlot] = [
        StudySlot(id: "morning", name: "Morning", emoji: "🌅", start: 9 * 60 + 30, end: 12 * 60, focus: .learnNew),
        StudySlot(id: "jobsearch", name: "Job search", emoji: "💼", start: 12 * 60, end: 14 * 60 + 30, focus: .jobSearch),
        StudySlot(id: "afternoon", name: "Afternoon", emoji: "☀️", start: 14 * 60 + 30, end: 16 * 60 + 30, focus: .review),
        StudySlot(id: "evening", name: "Evening", emoji: "🌙", start: 19 * 60 + 30, end: 20 * 60 + 30, focus: .review),
    ]
}

/// What a session should cover on a given day.
public struct SlotTarget: Codable, Equatable, Sendable {
    public var newKeys: [String]
    public var reviewKeys: [String]
    /// Keys that came from an earlier session; shown as "carried".
    public var carriedKeys: [String]
    /// Set once the session's end has passed and leftovers moved on.
    public var rolledOver: Bool
    /// "Busy today": the session was skipped and its work moved to tomorrow.
    public var skipped: Bool

    public init(newKeys: [String] = [], reviewKeys: [String] = [], carriedKeys: [String] = [],
                rolledOver: Bool = false, skipped: Bool = false) {
        self.newKeys = newKeys
        self.reviewKeys = reviewKeys
        self.carriedKeys = carriedKeys
        self.rolledOver = rolledOver
        self.skipped = skipped
    }

    public var allKeys: [String] { newKeys + reviewKeys }
}

/// A day's locked session targets, plus work carried in before the day was locked.
public struct DayTargets: Codable, Equatable, Sendable {
    public var slots: [String: SlotTarget] = [:]
    public var locked = false
    public var carryInNew: [String] = []
    public var carryInReview: [String] = []
    /// "Learned by" estimate when the day was locked, to show if the finish date slipped.
    public var learnedByAtLock: String?

    public init() {}
}

public struct StudyPlan: Codable, Equatable, Sendable {
    /// Empty means all categories.
    public var categories: [String]

    public init(categories: [String] = []) {
        self.categories = categories
    }
}

// MARK: - Stored data

public struct ProgressData: Codable, Equatable, Sendable {
    public static let currentVersion = 2

    public var version = ProgressData.currentVersion
    public var timeLog = TimeLog()
    public var cards: [String: CardReview] = [:]
    public var plan = StudyPlan()
    public var slots: [StudySlot] = StudySlot.defaults
    public var categoryMinutes: [String: Int] = [:]
    public var timing: [String: TimingStats] = [:]
    public var cardSeconds: [String: Double] = [:]
    public var activeCard: ActiveCardTimer?
    public var dayTargets: [String: DayTargets] = [:]
    /// Keys studied or practised each day.
    public var dayDone: [String: [String]] = [:]
    public var notifyLeadMinutes = 10
    /// FSRS target recall probability at review time.
    public var desiredRetention = FSRS.defaultRetention

    public init() {}

    enum CodingKeys: String, CodingKey {
        case version, timeLog, cards, plan, slots, categoryMinutes, timing, cardSeconds, activeCard,
             dayTargets, dayDone, notifyLeadMinutes, desiredRetention
    }

    /// Reads version 1 files too: missing fields get defaults; the old Pomodoro state is dropped.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ProgressData()
        version = ProgressData.currentVersion
        timeLog = try c.decodeIfPresent(TimeLog.self, forKey: .timeLog) ?? d.timeLog
        cards = try c.decodeIfPresent([String: CardReview].self, forKey: .cards) ?? d.cards
        plan = (try? c.decodeIfPresent(StudyPlan.self, forKey: .plan)) ?? d.plan
        slots = try c.decodeIfPresent([StudySlot].self, forKey: .slots) ?? d.slots
        categoryMinutes = try c.decodeIfPresent([String: Int].self, forKey: .categoryMinutes) ?? d.categoryMinutes
        timing = try c.decodeIfPresent([String: TimingStats].self, forKey: .timing) ?? d.timing
        cardSeconds = try c.decodeIfPresent([String: Double].self, forKey: .cardSeconds) ?? d.cardSeconds
        activeCard = try c.decodeIfPresent(ActiveCardTimer.self, forKey: .activeCard)
        dayTargets = try c.decodeIfPresent([String: DayTargets].self, forKey: .dayTargets) ?? d.dayTargets
        dayDone = try c.decodeIfPresent([String: [String]].self, forKey: .dayDone) ?? d.dayDone
        notifyLeadMinutes = try c.decodeIfPresent(Int.self, forKey: .notifyLeadMinutes) ?? d.notifyLeadMinutes
        desiredRetention = try c.decodeIfPresent(Double.self, forKey: .desiredRetention) ?? d.desiredRetention
    }

    public func isDone(_ key: String, on day: String) -> Bool {
        dayDone[day]?.contains(key) ?? false
    }

    public mutating func markDone(_ key: String, on day: String) {
        if !isDone(key, on: day) { dayDone[day, default: []].append(key) }
    }
}
