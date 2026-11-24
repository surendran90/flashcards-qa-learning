import XCTest
@testable import FlashCardsCore

private let clock: DayClock = {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    return DayClock(calendar: cal)
}()

private let day = "2026-01-05"

final class CardTimingTests: XCTestCase {
    func testDefaultsAndOverrides() {
        XCTAssertEqual(CardTiming.minutes(for: "C Programs", overrides: [:]), 20)
        XCTAssertEqual(CardTiming.minutes(for: "C QA", overrides: [:]), 5)
        XCTAssertEqual(CardTiming.minutes(for: "C QA", overrides: ["C QA": 8]), 8)
        XCTAssertEqual(CardTiming.minutes(for: "Module Knowelege", overrides: [:]), 20)
    }

    func testDisplayAndOvertime() {
        XCTAssertEqual(CardTiming.display(remaining: CardTiming.remaining(limitMinutes: 5, elapsed: 0)), "5:00")
        XCTAssertEqual(CardTiming.display(remaining: CardTiming.remaining(limitMinutes: 5, elapsed: 0.6)), "5:00")
        XCTAssertEqual(CardTiming.display(remaining: CardTiming.remaining(limitMinutes: 5, elapsed: 61)), "3:59")
        XCTAssertEqual(CardTiming.display(remaining: CardTiming.remaining(limitMinutes: 5, elapsed: 380)), "+1:20")
    }

    func testCostModelCalibratesFromRealTimes() {
        var cost = CostModel()
        XCTAssertEqual(cost.newMinutes("C Programs"), 20)
        XCTAssertEqual(cost.reviewMinutes("C Programs"), 4)
        XCTAssertEqual(cost.reviewMinutes("C QA"), 1)
        var stats = TimingStats()
        stats.newSeconds = 10 * 180
        stats.newCount = 10
        cost.timing["C QA"] = stats
        XCTAssertEqual(cost.newMinutes("C QA"), 3, accuracy: 0.001)
    }
}

final class SessionPlannerTests: XCTestCase {
    private let slots = [
        StudySlot(id: "morning", name: "Morning", emoji: "🌅", start: 570, end: 630, focus: .learnNew),       // 60 min
        StudySlot(id: "jobsearch", name: "Job search", emoji: "💼", start: 720, end: 870, focus: .jobSearch),
        StudySlot(id: "afternoon", name: "Afternoon", emoji: "☀️", start: 870, end: 990, focus: .review),     // 120 min
        StudySlot(id: "evening", name: "Evening", emoji: "🌙", start: 1170, end: 1230, focus: .review),      // 60 min
    ]

    private func cards(qa: Int, programs: Int) -> [PlanCard] {
        (0..<qa).map { PlanCard(key: "qa\($0)", topic: "C QA") }
            + (0..<programs).map { PlanCard(key: "p\($0)", topic: "C Programs") }
    }

    private func data() -> ProgressData {
        var d = ProgressData()
        d.slots = slots
        return d
    }

    func testMorningMixesCategoriesWithinBudget() {
        var d = data()
        SessionPlanner.lockDay(&d, cards: cards(qa: 10, programs: 4), day: day, clock: clock)
        let morning = d.dayTargets[day]!.slots["morning"]!
        XCTAssertEqual(morning.newKeys.filter { $0.hasPrefix("qa") }.count, 4)
        XCTAssertEqual(morning.newKeys.filter { $0.hasPrefix("p") }.count, 2, "60 min = 2×20 + 4×5")
        XCTAssertTrue(d.dayTargets[day]!.slots["afternoon"]!.allKeys.isEmpty, "nothing due yet")
        XCTAssertNil(d.dayTargets[day]!.slots["jobsearch"], "job search isn't a study session")
    }

    func testOnlyDueCardsGoToReviewSessions() {
        var d = data()
        for i in 0..<3 {
            d.cards["qa\(i)"] = CardReview(dueDay: "2026-01-04", lastReviewed: "2026-01-03", reviews: 1, lapses: 0, topic: "C QA",
                                           stability: 1, difficulty: 5)
        }
        d.cards["qa3"] = CardReview(dueDay: "2026-01-09", lastReviewed: "2026-01-04", reviews: 4, lapses: 2, topic: "C QA",
                                    stability: 0.5, difficulty: 9)
        SessionPlanner.lockDay(&d, cards: cards(qa: 6, programs: 0), day: day, clock: clock)
        let afternoon = d.dayTargets[day]!.slots["afternoon"]!
        XCTAssertEqual(Set(afternoon.reviewKeys), ["qa0", "qa1", "qa2"], "weak but not-yet-due cards wait for FSRS")
        XCTAssertEqual(Set(d.dayTargets[day]!.slots["morning"]!.newKeys), ["qa4", "qa5"])
    }

    func testLockedTargetsDoNotChange() {
        var d = data()
        let c = cards(qa: 10, programs: 0)
        SessionPlanner.lockDay(&d, cards: c, day: day, clock: clock)
        let before = d.dayTargets[day]
        d.slots[0].end = 700
        SessionPlanner.lockDay(&d, cards: c, day: day, clock: clock)
        XCTAssertEqual(d.dayTargets[day], before)
    }

    func testMissedSessionCarriesToNextSession() {
        var d = data()
        SessionPlanner.lockDay(&d, cards: cards(qa: 20, programs: 0), day: day, clock: clock)
        let morning = d.dayTargets[day]!.slots["morning"]!.newKeys
        XCTAssertEqual(morning.count, 12)
        d.markDone(morning[0], on: day)
        d.markDone(morning[1], on: day)

        SessionPlanner.rollOver(&d, day: day, nowMinute: 12 * 60 + 30, clock: clock)
        let afternoon = d.dayTargets[day]!.slots["afternoon"]!
        XCTAssertEqual(afternoon.carriedKeys.count, 10)
        XCTAssertEqual(afternoon.newKeys.count, 10)
        XCTAssertEqual(SessionPlanner.status(of: slots[0], on: day, data: d, nowMinute: 750), .missed)
        XCTAssertEqual(SessionPlanner.status(of: slots[2], on: day, data: d, nowMinute: 750), .upcoming)

        // Rolling over twice does nothing more.
        SessionPlanner.rollOver(&d, day: day, nowMinute: 12 * 60 + 30, clock: clock)
        XCTAssertEqual(d.dayTargets[day]!.slots["afternoon"]!.carriedKeys.count, 10)
    }

    func testLastSessionCarriesToTomorrowsFirstSession() {
        var d = data()
        let c = cards(qa: 20, programs: 0)
        SessionPlanner.lockDay(&d, cards: c, day: day, clock: clock)
        SessionPlanner.rollOver(&d, day: day, nowMinute: 23 * 60, clock: clock)
        let tomorrow = clock.add(1, to: day)
        XCTAssertEqual(d.dayTargets[tomorrow]!.carryInNew.count, 12)

        SessionPlanner.lockDay(&d, cards: c, day: tomorrow, clock: clock)
        let first = d.dayTargets[tomorrow]!.slots["morning"]!
        XCTAssertEqual(first.carriedKeys.count, 12)
        XCTAssertEqual(first.newKeys.count, 12, "carried cards fill the morning budget")
    }

    func testBusyTodayMovesEverythingToTomorrow() {
        var d = data()
        SessionPlanner.lockDay(&d, cards: cards(qa: 20, programs: 0), day: day, clock: clock)
        SessionPlanner.skipRest(&d, day: day, clock: clock)
        XCTAssertEqual(SessionPlanner.status(of: slots[0], on: day, data: d, nowMinute: 600), .skipped)
        XCTAssertEqual(d.dayTargets[clock.add(1, to: day)]!.carryInNew.count, 12)
    }

    func testCatchUpAfterAppWasClosedForDays() {
        var d = data()
        let c = cards(qa: 20, programs: 0)
        SessionPlanner.lockDay(&d, cards: c, day: day, clock: clock)
        let later = clock.add(3, to: day)
        SessionPlanner.catchUp(&d, today: later, clock: clock)
        XCTAssertEqual(d.dayTargets[later]!.carryInNew.count, 12)
        SessionPlanner.lockDay(&d, cards: c, day: later, clock: clock)
        XCTAssertEqual(d.dayTargets[later]!.slots["morning"]!.carriedKeys.count, 12)
    }

    func testForecastFinishDateAndSlipWhenSkipping() {
        var d = data()
        let c = cards(qa: 24, programs: 0)
        SessionPlanner.lockDay(&d, cards: c, day: day, clock: clock)
        let plan = SessionPlanner.forecast(d, cards: c, today: day, clock: clock)
        XCTAssertEqual(plan.learnedBy, clock.add(1, to: day), "12 today + 12 tomorrow")
        XCTAssertNotNil(plan.masteredBy)
        XCTAssertEqual(plan.days.count, 14)
        XCTAssertEqual(plan.days[0].newCount, 12)
        XCTAssertEqual(plan.days[1].reviewCount, 0, "a first Good rating lasts about 3 days")
        XCTAssertEqual(plan.days[3].reviewCount, 12, "today's new cards come back on day 3")
        XCTAssertEqual(d.dayTargets[day]!.learnedByAtLock, plan.learnedBy)

        SessionPlanner.skipRest(&d, day: day, clock: clock)
        let slipped = SessionPlanner.forecast(d, cards: c, today: day, clock: clock)
        XCTAssertEqual(slipped.days[0].newCount, 0)
        XCTAssertEqual(slipped.learnedBy, clock.add(2, to: day), "a skipped day pushes the finish date")
    }

    func testForecastWithoutLearningSessionHasNoFinishDate() {
        var d = data()
        d.slots[0].enabled = false
        let c = cards(qa: 5, programs: 0)
        XCTAssertNil(SessionPlanner.forecast(d, cards: c, today: day, clock: clock).learnedBy)
    }
}

final class MigrationTests: XCTestCase {
    func testReadsVersion1File() throws {
        let v1 = """
        {"version":1,"timer":{"phase":"focus","remainingSeconds":1464,"completedFocusCount":0,
         "settings":{"focusMinutes":25,"shortBreakMinutes":5,"longBreakMinutes":15,"longBreakEvery":4,"autoStartNext":false,"playSound":true}},
         "timeLog":{"days":{"2026-01-01":{"study":{"C QA":60}}}},
         "cards":{"abc":{"step":1,"dueDay":"2026-01-02","lastReviewed":"2026-01-01","reviews":1,"lapses":0,"topic":"C QA","introducedDay":"2026-01-01"}},
         "plan":{"examDay":"2026-02-01","dailyMinutes":45,"categories":["C QA"]}}
        """
        let data = try JSONDecoder().decode(ProgressData.self, from: Data(v1.utf8))
        XCTAssertEqual(data.version, 2)
        XCTAssertEqual(data.timeLog.total(), 60)
        XCTAssertEqual(data.cards["abc"]?.dueDay, "2026-01-02")
        XCTAssertEqual(data.plan.categories, ["C QA"])
        XCTAssertEqual(data.slots, StudySlot.defaults)
        XCTAssertEqual(data.notifyLeadMinutes, 10)
        XCTAssertEqual(data.cards["abc"]?.stability, 1, "ladder step 1 → 1-day stability")
    }

    func testOldLightReviewFocusReadsAsReview() throws {
        let json = #"{"slots":[{"id":"evening","name":"Evening","emoji":"🌙","start":1170,"end":1230,"focus":"lightReview","enabled":true}]}"#
        let data = try JSONDecoder().decode(ProgressData.self, from: Data(json.utf8))
        XCTAssertEqual(data.slots.first?.focus, .review)
    }
}
