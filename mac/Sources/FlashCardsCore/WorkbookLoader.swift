import CoreXLSX
import Foundation

public struct LoadedWorkbook: Sendable {
    public let result: ParseResult
    public let fileName: String
    public let sheetNames: [String]
    /// The file the cards were read from (edits are written back here).
    public let url: URL
}

public enum WorkbookLoaderError: LocalizedError {
    case notFound(String)
    case unreadable(String)
    case unsupportedFormat

    public var errorDescription: String? {
        switch self {
        case .notFound(let dir): return "Could not find InterviewPrepare.xlsx in \(dir)."
        case .unreadable(let name): return "Could not read \(name). Try saving it as .xlsx and check its file format."
        case .unsupportedFormat: return "Only .xlsx workbooks are supported. Open the file in Excel and save it as .xlsx."
        }
    }
}

/// Reads workbooks from disk. Read-only: never writes to any workbook.
public enum WorkbookLoader {
    public static let defaultFolder: String = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/CloudStorage/OneDrive-Personal/Interview/Interview Preparation").path

    static func normalizeFileName(_ name: String) -> String {
        String(name.lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) })
    }

    /// Finds `InterviewPrepare.xlsx` (or `Interview Prepare.xlsx`, etc.) in the folder.
    public static func findWorkbook(in folder: String) throws -> URL {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
        let expected = normalizeFileName("InterviewPrepare.xlsx")
        guard let match = files.first(where: { normalizeFileName($0) == expected }) else {
            throw WorkbookLoaderError.notFound(folder)
        }
        return URL(fileURLWithPath: folder).appendingPathComponent(match)
    }

    public static func loadDefault(folder: String) throws -> LoadedWorkbook {
        try load(url: findWorkbook(in: folder))
    }

    public static func load(url: URL) throws -> LoadedWorkbook {
        guard url.pathExtension.lowercased() == "xlsx" else { throw WorkbookLoaderError.unsupportedFormat }
        let sheets = try readSheets(url: url)
        return LoadedWorkbook(
            result: WorkbookParser.parse(sheets),
            fileName: url.lastPathComponent,
            sheetNames: sheets.map(\.name),
            url: url)
    }

    static func readSheets(url: URL) throws -> [SheetData] {
        guard let file = XLSXFile(filepath: url.path) else {
            throw WorkbookLoaderError.unreadable(url.lastPathComponent)
        }
        do {
            let shared = try file.parseSharedStrings()
            var sheets: [SheetData] = []
            for workbook in try file.parseWorkbooks() {
                // Keep the tab order from the workbook (CoreXLSX may return paths in another order).
                let order = workbook.sheets.items.compactMap(\.name)
                let pairs = try file.parseWorksheetPathsAndNames(workbook: workbook).sorted {
                    (order.firstIndex(of: $0.name ?? "") ?? .max) < (order.firstIndex(of: $1.name ?? "") ?? .max)
                }
                for (name, path) in pairs {
                    let worksheet = try file.parseWorksheet(at: path)
                    sheets.append(sheetData(name: name ?? path, path: path, worksheet: worksheet, shared: shared))
                }
            }
            return sheets
        } catch {
            throw WorkbookLoaderError.unreadable(url.lastPathComponent)
        }
    }

    static func columnIndex(_ letters: String) -> Int {
        letters.uppercased().unicodeScalars.reduce(0) { $0 * 26 + Int($1.value) - 64 } - 1
    }

    static func text(of cell: Cell, shared: SharedStrings?) -> String {
        switch cell.type {
        case .sharedString:
            guard let shared, let raw = cell.value, let i = Int(raw), i < shared.items.count else { return "" }
            let item = shared.items[i]
            if let text = item.text { return text }
            return item.richText.compactMap(\.text).joined()
        case .inlineStr:
            return cell.inlineString?.text ?? ""
        case .bool:
            return cell.value == "1" ? "TRUE" : "FALSE"
        default:
            return cell.value ?? ""
        }
    }

    static func sheetData(name: String, path: String? = nil, worksheet: Worksheet, shared: SharedStrings?) -> SheetData {
        var a1 = ""
        var rows: [[String]] = []
        var rowNumbers: [Int] = []
        let xmlRows = (worksheet.data?.rows ?? []).sorted { $0.reference < $1.reference }
        for row in xmlRows {
            var values: [String] = []
            for cell in row.cells {
                let col = columnIndex(cell.reference.column.value)
                guard col >= 0 else { continue }
                let value = text(of: cell, shared: shared)
                if col == 0 && cell.reference.row == 1 { a1 = value }
                if values.count <= col { values.append(contentsOf: repeatElement("", count: col - values.count + 1)) }
                values[col] = value
            }
            if values.contains(where: { !$0.isEmpty }) {
                rows.append(values)
                rowNumbers.append(Int(row.reference))
            }
        }
        return SheetData(name: name, a1: a1, rows: rows, rowNumbers: rowNumbers, path: path)
    }
}
