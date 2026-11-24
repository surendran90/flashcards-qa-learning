import XCTest
import ZIPFoundation
@testable import FlashCardsCore

/// Builds a small but realistic .xlsx: shared strings, styles, a header row, an extra ID column,
/// a blank row, and a second sheet that must stay untouched.
enum Fixture {
    static let sheet1 = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><dimension ref="A1:C6"/><sheetData>\
    <row r="1"><c r="A1" t="s"><v>0</v></c></row>\
    <row r="2"><c r="A2" t="s"><v>1</v></c><c r="B2" t="s"><v>2</v></c><c r="C2" t="s"><v>3</v></c></row>\
    <row r="3"><c r="A3"><v>1</v></c><c r="B3" t="s" s="1"><v>4</v></c><c r="C3" t="s"><v>5</v></c></row>\
    <row r="4"><c r="A4"><v>2</v></c><c r="B4" t="s"><v>6</v></c><c r="C4" t="s"><v>7</v></c></row>\
    <row r="6"><c r="A6"><v>3</v></c><c r="B6" t="s"><v>8</v></c><c r="C6" t="s"><v>9</v></c></row>\
    </sheetData></worksheet>
    """
    static let sheet2 = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>\
    <row r="1"><c r="A1" t="s"><v>10</v></c></row></sheetData></worksheet>
    """
    static let strings = ["QA", "ID", "Question", "Answer", "What is C?", "A language.",
                          "What is a pointer?", "An address.", "What is malloc?", "Heap allocation.", "Notes"]

    static func make(in folder: URL) throws -> URL {
        let url = folder.appendingPathComponent("Prep.xlsx")
        let sst = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><sst xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" count=\"\(strings.count)\" uniqueCount=\"\(strings.count)\">"
            + strings.enumerated().map { i, s in
                // "Heap allocation." (index 9) is stored as rich text: "Heap" in bold.
                i == 9 ? "<si><r><rPr><b/><sz val=\"11\"/></rPr><t>Heap</t></r><r><rPr><sz val=\"11\"/></rPr><t xml:space=\"preserve\"> allocation.</t></r></si>"
                       : "<si><t>\(s)</t></si>"
            }.joined() + "</sst>"
        let files: [(String, String)] = [
            ("[Content_Types].xml", """
            <?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">\
            <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>\
            <Default Extension="xml" ContentType="application/xml"/>\
            <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>\
            <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>\
            <Override PartName="/xl/worksheets/sheet2.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>\
            <Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/></Types>
            """),
            ("_rels/.rels", """
            <?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
            <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>
            """),
            ("xl/workbook.xml", """
            <?xml version="1.0" encoding="UTF-8"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" \
            xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>\
            <sheet name="C QA" sheetId="1" r:id="rId1"/><sheet name="Notes" sheetId="2" r:id="rId2"/></sheets></workbook>
            """),
            ("xl/_rels/workbook.xml.rels", """
            <?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
            <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>\
            <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/>\
            <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" Target="sharedStrings.xml"/></Relationships>
            """),
            ("xl/worksheets/sheet1.xml", sheet1),
            ("xl/worksheets/sheet2.xml", sheet2),
            ("xl/sharedStrings.xml", sst),
        ]
        let archive = try Archive(url: url, accessMode: .create)
        for (path, text) in files {
            let data = Data(text.utf8)
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count), compressionMethod: .deflate) { pos, size in
                data.subdata(in: Int(pos)..<Int(pos) + size)
            }
        }
        return url
    }

    static func entry(_ url: URL, _ path: String) throws -> Data {
        let a = try Archive(url: url, accessMode: .read)
        var d = Data()
        _ = try a.extract(a[path]!) { d.append($0) }
        return d
    }
}

final class WorkbookWriterTests: XCTestCase {
    var folder: URL!
    var url: URL!
    var backups: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        url = try Fixture.make(in: folder)
        backups = folder.appendingPathComponent("backups")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func cards() throws -> [Card] { try WorkbookLoader.load(url: url).result.cards }

    func testLoaderRecordsRealRowsColumnsAndSheet() throws {
        let c = try cards()
        XCTAssertEqual(c.map(\.question), ["What is C?", "What is a pointer?", "What is malloc?"])
        XCTAssertEqual(c.map(\.excelRow), [3, 4, 6], "row 5 is blank, so the last card is on row 6")
        XCTAssertEqual(c[0].questionColumn, 1)
        XCTAssertEqual(c[0].answerColumn, 2)
        XCTAssertEqual(c[0].sheetPath.map(WorkbookWriter.normalized), "xl/worksheets/sheet1.xml")
    }

    func testEditKeepsStyleAndOtherSheets() throws {
        let card = try cards()[0]
        let notesBefore = try Fixture.entry(url, "xl/worksheets/sheet2.xml")
        try WorkbookWriter.setCells(url, sheetPath: card.sheetPath!, row: card.excelRow,
                                    cells: [card.questionColumn: "What is C really?", card.answerColumn: "A <systems> language & more."],
                                    backupFolder: backups)
        let after = try cards()
        XCTAssertEqual(after[0].question, "What is C really?")
        XCTAssertEqual(after[0].answer, "A <systems> language & more.")
        XCTAssertEqual(after.count, 3)
        let xml = String(decoding: try Fixture.entry(url, "xl/worksheets/sheet1.xml"), as: UTF8.self)
        XCTAssertTrue(xml.contains("r=\"B3\" s=\"1\"") || xml.contains("s=\"1\" r=\"B3\"") || xml.contains("s=\"1\""), "style kept")
        XCTAssertEqual(try Fixture.entry(url, "xl/worksheets/sheet2.xml"), notesBefore, "other sheets untouched")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: backups.path).count, 1)
    }

    func testAppendAddsRowAfterLast() throws {
        let card = try cards()[0]
        let row = try WorkbookWriter.appendRow(url, sheetPath: card.sheetPath!,
                                               cells: [1: "What is a struct?", 2: "Grouped fields."], backupFolder: nil)
        XCTAssertEqual(row, 7)
        let after = try cards()
        XCTAssertEqual(after.last?.question, "What is a struct?")
        XCTAssertEqual(after.last?.excelRow, 7)
        let xml = String(decoding: try Fixture.entry(url, "xl/worksheets/sheet1.xml"), as: UTF8.self)
        XCTAssertTrue(xml.contains("ref=\"A1:C7\""), "dimension updated")
    }

    func testReorderMovesWholeRows() throws {
        let c = try cards()
        // malloc first, then C, then pointer
        try WorkbookWriter.reorderRows(url, sheetPath: c[0].sheetPath!, order: [c[2].excelRow, c[0].excelRow, c[1].excelRow], backupFolder: nil)
        let after = try cards()
        XCTAssertEqual(after.map(\.question), ["What is malloc?", "What is C?", "What is a pointer?"])
        XCTAssertEqual(after.map { FormattedText.plain($0.answer) }, ["Heap allocation.", "A language.", "An address."])
        XCTAssertEqual(after.map(\.excelRow), [3, 4, 6])
        let sheets = try WorkbookLoader.readSheets(url: url)
        let ids = sheets[0].rows.dropFirst(2).map { $0[0] }
        XCTAssertEqual(ids, ["3", "1", "2"], "the ID column moved with its question")
    }

    func testDeleteShiftsRowsUp() throws {
        let c = try cards()
        try WorkbookWriter.deleteRow(url, sheetPath: c[1].sheetPath!, row: c[1].excelRow, backupFolder: nil)
        let after = try cards()
        XCTAssertEqual(after.map(\.question), ["What is C?", "What is malloc?"])
        XCTAssertEqual(after.map(\.excelRow), [3, 5])
    }

    func testRefusesWhileExcelHasFileOpen() throws {
        let lock = folder.appendingPathComponent("~$Prep.xlsx")
        try Data().write(to: lock)
        let card = try cards()[0]
        let before = try Data(contentsOf: url)
        XCTAssertThrowsError(try WorkbookWriter.setCells(url, sheetPath: card.sheetPath!, row: 3, cells: [1: "x"], backupFolder: nil)) {
            XCTAssertEqual($0 as? WorkbookWriterError, .locked("Prep.xlsx"))
        }
        XCTAssertEqual(try Data(contentsOf: url), before)
    }

    func testBackupIsThrottledAndPruned() throws {
        let t0 = Date(timeIntervalSince1970: 2_000_000_000)
        XCTAssertNotNil(try WorkbookWriter.backup(url, to: backups, keep: 2, minInterval: 300, now: t0))
        XCTAssertNil(try WorkbookWriter.backup(url, to: backups, keep: 2, minInterval: 300, now: t0.addingTimeInterval(10)))
        // Older backups beyond `keep` are pruned.
        for i in 1...3 {
            _ = try WorkbookWriter.backup(url, to: backups, keep: 2, minInterval: 0, now: t0.addingTimeInterval(Double(i) * 1000))
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: backups.path).count, 2)
    }

    func testDividerRowsAreSectionsNotCards() throws {
        let c = try cards()
        // Turn the blank-free row 4 ("What is a pointer?") into a divider.
        try WorkbookWriter.setCells(url, sheetPath: c[1].sheetPath!, row: c[1].excelRow,
                                    cells: [c[1].questionColumn: SectionDivider.cellText("Pointers"), c[1].answerColumn: ""],
                                    backupFolder: nil)
        let loaded = try WorkbookLoader.load(url: url).result
        XCTAssertEqual(loaded.cards.map(\.question), ["What is C?", "What is malloc?"])
        XCTAssertEqual(loaded.dividers.map(\.title), ["Pointers"])
        XCTAssertEqual(loaded.dividers.first?.excelRow, 4)
        XCTAssertEqual(loaded.sheets.first?.questionColumn, 1)
        XCTAssertEqual(loaded.sheets.first?.answerColumn, 2)
    }

    func testReorderMovesDividersWithQuestions() throws {
        let c = try cards()
        let path = c[0].sheetPath!
        try WorkbookWriter.appendRow(url, sheetPath: path, cells: [1: "## Memory"], backupFolder: nil)   // row 7
        // Put the divider first: rows [7, 3, 4, 6] into slots [3, 4, 6, 7].
        try WorkbookWriter.reorderRows(url, sheetPath: path, order: [7, 3, 4, 6], backupFolder: nil)
        let loaded = try WorkbookLoader.load(url: url).result
        XCTAssertEqual(loaded.dividers.map(\.excelRow), [3])
        XCTAssertEqual(loaded.cards.map(\.excelRow), [4, 6, 7])
    }

    func testAddSheetCreatesEmptyCategory() throws {
        let path = try WorkbookWriter.addSheet(url, name: "Linux QA", backupFolder: nil)
        XCTAssertEqual(path, "xl/worksheets/sheet3.xml")
        var loaded = try WorkbookLoader.load(url: url)
        XCTAssertEqual(loaded.result.loadedSheets, ["C QA", "Linux QA"])
        XCTAssertEqual(loaded.sheetNames, ["C QA", "Notes", "Linux QA"])
        let info = try XCTUnwrap(loaded.result.sheets.first { $0.name == "Linux QA" })
        XCTAssertEqual(info.questionColumn, 0)
        XCTAssertEqual(info.answerColumn, 1)

        // Questions can be added straight away.
        try WorkbookWriter.appendRow(url, sheetPath: info.path!, cells: [0: "What is a process?", 1: "A running program."], backupFolder: nil)
        loaded = try WorkbookLoader.load(url: url)
        let linux = loaded.result.cards.filter { $0.topic == "Linux QA" }
        XCTAssertEqual(linux.map(\.question), ["What is a process?"])
        XCTAssertEqual(linux.first?.excelRow, 2)

        let types = String(decoding: try Fixture.entry(url, "[Content_Types].xml"), as: UTF8.self)
        XCTAssertTrue(types.contains("/xl/worksheets/sheet3.xml"))
    }

    func testSheetNameRules() {
        XCTAssertThrowsError(try WorkbookWriter.validateSheetName("  ", existing: []))
        XCTAssertThrowsError(try WorkbookWriter.validateSheetName("a/b", existing: []))
        XCTAssertThrowsError(try WorkbookWriter.validateSheetName(String(repeating: "x", count: 32), existing: []))
        XCTAssertThrowsError(try WorkbookWriter.validateSheetName("c qa", existing: ["C QA"]))
        XCTAssertEqual(try WorkbookWriter.validateSheetName("  OS QA ", existing: ["C QA"]), "OS QA")
    }

    func testBoldFromSharedStringsIsKept() throws {
        let malloc = try XCTUnwrap(cards().first { $0.question == "What is malloc?" })
        XCTAssertEqual(FormattedText.runs(malloc.answer),
                       [FormattedText.Run("Heap", bold: true), FormattedText.Run(" allocation.", bold: false)])
        XCTAssertEqual(FormattedText.plain(malloc.answer), "Heap allocation.")
    }

    func testBoldRoundTripsAsRealExcelBold() throws {
        let card = try cards()[0]
        let marked = FormattedText.marked([.init("Use ", bold: false), .init("pointers", bold: true), .init(" carefully.", bold: false)])
        try WorkbookWriter.setCells(url, sheetPath: card.sheetPath!, row: card.excelRow, cells: [card.answerColumn: marked], backupFolder: nil)
        let xml = String(decoding: try Fixture.entry(url, "xl/worksheets/sheet1.xml"), as: UTF8.self)
        XCTAssertTrue(xml.contains("<rPr><b/></rPr><t xml:space=\"preserve\">pointers</t>"), xml)
        XCTAssertFalse(xml.contains("\u{E000}"), "markers never reach the file")
        XCTAssertEqual(try cards()[0].answer, marked)
    }

    func testFormattedTextHelpers() {
        let s = FormattedText.marked([.init("  a ", bold: false), .init("b", bold: true), .init("\n", bold: false)])
        XCTAssertEqual(FormattedText.plain(FormattedText.trimmed(s)), "a b")
        XCTAssertEqual(FormattedText.runs(FormattedText.trimmed(s)).last, FormattedText.Run("b", bold: true))
        XCTAssertEqual(FormattedText.trimmed("  plain \n"), "plain")
    }

    func testCellRefs() {
        XCTAssertEqual(CellRef.letters(0), "A")
        XCTAssertEqual(CellRef.letters(27), "AB")
        XCTAssertEqual(CellRef.column(of: "AB12"), 27)
    }
}

final class RenameCardTests: XCTestCase {
    func testRenameMovesHistoryAndTargets() {
        var d = ProgressData()
        d.cards["old"] = CardReview(dueDay: "2026-01-05", lastReviewed: "2026-01-01", reviews: 2, lapses: 0, topic: "T",
                                    stability: 4, difficulty: 5)
        d.cardSeconds["old"] = 90
        d.dayDone["2026-01-01"] = ["old", "x"]
        var dt = DayTargets()
        dt.slots["morning"] = SlotTarget(newKeys: ["a"], reviewKeys: ["old"], carriedKeys: ["old"])
        d.dayTargets["2026-01-05"] = dt
        d.renameCard(from: "old", to: "new")
        XCTAssertNil(d.cards["old"])
        XCTAssertEqual(d.cards["new"]?.stability, 4)
        XCTAssertEqual(d.cardSeconds["new"], 90)
        XCTAssertEqual(d.dayDone["2026-01-01"], ["new", "x"])
        XCTAssertEqual(d.dayTargets["2026-01-05"]?.slots["morning"]?.reviewKeys, ["new"])
        XCTAssertEqual(d.dayTargets["2026-01-05"]?.slots["morning"]?.carriedKeys, ["new"])
    }
}
