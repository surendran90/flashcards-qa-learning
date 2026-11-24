import XCTest
@testable import FlashCardsCore

/// Port of `src/excelImport.test.js`.
final class WorkbookParserTests: XCTestCase {
    private func sheet(_ name: String, _ rows: [[String]]) -> SheetData {
        SheetData(name: name, a1: rows.first?.first ?? "", rows: rows)
    }

    func testImportsMarkedTabsAndSkipsUnmarked() {
        let result = WorkbookParser.parse([
            sheet("Resume QA", [["QA"], ["Tell me about yourself", "A concise introduction."]]),
            sheet("Embedded QA", [["QA"], ["What is volatile?", "A qualifier for externally changing values."]]),
            sheet("Planner", [["Tasks"], ["Not a Q&A tab", "Should not be imported."]]),
        ])
        XCTAssertEqual(result.loadedSheets, ["Resume QA", "Embedded QA"])
        XCTAssertEqual(result.cards.count, 2)
        XCTAssertEqual(result.cards[0].topic, "Resume QA")
        XCTAssertEqual(result.cards[0].question, "Tell me about yourself")
        XCTAssertEqual(result.cards[0].answer, "A concise introduction.")
        XCTAssertEqual(result.cards[0].id, "resume qa-2")
        XCTAssertEqual(result.cards[1].topic, "Embedded QA")
    }

    func testOptionalHeadersAndDeduplication() {
        let result = WorkbookParser.parse([
            sheet("Resume QA", [
                ["Q&A"],
                ["ID", "Category", "Answer", "Question"],
                ["1", "Resume", "Reliable delivery.", "What does TCP provide?"],
                ["2", "Resume", "Repeated answer.", "What does TCP provide?"],
            ]),
        ])
        XCTAssertEqual(result.cards.count, 1)
        XCTAssertEqual(result.cards[0].question, "What does TCP provide?")
        XCTAssertEqual(result.cards[0].answer, "Reliable delivery.")
        XCTAssertEqual(result.duplicatesSkipped, 1)
    }

    func testRequiresQAMarkerInA1() {
        let result = WorkbookParser.parse([sheet("Resume QA", [["Question"], ["A question", "An answer"]])])
        XCTAssertTrue(result.cards.isEmpty)
    }

    func testRenamedTabBecomesCategory() {
        let result = WorkbookParser.parse([
            sheet("CV Preparation", [["QA"], ["What does a resume summary do?", "It introduces relevant qualifications."]]),
        ])
        XCTAssertEqual(result.loadedSheets, ["CV Preparation"])
        XCTAssertEqual(result.cards[0].topic, "CV Preparation")
    }

    func testAnswerFallsBackToNextNonEmptyColumn() {
        let result = WorkbookParser.parse([sheet("X QA", [["qa"], ["Q1", "", "", "Later answer"]])])
        XCTAssertEqual(result.cards[0].answer, "Later answer")
    }

    func testMarkerVariants() {
        for marker in ["QA", "qa", "Q&A", "Q / A", "Resume QA"] {
            XCTAssertTrue(WorkbookParser.hasQAMarker(marker), marker)
        }
        for marker in ["Question", "QAT", "Tasks", ""] {
            XCTAssertFalse(WorkbookParser.hasQAMarker(marker), marker)
        }
    }
}
