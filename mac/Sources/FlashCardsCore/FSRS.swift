import Foundation

/// How well you recalled a card.
public enum Rating: Int, Codable, CaseIterable, Sendable {
    case again = 1, hard, good, easy

    public var label: String {
        switch self {
        case .again: return "Again"
        case .hard: return "Hard"
        case .good: return "Good"
        case .easy: return "Easy"
        }
    }

    public var emoji: String {
        switch self {
        case .again: return "❌"
        case .hard: return "😬"
        case .good: return "✅"
        case .easy: return "⭐"
        }
    }
}

/// FSRS-5 (Free Spaced Repetition Scheduler), the default scheduler in Anki since 23.10.
///
/// Each card has a memory **stability** S (days until recall probability falls to 90%) and a
/// **difficulty** D (1–10). The next review is set for when recall would drop to your target
/// retention. Uses the published FSRS-5 default parameters.
public enum FSRS {
    public static let w: [Double] = [
        0.40255, 1.18385, 3.173, 15.69105, 7.1949, 0.5345, 1.4604, 0.0046, 1.54575, 0.1192,
        1.01925, 1.9395, 0.11, 0.29605, 2.2698, 0.2315, 2.9898, 0.51655, 0.6621,
    ]
    static let decay = -0.5
    static let factor = 19.0 / 81.0
    public static let maxIntervalDays = 36500
    public static let defaultRetention = 0.9
    /// Stability (days) from which a card counts as mastered: ~90% recall three weeks out.
    public static let masteredStability = 21.0

    public struct Memory: Equatable, Sendable {
        public var stability: Double
        public var difficulty: Double

        public init(stability: Double, difficulty: Double) {
            self.stability = stability
            self.difficulty = difficulty
        }
    }

    /// Probability of recall after `days` with stability `stability`.
    public static func retrievability(days: Double, stability: Double) -> Double {
        pow(1 + factor * max(0, days) / max(0.01, stability), decay)
    }

    /// Days until recall falls to `retention`.
    public static func interval(stability: Double, retention: Double = defaultRetention) -> Int {
        let r = min(0.99, max(0.5, retention))
        let days = stability / factor * (pow(r, 1 / decay) - 1)
        return max(1, min(maxIntervalDays, Int(days.rounded())))
    }

    static func clampD(_ d: Double) -> Double { min(10, max(1, d)) }

    static func initialStability(_ g: Rating) -> Double { max(0.1, w[g.rawValue - 1]) }

    static func initialDifficulty(_ g: Rating) -> Double {
        clampD(w[4] - exp(w[5] * Double(g.rawValue - 1)) + 1)
    }

    static func nextDifficulty(_ d: Double, _ g: Rating) -> Double {
        let delta = -w[6] * Double(g.rawValue - 3)
        let damped = d + delta * (10 - d) / 9
        return clampD(w[7] * initialDifficulty(.easy) + (1 - w[7]) * damped)
    }

    static func recallStability(d: Double, s: Double, r: Double, _ g: Rating) -> Double {
        let hardPenalty = g == .hard ? w[15] : 1
        let easyBonus = g == .easy ? w[16] : 1
        return s * (exp(w[8]) * (11 - d) * pow(s, -w[9]) * (exp(w[10] * (1 - r)) - 1) * hardPenalty * easyBonus + 1)
    }

    static func forgetStability(d: Double, s: Double, r: Double) -> Double {
        min(s, w[11] * pow(d, -w[12]) * (pow(s + 1, w[13]) - 1) * exp(w[14] * (1 - r)))
    }

    static func sameDayStability(s: Double, _ g: Rating) -> Double {
        s * exp(w[17] * (Double(g.rawValue - 3) + w[18]))
    }

    /// Memory after a review `elapsedDays` after the previous one (nil = first review).
    public static func next(_ memory: Memory?, rating g: Rating, elapsedDays: Int) -> Memory {
        guard let m = memory else {
            return Memory(stability: initialStability(g), difficulty: initialDifficulty(g))
        }
        let d = nextDifficulty(m.difficulty, g)
        let s: Double
        if elapsedDays <= 0 {
            s = sameDayStability(s: m.stability, g)
        } else {
            let r = retrievability(days: Double(elapsedDays), stability: m.stability)
            s = g == .again ? forgetStability(d: m.difficulty, s: m.stability, r: r)
                            : recallStability(d: m.difficulty, s: m.stability, r: r, g)
        }
        return Memory(stability: max(0.01, s), difficulty: d)
    }

    public static func memory(of review: CardReview?) -> Memory? {
        review.map { Memory(stability: $0.stability, difficulty: $0.difficulty) }
    }

    /// Converts a review saved before FSRS (old fixed ladder 1/3/7/16/35/75 days).
    public static func legacyMemory(step: Int, lapses: Int) -> Memory {
        let ladder = [1.0, 3, 7, 16, 35, 75]
        let s = step <= 0 ? 0.5 : ladder[min(step, ladder.count) - 1]
        return Memory(stability: s, difficulty: clampD(5 + Double(lapses)))
    }

    /// Applies one rating to a card and schedules its next review.
    public static func review(
        _ existing: CardReview?, rating: Rating, topic: String, today: String,
        retention: Double = defaultRetention, clock: DayClock = DayClock()
    ) -> CardReview {
        let elapsed = existing.map { clock.days(from: $0.lastReviewed, to: today) } ?? 0
        let m = next(memory(of: existing), rating: rating, elapsedDays: elapsed)
        let days = rating == .again ? 1 : interval(stability: m.stability, retention: retention)
        var card = existing ?? CardReview(dueDay: today, lastReviewed: today, reviews: 0, lapses: 0, topic: topic,
                                          stability: m.stability, difficulty: m.difficulty, introducedDay: today)

        card.stability = m.stability
        card.difficulty = m.difficulty
        card.lastRating = rating.rawValue
        card.reviews += 1
        if rating == .again && existing != nil { card.lapses += 1 }
        card.lastReviewed = today
        card.topic = topic
        card.dueDay = clock.add(days, to: today)
        return card
    }

    /// Days until the next review for each rating, for the answer buttons.
    public static func preview(_ existing: CardReview?, today: String, retention: Double = defaultRetention,
                               clock: DayClock = DayClock()) -> [Rating: Int] {
        var out: [Rating: Int] = [:]
        for g in Rating.allCases {
            let r = review(existing, rating: g, topic: existing?.topic ?? "", today: today, retention: retention, clock: clock)
            out[g] = clock.days(from: today, to: r.dueDay)
        }
        return out
    }

    /// "1d", "16d", "2.5mo", "1.2y"
    public static func intervalLabel(_ days: Int) -> String {
        if days < 30 { return "\(days)d" }
        if days < 365 { return String(format: "%.1fmo", Double(days) / 30.4) }
        return String(format: "%.1fy", Double(days) / 365)
    }
}
