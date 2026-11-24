import Foundation

/// One flashcard read from a QA-marked worksheet.
public struct Card: Identifiable, Hashable, Sendable {
    public let id: String
    public let topic: String
    public let question: String
    public let answer: String
    public let sourceSheet: String
    /// Position among the sheet's non-blank rows (1-based), as in the web app.
    public let sourceRow: Int
    /// Where the card lives in the workbook, for editing: real Excel row (1-based),
    /// 0-based question/answer columns, and the sheet's XML path inside the .xlsx.
    public let excelRow: Int
    public let questionColumn: Int
    public let answerColumn: Int
    public let sheetPath: String?

    public init(id: String, topic: String, question: String, answer: String, sourceSheet: String, sourceRow: Int,
                excelRow: Int? = nil, questionColumn: Int = 0, answerColumn: Int = 1, sheetPath: String? = nil) {
        self.id = id
        self.topic = topic
        self.question = question
        self.answer = answer
        self.sourceSheet = sourceSheet
        self.sourceRow = sourceRow
        self.excelRow = excelRow ?? sourceRow
        self.questionColumn = questionColumn
        self.answerColumn = answerColumn
        self.sheetPath = sheetPath
    }
}

/// A worksheet as plain text. `a1` is the raw A1 cell; `rows` has blank rows removed
/// (same as SheetJS `sheet_to_json(header: 1, blankrows: false)`).
public struct SheetData: Sendable {
    public let name: String
    public let a1: String
    public let rows: [[String]]
    /// Real Excel row number (1-based) for each entry in `rows`.
    public let rowNumbers: [Int]
    /// The worksheet's XML path inside the .xlsx (for writing).
    public let path: String?

    public init(name: String, a1: String, rows: [[String]], rowNumbers: [Int]? = nil, path: String? = nil) {
        self.name = name
        self.a1 = a1
        self.rows = rows
        self.rowNumbers = rowNumbers ?? (0..<rows.count).map { $0 + 1 }
        self.path = path
    }
}

/// A section divider inside a category's question list. Stored in the workbook as a row whose
/// question cell starts with "## " (for example "## Arrays").
public struct SectionDivider: Identifiable, Hashable, Sendable {
    public static let prefix = "## "

    public let sheet: String
    public let title: String
    public let excelRow: Int
    public var id: String { "divider-\(sheet)-\(excelRow)" }

    public init(sheet: String, title: String, excelRow: Int) {
        self.sheet = sheet
        self.title = title
        self.excelRow = excelRow
    }

    /// The divider title if this cell text is a divider, else nil.
    public static func title(of text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix("##") else { return nil }
        return String(t.dropFirst(2)).trimmingCharacters(in: .whitespaces)
    }

    public static func cellText(_ title: String) -> String { prefix + title.trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// Where a QA sheet's questions live, so new rows can be added even when it has no cards yet.
public struct SheetInfo: Hashable, Sendable {
    public let name: String
    public let path: String?
    public let questionColumn: Int
    public let answerColumn: Int

    public init(name: String, path: String?, questionColumn: Int = 0, answerColumn: Int = 1) {
        self.name = name
        self.path = path
        self.questionColumn = questionColumn
        self.answerColumn = answerColumn
    }
}

public struct ParseResult: Sendable {
    public var cards: [Card]
    public var loadedSheets: [String]
    public var duplicatesSkipped: Int
    public var dividers: [SectionDivider] = []
    public var sheets: [SheetInfo] = []
}

/// Swift port of `src/excelImport.js`.
public enum WorkbookParser {
    static let questionHeaders: Set<String> = [
        "question", "questions", "questiontext", "interviewquestion", "prompt", "problem", "problemstatement",
    ]
    static let answerHeaders: Set<String> = [
        "answer", "answers", "answertext", "suggestedanswer", "solution", "explanation", "response",
    ]

    private static let markerRegex = try! NSRegularExpression(
        pattern: #"\bq\s*(?:&|/)?\s*a\b"#, options: [.caseInsensitive])

    public static func hasQAMarker(_ value: String) -> Bool {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return markerRegex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    static func isAlnum(_ c: Character) -> Bool {
        c.isASCII && (c.isLetter || c.isNumber)
    }

    static func normalizeHeader(_ value: String) -> String {
        String(value.lowercased().decomposedStringWithCompatibilityMapping.filter(isAlnum))
    }

    static func normalizeSheetName(_ value: String) -> String {
        let spaced = value.decomposedStringWithCompatibilityMapping
            .replacingOccurrences(of: "[\u{00a0}\u{2007}\u{202f}]", with: " ", options: .regularExpression)
            .lowercased()
        var out = ""
        var pendingSpace = false
        for c in spaced {
            if isAlnum(c) {
                if pendingSpace && !out.isEmpty { out.append(" ") }
                pendingSpace = false
                out.append(c)
            } else {
                pendingSpace = true
            }
        }
        return out
    }

    private static func trimmed(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func parse(_ sheets: [SheetData]) -> ParseResult {
        var seen = Set<String>()
        var cards: [Card] = []
        var loaded: [String] = []
        var duplicates = 0
        var dividers: [SectionDivider] = []
        var infos: [SheetInfo] = []

        for sheet in sheets where hasQAMarker(sheet.a1) {
            let rows = sheet.rows
            loaded.append(sheet.name)

            // A1 is the QA marker. Look for optional column labels starting on row 2.
            var headerIndex = -1
            var questionColumn = 0
            var answerColumn = 1
            if rows.count > 1 {
                for i in 1..<min(rows.count, 16) {
                    let headers = rows[i].map { normalizeHeader(FormattedText.plain($0)) }
                    if let q = headers.firstIndex(where: questionHeaders.contains),
                       let a = headers.firstIndex(where: answerHeaders.contains) {
                        headerIndex = i
                        questionColumn = q
                        answerColumn = a
                        break
                    }
                }
            }

            let topic = trimmed(sheet.name)
            infos.append(SheetInfo(name: topic, path: sheet.path, questionColumn: questionColumn, answerColumn: answerColumn))
            let firstDataRow = headerIndex >= 0 ? headerIndex + 1 : 1
            guard firstDataRow < rows.count else { continue }

            for (offset, row) in rows[firstDataRow...].enumerated() {
                func cell(_ i: Int) -> String { i < row.count ? row[i] : "" }
                let question = trimmed(FormattedText.plain(cell(questionColumn)))
                var answer = FormattedText.trimmed(cell(answerColumn))
                var resolvedAnswerColumn = answerColumn
                if FormattedText.plain(answer).isEmpty && headerIndex < 0 && answerColumn + 1 < row.count {
                    if let next = row.indices.dropFirst(answerColumn + 1).first(where: { !trimmed(FormattedText.plain(row[$0])).isEmpty }) {
                        answer = FormattedText.trimmed(row[next])
                        resolvedAnswerColumn = next
                    }
                }
                if question.isEmpty || question.lowercased() == "question" { continue }
                let excelRow = firstDataRow + offset < sheet.rowNumbers.count ? sheet.rowNumbers[firstDataRow + offset] : firstDataRow + offset + 1
                if let title = SectionDivider.title(of: question) {
                    dividers.append(SectionDivider(sheet: topic, title: title, excelRow: excelRow))
                    continue
                }

                let key = question.lowercased()
                if seen.contains(key) {
                    duplicates += 1
                    continue
                }
                let rowNumber = firstDataRow + offset + 1
                cards.append(Card(
                    id: "\(normalizeSheetName(sheet.name))-\(rowNumber)",
                    topic: topic,
                    question: question,
                    answer: answer,
                    sourceSheet: sheet.name,
                    sourceRow: rowNumber,
                    excelRow: excelRow,
                    questionColumn: questionColumn,
                    answerColumn: resolvedAnswerColumn,
                    sheetPath: sheet.path))
                seen.insert(key)
            }
        }
        return ParseResult(cards: cards, loadedSheets: loaded, duplicatesSkipped: duplicates,
                           dividers: dividers, sheets: infos)
    }
}
