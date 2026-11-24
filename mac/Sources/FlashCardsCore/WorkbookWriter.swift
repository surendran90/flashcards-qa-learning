import Foundation
import ZIPFoundation

public enum WorkbookWriterError: LocalizedError, Equatable {
    case locked(String)
    case unsupportedFormat
    case sheetNotFound(String)
    case invalidResult
    case invalidName(String)
    case io(String)

    public var errorDescription: String? {
        switch self {
        case .locked(let name): return "\(name) is open in Excel. Close it there to save your changes (the app will retry)."
        case .unsupportedFormat: return "Only .xlsx workbooks can be edited. Save the file as .xlsx in Excel first."
        case .sheetNotFound(let path): return "Couldn't find the worksheet (\(path)) in the workbook."
        case .invalidResult: return "The change couldn't be saved safely, so the workbook was left as it was."
        case .invalidName(let message): return message
        case .io(let message): return "Couldn't save the workbook: \(message)"
        }
    }
}

/// Edits question/answer rows in an .xlsx in place. Only the target sheet's XML is changed;
/// every other part of the file is copied unchanged. Writes are atomic, a backup is kept,
/// and nothing is written while Excel has the file open.
public enum WorkbookWriter {
    static let mainNS = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"

    // MARK: Safety

    /// Excel's lock file ("~$Name.xlsx") means the workbook is open and being edited there.
    public static func isLocked(_ url: URL) -> Bool {
        let folder = url.deletingLastPathComponent()
        let name = url.lastPathComponent
        let candidates = ["~$" + name, "~$" + String(name.dropFirst(2))]
        return candidates.contains { FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path) }
    }

    /// Copies the workbook into `folder` (at most once per `minInterval`), keeping the newest `keep` copies.
    @discardableResult
    public static func backup(_ url: URL, to folder: URL, keep: Int = 30, minInterval: TimeInterval = 300,
                              now: Date = Date()) throws -> URL? {
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let base = url.deletingPathExtension().lastPathComponent
        let existing = ((try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
            .filter { $0.lastPathComponent.hasPrefix(base + " ") && $0.pathExtension == "xlsx" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        if let last = existing.last,
           let date = try? last.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
           now.timeIntervalSince(date) < minInterval {
            return nil
        }
        let stamp = ISO8601DateFormatter.string(from: now, timeZone: .current, formatOptions: [.withFullDate, .withTime, .withColonSeparatorInTime])
            .replacingOccurrences(of: ":", with: "-")
        let dest = folder.appendingPathComponent("\(base) \(stamp).xlsx")
        try? fm.removeItem(at: dest)
        try fm.copyItem(at: url, to: dest)
        // The copy keeps the workbook's own date; stamp it with the backup time for throttling.
        try? fm.setAttributes([.modificationDate: now], ofItemAtPath: dest.path)
        let all = existing + [dest]
        for old in all.dropLast(keep) { try? fm.removeItem(at: old) }
        return dest
    }

    // MARK: Public operations (rows are real Excel row numbers, columns 0-based)

    /// Sets cell texts in one row (creating the row or cells if needed).
    public static func setCells(_ url: URL, sheetPath: String, row: Int, cells: [Int: String], backupFolder: URL?) throws {
        try modifySheet(url, sheetPath: sheetPath, backupFolder: backupFolder) { sheet in
            for (col, text) in cells.sorted(by: { $0.key < $1.key }) { sheet.setCell(row: row, col: col, text: text) }
        }
    }

    /// Adds a row after the sheet's last row; returns its row number.
    @discardableResult
    public static func appendRow(_ url: URL, sheetPath: String, cells: [Int: String], backupFolder: URL?) throws -> Int {
        var newRow = 0
        try modifySheet(url, sheetPath: sheetPath, backupFolder: backupFolder) { sheet in
            newRow = sheet.lastRow + 1
            for (col, text) in cells.sorted(by: { $0.key < $1.key }) { sheet.setCell(row: newRow, col: col, text: text) }
        }
        return newRow
    }

    /// Reorders rows: the content of `order[i]` moves to the i-th smallest of those row numbers.
    public static func reorderRows(_ url: URL, sheetPath: String, order: [Int], backupFolder: URL?) throws {
        guard order.count > 1 else { return }
        try modifySheet(url, sheetPath: sheetPath, backupFolder: backupFolder) { sheet in
            sheet.reorder(order)
        }
    }

    /// Deletes a row and moves the rows below it up by one.
    public static func deleteRow(_ url: URL, sheetPath: String, row: Int, backupFolder: URL?) throws {
        try modifySheet(url, sheetPath: sheetPath, backupFolder: backupFolder) { sheet in
            sheet.deleteRow(row)
        }
    }

    // MARK: Core

    static func normalized(_ path: String) -> String {
        path.hasPrefix("/") ? String(path.dropFirst()) : path
    }

    static func modifySheet(_ url: URL, sheetPath: String, backupFolder: URL?, _ change: (SheetXML) throws -> Void) throws {
        let target = normalized(sheetPath)
        try rewriteArchive(url, backupFolder: backupFolder) { read in
            guard let xml = try read(target) else { throw WorkbookWriterError.sheetNotFound(target) }
            let sheet = try SheetXML(data: xml)
            try change(sheet)
            sheet.updateDimension()
            return [target: sheet.data()]
        }
    }

    /// Rewrites the .xlsx with some parts replaced or added. `build` gets a reader for existing
    /// parts (nil if missing) and returns the new contents by path. Everything else is copied as is.
    /// The result must load as a workbook before it replaces the original (with a backup first).
    static func rewriteArchive(_ url: URL, backupFolder: URL?,
                               _ build: (_ read: (String) throws -> Data?) throws -> [String: Data]) throws {
        guard url.pathExtension.lowercased() == "xlsx" else { throw WorkbookWriterError.unsupportedFormat }
        if isLocked(url) { throw WorkbookWriterError.locked(url.lastPathComponent) }
        let fm = FileManager.default

        do {
            let source = try Archive(url: url, accessMode: .read)
            func read(_ path: String) throws -> Data? {
                guard let entry = source[normalized(path)] else { return nil }
                var data = Data()
                _ = try source.extract(entry, skipCRC32: false) { data.append($0) }
                return data
            }
            var changes = try build(read)

            let tmp = fm.temporaryDirectory.appendingPathComponent("flashcards-\(UUID().uuidString).xlsx")
            defer { try? fm.removeItem(at: tmp) }
            let out = try Archive(url: tmp, accessMode: .create)
            func add(_ path: String, _ bytes: Data) throws {
                try out.addEntry(with: path, type: .file, uncompressedSize: Int64(bytes.count),
                                 compressionMethod: .deflate) { position, size in
                    bytes.subdata(in: Int(position)..<Int(position) + size)
                }
            }
            for e in source {
                guard e.type == .file else { continue }
                if let replacement = changes.removeValue(forKey: e.path) {
                    try add(e.path, replacement)
                } else {
                    var data = Data()
                    _ = try source.extract(e, skipCRC32: false) { data.append($0) }
                    try add(e.path, data)
                }
            }
            for (path, data) in changes.sorted(by: { $0.key < $1.key }) { try add(path, data) }

            // Sanity check: the new file must still read as a workbook.
            _ = try WorkbookLoader.load(url: tmp)

            if let backupFolder { try backup(url, to: backupFolder) }
            if isLocked(url) { throw WorkbookWriterError.locked(url.lastPathComponent) }
            _ = try fm.replaceItemAt(url, withItemAt: tmp)
        } catch let error as WorkbookWriterError {
            throw error
        } catch is WorkbookLoaderError {
            throw WorkbookWriterError.invalidResult
        } catch {
            throw WorkbookWriterError.io(error.localizedDescription)
        }
    }

    // MARK: New category (worksheet)

    static let relsNS = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
    static let worksheetType = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet"
    static let worksheetContentType = "application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"

    /// Excel's rules for tab names: 1–31 characters, none of [ ] : * ? / \\, not starting or ending with '.
    public static func validateSheetName(_ raw: String, existing: [String]) throws -> String {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw WorkbookWriterError.invalidName("Enter a category name.") }
        guard name.count <= 31 else { throw WorkbookWriterError.invalidName("Category names can be at most 31 characters (Excel's limit).") }
        if let bad = name.first(where: { "[]:*?/\\".contains($0) }) {
            throw WorkbookWriterError.invalidName("Category names can't contain “\(bad)”.")
        }
        guard !name.hasPrefix("'"), !name.hasSuffix("'") else {
            throw WorkbookWriterError.invalidName("Category names can't start or end with an apostrophe.")
        }
        guard !existing.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else {
            throw WorkbookWriterError.invalidName("There's already a tab called “\(name)”.")
        }
        return name
    }

    /// Adds a new worksheet (tab) with "QA" in A1 so the app picks it up as a category.
    /// Returns the new sheet's path inside the .xlsx.
    @discardableResult
    public static func addSheet(_ url: URL, name raw: String, backupFolder: URL?) throws -> String {
        var newPath = ""
        try rewriteArchive(url, backupFolder: backupFolder) { read in
            guard let wbData = try read("xl/workbook.xml"),
                  let relsData = try read("xl/_rels/workbook.xml.rels"),
                  let typesData = try read("[Content_Types].xml") else { throw WorkbookWriterError.invalidResult }
            let wb = try XMLDocument(data: wbData, options: [.nodePreserveWhitespace])
            let rels = try XMLDocument(data: relsData, options: [.nodePreserveWhitespace])
            let types = try XMLDocument(data: typesData, options: [.nodePreserveWhitespace])
            guard let sheets = wb.rootElement()?.child(named: "sheets"),
                  let relsRoot = rels.rootElement(), let typesRoot = types.rootElement() else {
                throw WorkbookWriterError.invalidResult
            }

            let existingNames = sheets.children(named: "sheet").compactMap { $0.attr("name") }
            let name = try validateSheetName(raw, existing: existingNames)

            let sheetId = (sheets.children(named: "sheet").compactMap { $0.attr("sheetId").flatMap(Int.init) }.max() ?? 0) + 1
            let relIds = Set(relsRoot.children(named: "Relationship").compactMap { $0.attr("Id") })
            var n = relIds.count + 1
            while relIds.contains("rId\(n)") { n += 1 }
            let relId = "rId\(n)"
            var k = 1
            while try read("xl/worksheets/sheet\(k).xml") != nil { k += 1 }
            newPath = "xl/worksheets/sheet\(k).xml"

            let sheet = XMLElement(name: "sheet")
            sheet.setAttr("name", name)
            sheet.setAttr("sheetId", "\(sheetId)")
            sheet.addAttribute(XMLNode.attribute(withName: "r:id", uri: relsNS, stringValue: relId) as! XMLNode)
            sheets.addChild(sheet)

            let rel = XMLElement(name: "Relationship")
            rel.setAttr("Id", relId)
            rel.setAttr("Type", worksheetType)
            rel.setAttr("Target", "worksheets/sheet\(k).xml")
            relsRoot.addChild(rel)

            let override = XMLElement(name: "Override")
            override.setAttr("PartName", "/\(newPath)")
            override.setAttr("ContentType", worksheetContentType)
            typesRoot.addChild(override)

            let sheetXML = """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <worksheet xmlns="\(mainNS)" xmlns:r="\(relsNS)"><dimension ref="A1"/><sheetData>\
            <row r="1"><c r="A1" t="inlineStr"><is><t>QA</t></is></c></row></sheetData></worksheet>
            """
            return [
                "xl/workbook.xml": wb.xmlData(options: [.nodeCompactEmptyElement]),
                "xl/_rels/workbook.xml.rels": rels.xmlData(options: [.nodeCompactEmptyElement]),
                "[Content_Types].xml": types.xmlData(options: [.nodeCompactEmptyElement]),
                newPath: Data(sheetXML.utf8),
            ]
        }
        return newPath
    }
}

// MARK: - Sheet XML editing

/// A worksheet's XML with helpers for rows and cells, keeping everything else as it was.
final class SheetXML {
    let doc: XMLDocument
    let sheetData: XMLElement

    init(data: Data) throws {
        doc = try XMLDocument(data: data, options: [.nodePreserveWhitespace])
        guard let root = doc.rootElement(), let sd = root.child(named: "sheetData") else {
            throw WorkbookWriterError.invalidResult
        }
        sheetData = sd
    }

    func data() -> Data { doc.xmlData(options: [.nodeCompactEmptyElement]) }

    var rows: [XMLElement] { sheetData.children(named: "row") }

    var lastRow: Int { rows.compactMap(\.rowNumber).max() ?? 0 }

    func row(_ number: Int) -> XMLElement? { rows.first { $0.rowNumber == number } }

    /// Finds or creates a row, keeping rows sorted.
    func ensureRow(_ number: Int) -> XMLElement {
        if let r = row(number) { return r }
        let r = XMLElement(name: "row")
        r.setAttr("r", "\(number)")
        let index = rows.firstIndex { ($0.rowNumber ?? 0) > number }
        if let index, let before = rows[safe: index], let i = sheetData.children?.firstIndex(where: { $0 === before }) {
            sheetData.insertChild(r, at: i)
        } else {
            sheetData.addChild(r)
        }
        return r
    }

    func setCell(row number: Int, col: Int, text: String) {
        let r = ensureRow(number)
        let ref = CellRef.name(col: col, row: number)
        let cells = r.children(named: "c")
        let cell: XMLElement
        if let existing = cells.first(where: { $0.attr("r") == ref }) {
            cell = existing
            cell.setChildren(nil)
        } else {
            cell = XMLElement(name: "c")
            cell.setAttr("r", ref)
            if let after = cells.firstIndex(where: { CellRef.column(of: $0.attr("r") ?? "") > col }),
               let i = r.children?.firstIndex(where: { $0 === cells[after] }) {
                r.insertChild(cell, at: i)
            } else {
                r.addChild(cell)
            }
        }
        cell.removeAttribute(forName: "t")
        cell.setAttr("t", "inlineStr")
        let isEl = XMLElement(name: "is")
        let t = XMLElement(name: "t", stringValue: text)
        t.setAttr("xml:space", "preserve")
        isEl.addChild(t)
        cell.addChild(isEl)
        // A row's "spans" hint may no longer cover new cells; Excel recomputes it.
        r.removeAttribute(forName: "spans")
    }

    /// Moves row contents: `order[i]`'s cells go to the i-th smallest row number in `order`.
    func reorder(_ order: [Int]) {
        let slots = order.sorted()
        var moved: [XMLElement] = []
        for (i, source) in order.enumerated() {
            let original = row(source)
            let copy = (original?.copy() as? XMLElement) ?? XMLElement(name: "row")
            Self.renumber(copy, to: slots[i])
            moved.append(copy)
        }
        for number in Set(order) { row(number)?.detach() }
        for r in moved { insertSorted(r) }
    }

    func deleteRow(_ number: Int) {
        row(number)?.detach()
        for r in rows where (r.rowNumber ?? 0) > number {
            Self.renumber(r, to: (r.rowNumber ?? 0) - 1)
        }
    }

    private func insertSorted(_ r: XMLElement) {
        let n = r.rowNumber ?? 0
        if let next = rows.first(where: { ($0.rowNumber ?? 0) > n }),
           let i = sheetData.children?.firstIndex(where: { $0 === next }) {
            sheetData.insertChild(r, at: i)
        } else {
            sheetData.addChild(r)
        }
    }

    static func renumber(_ r: XMLElement, to number: Int) {
        r.setAttr("r", "\(number)")
        for c in r.children(named: "c") {
            let col = CellRef.column(of: c.attr("r") ?? "")
            c.setAttr("r", CellRef.name(col: max(0, col), row: number))
        }
    }

    /// Keeps the <dimension ref="A1:D40"> hint in line with the data.
    func updateDimension() {
        guard let root = doc.rootElement(), let dim = root.child(named: "dimension") else { return }
        let maxRow = max(1, lastRow)
        let maxCol = rows.flatMap { $0.children(named: "c") }.map { CellRef.column(of: $0.attr("r") ?? "") }.max() ?? 0
        dim.setAttr("ref", "A1:\(CellRef.name(col: max(0, maxCol), row: maxRow))")
    }
}

enum CellRef {
    static func letters(_ col: Int) -> String {
        var n = col + 1
        var s = ""
        while n > 0 {
            let r = (n - 1) % 26
            s = String(UnicodeScalar(65 + r)!) + s
            n = (n - 1) / 26
        }
        return s
    }

    static func name(col: Int, row: Int) -> String { letters(col) + "\(row)" }

    /// 0-based column of a reference like "AB12" (-1 if none).
    static func column(of ref: String) -> Int {
        let letters = ref.prefix { $0.isLetter }.uppercased()
        guard !letters.isEmpty else { return -1 }
        return letters.unicodeScalars.reduce(0) { $0 * 26 + Int($1.value) - 64 } - 1
    }
}

private extension XMLElement {
    func child(named name: String) -> XMLElement? { children(named: name).first }

    func children(named name: String) -> [XMLElement] {
        (children ?? []).compactMap { $0 as? XMLElement }.filter { ($0.localName ?? $0.name) == name }
    }

    func attr(_ name: String) -> String? { attribute(forName: name)?.stringValue }

    func setAttr(_ name: String, _ value: String) {
        if let a = attribute(forName: name) {
            a.stringValue = value
        } else {
            addAttribute(XMLNode.attribute(withName: name, stringValue: value) as! XMLNode)
        }
    }

    var rowNumber: Int? { attr("r").flatMap(Int.init) }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
