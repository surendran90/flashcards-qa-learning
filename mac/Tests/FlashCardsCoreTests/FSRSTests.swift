import XCTest
@testable import FlashCardsCore

private let clock: DayClock = {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    return DayClock(calendar: cal)
}()

final class FSRSTests: XCTestCase {
    func testFirstReviewIntervalsMatchFSRS5Defaults() {
        let p = FSRS.preview(nil, today: "2026-01-01", clock: clock)
        XCTAssertEqual(p[.again], 1)
        XCTAssertEqual(p[.hard], 1)
        XCTAssertEqual(p[.good], 3)
        XCTAssertEqual(p[.easy], 16)
    }

    func testIntervalEqualsStabilityAt90Percent() {
        XCTAssertEqual(FSRS.interval(stability: 10, retention: 0.9), 10)
        XCTAssertEqual(FSRS.retrievability(days: 10, stability: 10), 0.9, accuracy: 0.0001)
    }

    func testRepeatedGoodGrowsIntervals() {
        var card: CardReview? = nil
        var day = "2026-01-01"
        var gaps: [Int] = []
        for _ in 0..<5 {
            card = FSRS.review(card, rating: .good, topic: "C QA", today: day, clock: clock)
            let gap = clock.days(from: day, to: card!.dueDay)
            gaps.append(gap)
            day = card!.dueDay
        }
        XCTAssertEqual(gaps, gaps.sorted(), "intervals keep growing: \(gaps)")
        XCTAssertGreaterThan(gaps.last!, 30)
        XCTAssertEqual(SpacedRepetition.status(card), .mastered)
    }

    func testEasyBeatsGoodBeatsHard() {
        let first = FSRS.review(nil, rating: .good, topic: "T", today: "2026-01-01", clock: clock)
        let p = FSRS.preview(first, today: first.dueDay, clock: clock)
        XCTAssertLessThan(p[.hard]!, p[.good]!)
        XCTAssertLessThan(p[.good]!, p[.easy]!)
        XCTAssertEqual(p[.again], 1)
    }

    func testAgainDropsStabilityAndCountsLapse() {
        var card = FSRS.review(nil, rating: .easy, topic: "T", today: "2026-01-01", clock: clock)
        card = FSRS.review(card, rating: .good, topic: "T", today: card.dueDay, clock: clock)
        let before = card.stability
        card = FSRS.review(card, rating: .again, topic: "T", today: card.dueDay, clock: clock)
        XCTAssertLessThan(card.stability, before)
        XCTAssertEqual(card.lapses, 1)
        XCTAssertEqual(clock.days(from: card.lastReviewed, to: card.dueDay), 1)
    }

    func testFirstAgainIsNotALapse() {
        let card = FSRS.review(nil, rating: .again, topic: "T", today: "2026-01-01", clock: clock)
        XCTAssertEqual(card.lapses, 0)
        XCTAssertEqual(card.introducedDay, "2026-01-01")
    }

    func testHigherRetentionGivesShorterIntervals() {
        let card = FSRS.review(nil, rating: .easy, topic: "T", today: "2026-01-01", clock: clock)
        let relaxed = FSRS.preview(card, today: card.dueDay, retention: 0.85, clock: clock)[.good]!
        let strict = FSRS.preview(card, today: card.dueDay, retention: 0.95, clock: clock)[.good]!
        XCTAssertLessThan(strict, relaxed)
    }

    func testSameDayRetryChangesStabilityOnlySlightly() {
        let again = FSRS.review(nil, rating: .again, topic: "T", today: "2026-01-01", clock: clock)
        let retry = FSRS.review(again, rating: .good, topic: "T", today: "2026-01-01", clock: clock)
        XCTAssertLessThan(retry.stability, 1, "still short after failing once today")
        XCTAssertGreaterThan(retry.stability, again.stability)
    }

    func testRepeatedFailuresMakeCardWeak() {
        var card = FSRS.review(nil, rating: .again, topic: "T", today: "2026-01-01", clock: clock)
        card = FSRS.review(card, rating: .again, topic: "T", today: "2026-01-02", clock: clock)
        XCTAssertTrue(SpacedRepetition.isWeak(card))
    }

    func testLegacyLadderReviewsConvert() throws {
        let json = #"{"step":3,"dueDay":"2026-01-08","lastReviewed":"2026-01-01","reviews":3,"lapses":1,"topic":"T"}"#
        let legacy = try JSONDecoder().decode(CardReview.self, from: Data(json.utf8))
        let m = FSRS.memory(of: legacy)!
        XCTAssertEqual(m.stability, 7)
        XCTAssertEqual(m.difficulty, 6)
        XCTAssertEqual(SpacedRepetition.status(legacy), .learning)
        XCTAssertTrue(SpacedRepetition.isDue(legacy, on: "2026-01-08"))
    }

    func testIntervalLabels() {
        XCTAssertEqual(FSRS.intervalLabel(3), "3d")
        XCTAssertEqual(FSRS.intervalLabel(61), "2.0mo")
        XCTAssertEqual(FSRS.intervalLabel(400), "1.1y")
    }
}
