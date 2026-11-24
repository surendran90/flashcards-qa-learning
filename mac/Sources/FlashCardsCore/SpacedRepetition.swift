import Foundation

public enum CardStatus: String, Sendable, CaseIterable {
    case new, learning, mastered

    public var label: String { rawValue.capitalized }
}

/// Card status and due checks on top of the FSRS memory model.
public enum SpacedRepetition {
    public static let weakLapses = 2
    public static let weakDifficulty = 8.0

    public static func status(_ review: CardReview?) -> CardStatus {
        guard let m = FSRS.memory(of: review) else { return .new }
        return m.stability >= FSRS.masteredStability ? .mastered : .learning
    }

    /// Forgotten twice or more, or rated hard so often that FSRS considers it difficult.
    public static func isWeak(_ review: CardReview?) -> Bool {
        guard let review else { return false }
        return review.lapses >= weakLapses || review.difficulty >= weakDifficulty
    }

    public static func isDue(_ review: CardReview?, on day: String) -> Bool {
        guard let review else { return false }
        return review.dueDay <= day
    }
}
