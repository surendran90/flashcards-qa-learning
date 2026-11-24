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

final class DailyPlanTests: XCTestCase {
    private let today = "2026-11-25"

    func testParsesWrittenPlan() {
        let text = """
        [Nov 25 ]
        Revise as per algo
        Daily two modules
        Embedded C program (Add new 30)
        Apply in Coimbatore

        [Nov 26 ]
        Revise as per algo
        All Sorting in C Program + linked list + Binary search

        [Nov 27 ]
        - Resume QA [Add + All]

        [Nov 28 ]
        Embedded QA + Add
        """
        let p = PlanText.parse(text, today: today, categories: ["Resume QA", "Embedded QA", "C Programs", "C QA"], clock: clock)
        XCTAssertEqual(p.skippedRevisionLines, 2)
        XCTAssertEqual(p.tasksByDay["2026-11-25"]?.map(\.text), ["Daily two modules", "Embedded C program (Add new 30)", "Apply in Coimbatore"])
        XCTAssertEqual(p.tasksByDay["2026-11-26"]?.count, 1)
        XCTAssertEqual(p.tasksByDay["2026-11-27"]?.first?.text, "Resume QA [Add + All]")
        XCTAssertEqual(p.tasksByDay["2026-11-27"]?.first?.link, TaskLink(category: "Resume QA"))
        XCTAssertEqual(p.tasksByDay["2026-11-28"]?.first?.link, TaskLink(category: "Embedded QA"))
        XCTAssertNil(p.tasksByDay["2026-11-25"]?[2].link, "no category named")
    }

    func testHeaderFormats() {
        XCTAssertEqual(PlanText.headerDay("[Nov 25 ]", today: today, clock: clock), "2026-11-25")
        XCTAssertEqual(PlanText.headerDay("25th November", today: today, clock: clock), "2026-11-25")
        XCTAssertEqual(PlanText.headerDay("Jan 3", today: today, clock: clock), "2027-01-03", "next January, not last")
        XCTAssertEqual(PlanText.headerDay("[2026-12-01]", today: today, clock: clock), "2026-12-01")
        XCTAssertNil(PlanText.headerDay("Daily two modules", today: today, clock: clock))
        XCTAssertNil(PlanText.headerDay("Apply aggressive", today: today, clock: clock))
        XCTAssertNil(PlanText.headerDay("Dec 5 interview prep", today: today, clock: clock))
    }

    func testRevisionOutlook() {
        var d = ProgressData()
        func card(_ due: String, last: String = "2026-11-20", intro: String = "2026-11-10") -> CardReview {
            CardReview(dueDay: due, lastReviewed: last, reviews: 2, lapses: 0, topic: "C QA",
                       stability: 3, difficulty: 5, introducedDay: intro)
        }
        d.cards = ["a": card("2026-11-20"), "b": card("2026-11-25"), "c": card("2026-11-26"),
                   "d": card("2026-11-28", last: today), "e": card("2026-11-28", last: today, intro: today)]
        let keys = ["a", "b", "c", "d", "e", "new"]
        XCTAssertEqual(Set(RevisionOutlook.dueKeys(d, keys: keys, on: today)), ["a", "b"], "overdue counts as due")
        XCTAssertEqual(RevisionOutlook.revisedToday(d, keys: keys, today: today), 1, "cards first learned today aren't revisions")
        let days = RevisionOutlook.days(d, cards: keys.map { ($0, "C QA") }, today: today, days: 4, clock: clock)
        XCTAssertEqual(days.map(\.count), [2, 1, 0, 2])
        XCTAssertEqual(days[0].minutes, 2, "1 min per C QA review by default")
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
        XCTAssertEqual(data.version, 3)
        XCTAssertEqual(data.timeLog.total(), 60)
        XCTAssertEqual(data.cards["abc"]?.dueDay, "2026-01-02")
        XCTAssertEqual(data.tasks, [:])
        XCTAssertTrue(data.reminderOn)
        XCTAssertEqual(data.reminderMinute, 540)
        XCTAssertEqual(data.cards["abc"]?.stability, 1, "ladder step 1 → 1-day stability")
    }

    func testReadsVersion2FileWithSessions() throws {
        let json = #"{"version":2,"slots":[{"id":"evening","name":"Evening","emoji":"🌙","start":1170,"end":1230,"focus":"lightReview","enabled":true}],"notifyLeadMinutes":15,"dayTargets":{},"dayDone":{"2026-11-24":["abc"]},"categoryMinutes":{"C QA":10}}"#
        let data = try JSONDecoder().decode(ProgressData.self, from: Data(json.utf8))
        XCTAssertEqual(data.categoryMinutes, ["C QA": 10], "settings that still exist are kept")
        let reencoded = String(decoding: try JSONEncoder().encode(data), as: UTF8.self)
        XCTAssertFalse(reencoded.contains("slots"), "session data is dropped")
    }
}
