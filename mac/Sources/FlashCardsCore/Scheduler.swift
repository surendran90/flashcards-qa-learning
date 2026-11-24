import Foundation

/// Fixed checkpoints and FSRS, side by side.
///
/// Both start the day you study a card:
/// - 📅 **Fixed checkpoints:** revised 1, 3, 7 and 14 days later, whatever you rate it. "Again" restarts them.
/// - 🧠 **FSRS:** its own date from how well you remember the card, updated by every review.
///
/// The card is due on whichever date comes first. After the day-14 checkpoint only FSRS is left.
/// Cards scheduled by FSRS alone (before checkpoints existed) stay on FSRS.
public enum Scheduler {
    /// Days after studying (or restarting) on which a card is revised.
    public static let checkpoints = [1, 3, 7, 14]
    /// `checkpointsDone` value meaning "checkpoints (and FSRS) start at the next review".
    public static let startsAtNextReview = -1

    /// Which method schedules a card.
    public enum Phase: Equatable, Sendable {
        /// Due now; its checkpoints (and a fresh FSRS history) start when you revise it.
        case startsAtNextReview
        /// On the fixed checkpoints: `number` of 4, revised `day` days after the start.
        case checkpoint(number: Int, day: Int)
        case fsrs
    }

    public static func phase(of review: CardReview?) -> Phase? {
        guard let r = review else { return nil }
        guard r.checkpointAnchor != nil || r.checkpointsDone == startsAtNextReview, let d = r.checkpointsDone else { return .fsrs }
        if d == startsAtNextReview { return .startsAtNextReview }
        if d < checkpoints.count { return .checkpoint(number: d + 1, day: checkpoints[d]) }
        return .fsrs
    }

    /// Which method sets a card's next date.
    public enum Method: Sendable { case fixed, fsrs }

    /// Next fixed-checkpoint date, or nil when the card has no checkpoints left.
    public static func checkpointDue(of r: CardReview?, clock: DayClock = DayClock()) -> String? {
        guard let r, let d = r.checkpointsDone else { return nil }
        if d == startsAtNextReview { return r.dueDay }
        guard let anchor = r.checkpointAnchor, (0..<checkpoints.count).contains(d) else { return nil }
        // A late review still waits at least a day.
        return max(clock.add(checkpoints[d], to: anchor), clock.add(1, to: r.lastReviewed))
    }

    /// FSRS's next date.
    public static func fsrsDue(of r: CardReview?) -> String? {
        guard let r else { return nil }
        if r.checkpointsDone == startsAtNextReview { return r.dueDay }
        return r.fsrsDueDay ?? r.dueDay
    }

    /// The method whose date is the card's due date (the fixed checkpoint wins a tie).
    public static func nextMethod(of r: CardReview?, clock: DayClock = DayClock()) -> Method? {
        guard let r else { return nil }
        if let cp = checkpointDue(of: r, clock: clock), cp <= r.dueDay { return .fixed }
        return .fsrs
    }

    /// Puts every studied card back on the checkpoints: all are due `today`, and each one's
    /// checkpoints and FSRS history start fresh when it's revised. Returns how many changed.
    @discardableResult
    public static func restartAll(_ data: inout ProgressData, today: String) -> Int {
        for key in data.cards.keys {
            data.cards[key]?.dueDay = today
            data.cards[key]?.checkpointAnchor = nil
            data.cards[key]?.checkpointsDone = startsAtNextReview
            data.cards[key]?.fsrsDueDay = nil
        }
        return data.cards.count
    }

    public static func review(
        _ existing: CardReview?, rating: Rating, topic: String, today: String,
        retention: Double = FSRS.defaultRetention, useCheckpoints: Bool = true, clock: DayClock = DayClock()
    ) -> CardReview {
        // A restarted card begins a fresh FSRS history today (its counts and first-study day are kept).
        let restarting = existing?.checkpointsDone == startsAtNextReview
        var card = FSRS.review(restarting ? nil : existing, rating: rating, topic: topic, today: today,
                               retention: retention, clock: clock)
        if restarting, let old = existing {
            card.reviews = old.reviews + 1
            card.lapses = old.lapses
            card.introducedDay = old.introducedDay ?? today
        }
        let fsrsDate = card.dueDay
        guard useCheckpoints else {
            card.checkpointAnchor = nil
            card.checkpointsDone = nil
            card.fsrsDueDay = nil
            return card
        }

        var anchor: String
        var done: Int
        if restarting || existing == nil {
            anchor = today
            done = 0
        } else if let existing, let a = existing.checkpointAnchor, let d = existing.checkpointsDone,
                  d < checkpoints.count {
            if rating == .again {
                anchor = today
                done = 0
            } else if let cp = checkpointDue(of: existing, clock: clock), cp <= today {
                anchor = a
                done = d + 1 // this review is the checkpoint
            } else {
                // Revised early (FSRS was due first, or a same-day retry): the checkpoint still stands.
                anchor = a
                done = d
            }
        } else {
            card.fsrsDueDay = nil
            return card // FSRS only (graduated, or scheduled before checkpoints existed)
        }

        card.checkpointAnchor = anchor
        if done >= checkpoints.count {
            card.checkpointsDone = checkpoints.count
            card.fsrsDueDay = nil
            return card // all checkpoints done: only FSRS is left
        }
        card.checkpointsDone = done
        card.fsrsDueDay = fsrsDate
        let checkpoint = max(clock.add(checkpoints[done], to: anchor), clock.add(1, to: today))
        card.dueDay = min(checkpoint, fsrsDate)
        return card
    }

    /// Days until the next review for each rating, for the answer buttons.
    public static func preview(
        _ existing: CardReview?, today: String, retention: Double = FSRS.defaultRetention,
        useCheckpoints: Bool = true, clock: DayClock = DayClock()
    ) -> [Rating: Int] {
        var out: [Rating: Int] = [:]
        for g in Rating.allCases {
            let r = review(existing, rating: g, topic: existing?.topic ?? "", today: today,
                           retention: retention, useCheckpoints: useCheckpoints, clock: clock)
            out[g] = clock.days(from: today, to: r.dueDay)
        }
        return out
    }

    /// "Checkpoint 2 of 4 · day 3" while on the fixed checkpoints, else nil.
    public static func stage(_ review: CardReview?) -> String? {
        switch phase(of: review) {
        case .checkpoint(let n, let day): return "Checkpoint \(n) of \(checkpoints.count) · day \(day)"
        case .startsAtNextReview: return "Checkpoints start today"
        default: return nil
        }
    }
}
