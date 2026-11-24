import XCTest
@testable import FlashCardsCore

private let utc: DayClock = {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    return DayClock(calendar: cal)
}()

final class TimeLogTests: XCTestCase {
    func testAddAndTotals() {
        var log = TimeLog()
        log.add(60, day: "2026-01-01", activity: .study, category: "C QA")
        log.add(30, day: "2026-01-01", activity: .revise, category: "C QA")
        log.add(45, day: "2026-01-02", activity: .revise, category: "Resume QA")
        log.add(-5, day: "2026-01-02", activity: .revise, category: "Resume QA")
        XCTAssertEqual(log.total(day: "2026-01-01"), 90)
        XCTAssertEqual(log.total(day: "2026-01-01", activity: .study), 60)
        XCTAssertEqual(log.total(activity: .revise), 75)
        XCTAssertEqual(log.byCategory(), ["C QA": 90, "Resume QA": 45])
        XCTAssertEqual(log.byCategory(days: ["2026-01-02"]), ["Resume QA": 45])
    }

    func testSleepGapNotCredited() {
        XCTAssertEqual(TimeLog.creditable(1.02), 1.02)
        XCTAssertEqual(TimeLog.creditable(60), 60)
        XCTAssertEqual(TimeLog.creditable(600), 0)
        XCTAssertEqual(TimeLog.creditable(-3), 0)
    }

    func testDurationsFormatting() {
        XCTAssertEqual(Durations.short(5100), "1h 25m")
        XCTAssertEqual(Durations.short(720), "12m")
        XCTAssertEqual(Durations.clock(1122), "18:42")
    }
}

@MainActor
final class ProgressStoreTests: XCTestCase {
    func testSaveAndReload() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }

        let store = ProgressStore(folder: folder)
        store.data.timeLog.add(120, day: "2026-01-01", activity: .study, category: "C QA")
        store.data.activeCard = ActiveCardTimer(key: "abc", day: "2026-01-01", elapsed: 42)
        store.data.cards["abc"] = CardReview(dueDay: "2026-01-04", lastReviewed: "2026-01-01", reviews: 2, lapses: 0, topic: "C QA",
                                             stability: 3.2, difficulty: 5.3, introducedDay: "2026-01-01", lastRating: 3)
        store.data.plan = StudyPlan(categories: ["C QA"])
        store.data.categoryMinutes["C QA"] = 7
        store.saveNow()
        store.saveNow() // second save creates the backup

        let reloaded = ProgressStore(folder: folder)
        XCTAssertEqual(reloaded.data, store.data)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.fileURL.appendingPathExtension("bak").path))
    }

    func testFallsBackToBackupWhenMainFileIsCorrupt() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ProgressStore(folder: folder)
        store.data.notifyLeadMinutes = 25
        store.saveNow()
        store.saveNow()
        try Data("not json".utf8).write(to: store.fileURL)
        XCTAssertEqual(ProgressStore(folder: folder).data.notifyLeadMinutes, 25)
    }

    func testCardKeyIsStableAcrossRowsAndWhitespace() {
        let a = Card(id: "c qa-2", topic: "C QA", question: "What is  volatile?", answer: "", sourceSheet: "C QA", sourceRow: 2)
        let b = Card(id: "c-9", topic: "Renamed", question: " what is volatile? ", answer: "x", sourceSheet: "Renamed", sourceRow: 9)
        XCTAssertEqual(a.key, b.key)
        XCTAssertNotEqual(a.key, CardKey.make("What is static?"))
    }
}
