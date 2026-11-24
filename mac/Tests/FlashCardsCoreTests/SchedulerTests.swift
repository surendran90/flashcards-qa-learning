import XCTest
@testable import FlashCardsCore

private let clock: DayClock = {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    return DayClock(calendar: cal)
}()

final class SchedulerTests: XCTestCase {
    private func review(_ c: CardReview?, _ g: Rating, on day: String, checkpoints: Bool = true) -> CardReview {
        Scheduler.review(c, rating: g, topic: "C QA", today: day, useCheckpoints: checkpoints, clock: clock)
    }

    private func cp(_ c: CardReview) -> String? { Scheduler.checkpointDue(of: c, clock: clock) }

    func testCheckpointsRunOnDay1_3_7_14() {
        var c = review(nil, .good, on: "2026-11-25")          // studied
        XCTAssertEqual(cp(c), "2026-11-26")                     // day 1
        XCTAssertEqual(c.dueDay, "2026-11-26")
        XCTAssertEqual(Scheduler.stage(c), "Checkpoint 1 of 4 · day 1")
        for (day, next) in [("2026-11-26", "2026-11-28"), ("2026-11-28", "2026-12-02"), ("2026-12-02", "2026-12-09")] {
            c = review(c, .good, on: day)
            XCTAssertEqual(cp(c), next)
        }
        XCTAssertEqual(Scheduler.stage(c), "Checkpoint 4 of 4 · day 14")
        c = review(c, .good, on: "2026-12-09")
        XCTAssertNil(Scheduler.stage(c), "checkpoints finished")
        XCTAssertNil(cp(c))
        XCTAssertEqual(clock.days(from: "2026-12-09", to: c.dueDay), FSRS.interval(stability: c.stability), "only FSRS left")
        XCTAssertEqual(c.reviews, 5)
    }

    func testFSRSStartsTheDayYouStudy() {
        let c = review(nil, .good, on: "2026-11-25")
        let pure = FSRS.review(nil, rating: .good, topic: "C QA", today: "2026-11-25", clock: clock)
        XCTAssertEqual(c.fsrsDueDay, pure.dueDay, "FSRS has its own date from the first study")
        XCTAssertEqual(c.stability, pure.stability)
        XCTAssertEqual(Scheduler.nextMethod(of: c, clock: clock), .fixed, "day 1 comes before FSRS's day 3")
    }

    func testDueOnWhicheverComesFirst() {
        // A Hard rating makes FSRS want the card back before the day-7 checkpoint.
        var c = review(nil, .good, on: "2026-11-25")
        c = review(c, .good, on: "2026-11-26")
        c = review(c, .again, on: "2026-11-28")                  // restarts checkpoints, FSRS says tomorrow
        c = review(c, .hard, on: "2026-11-29")                   // day-1 checkpoint done; next checkpoint 12-01
        XCTAssertEqual(cp(c), "2026-12-01")
        XCTAssertEqual(c.dueDay, min("2026-12-01", c.fsrsDueDay!))

        // Revising on an FSRS date that comes before the checkpoint keeps the checkpoint.
        var d = review(nil, .good, on: "2026-11-25")
        d = review(d, .good, on: "2026-11-26")                   // day 1 done; checkpoint day 3 = 11-28
        d.fsrsDueDay = "2026-11-27"; d.dueDay = "2026-11-27"     // pretend FSRS wanted it sooner
        XCTAssertEqual(Scheduler.nextMethod(of: d, clock: clock), .fsrs)
        d = review(d, .good, on: "2026-11-27")
        XCTAssertEqual(d.checkpointsDone, 1, "FSRS review doesn't use up a checkpoint")
        XCTAssertEqual(cp(d), "2026-11-28")
        XCTAssertEqual(d.dueDay, "2026-11-28")
    }

    func testAgainRestartsCheckpoints() {
        var c = review(nil, .good, on: "2026-11-25")
        c = review(c, .good, on: "2026-11-26")
        c = review(c, .again, on: "2026-11-28")
        XCTAssertEqual(c.dueDay, "2026-11-29", "back tomorrow")
        XCTAssertEqual(c.checkpointAnchor, "2026-11-28")
        c = review(c, .good, on: "2026-11-29")
        XCTAssertEqual(cp(c), "2026-12-01", "day 3 counted from the restart")
    }

    func testSameDayRetryDoesNotUseUpACheckpoint() {
        var c = review(nil, .good, on: "2026-11-25")   // Studied
        c = review(c, .good, on: "2026-11-25")         // Test yourself, same day
        XCTAssertEqual(c.dueDay, "2026-11-26")
        XCTAssertEqual(c.checkpointsDone, 0)
        XCTAssertGreaterThan(c.reviews, 1, "FSRS still counts the retry")
    }

    func testLateReviewWaitsAtLeastADay() {
        var c = review(nil, .good, on: "2026-11-25")
        c = review(c, .good, on: "2026-11-30")         // day-1 checkpoint done 5 days late; day 3 has passed
        XCTAssertEqual(cp(c), "2026-12-01")
        c = review(c, .good, on: "2026-12-01")
        XCTAssertEqual(cp(c), "2026-12-02", "day 7 from the original study day")
    }

    func testCardsAlreadyOnFSRSStayOnFSRS() {
        let fsrsOnly = FSRS.review(nil, rating: .good, topic: "C QA", today: "2026-11-20", clock: clock)
        let c = review(fsrsOnly, .good, on: "2026-11-23")
        XCTAssertNil(c.checkpointAnchor)
        XCTAssertEqual(c.dueDay, FSRS.review(fsrsOnly, rating: .good, topic: "C QA", today: "2026-11-23", clock: clock).dueDay)
    }

    func testCheckpointsOffMeansPureFSRS() {
        let c = review(nil, .good, on: "2026-11-25", checkpoints: false)
        XCTAssertNil(c.checkpointAnchor)
        XCTAssertEqual(c.dueDay, "2026-11-28", "FSRS first Good is about 3 days")
    }

    func testPreviewShowsCheckpointDates() {
        let c = review(nil, .good, on: "2026-11-25")
        let p = Scheduler.preview(c, today: "2026-11-26", clock: clock)
        XCTAssertEqual(p[.again], 1)
        XCTAssertEqual(p[.hard], 2)
        XCTAssertEqual(p[.good], 2)
        XCTAssertEqual(p[.easy], 2, "the day-3 checkpoint comes before FSRS's date")
    }

    func testRestartAllMakesEverythingDueTodayAndStartsFresh() {
        var d = ProgressData()
        let old = FSRS.review(FSRS.review(nil, rating: .easy, topic: "C QA", today: "2026-11-01", clock: clock),
                              rating: .good, topic: "C QA", today: "2026-11-17", clock: clock)
        let onLadder = review(nil, .good, on: "2026-11-24")
        d.cards = ["old": old, "ladder": onLadder]
        XCTAssertEqual(Scheduler.restartAll(&d, today: "2026-11-25"), 2)
        XCTAssertEqual(d.cards["old"]?.dueDay, "2026-11-25")
        XCTAssertEqual(Scheduler.phase(of: d.cards["old"]), .startsAtNextReview)
        XCTAssertEqual(Scheduler.stage(d.cards["ladder"]), "Checkpoints start today")

        // Revising today starts day 1/3/7/14 from today, with a fresh FSRS memory.
        var c = review(d.cards["old"], .good, on: "2026-11-25")
        XCTAssertEqual(c.dueDay, "2026-11-26")
        XCTAssertEqual(Scheduler.phase(of: c), .checkpoint(number: 1, day: 1))
        XCTAssertEqual(c.stability, FSRS.review(nil, rating: .good, topic: "C QA", today: "2026-11-25", clock: clock).stability,
                       "FSRS history starts from today")
        XCTAssertEqual(c.reviews, 3, "review count kept")
        XCTAssertEqual(c.introducedDay, "2026-11-01", "first-study day kept")
        XCTAssertNil(d.cards["old"]?.fsrsDueDay)
        c = review(c, .good, on: "2026-11-26")
        XCTAssertEqual(cp(c), "2026-11-28")
    }

    func testPhases() {
        XCTAssertNil(Scheduler.phase(of: nil))
        let fsrsOnly = FSRS.review(nil, rating: .good, topic: "T", today: "2026-11-20", clock: clock)
        XCTAssertEqual(Scheduler.phase(of: fsrsOnly), .fsrs)
        var c = review(nil, .good, on: "2026-11-25")
        XCTAssertEqual(Scheduler.phase(of: c), .checkpoint(number: 1, day: 1))
        for day in ["2026-11-26", "2026-11-28", "2026-12-02", "2026-12-09"] { c = review(c, .good, on: day) }
        XCTAssertEqual(Scheduler.phase(of: c), .fsrs, "graduated")
    }

    func testCheckpointFieldsRoundTrip() throws {
        let c = review(nil, .good, on: "2026-11-25")
        let back = try JSONDecoder().decode(CardReview.self, from: JSONEncoder().encode(c))
        XCTAssertEqual(back, c)
    }
}
