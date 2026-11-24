import Foundation
import ZIPFoundation

/// Reads bold text runs that CoreXLSX doesn't expose. Returns, per worksheet path, the cells
/// (real row number → 0-based column) whose text contains bold, as `FormattedText` marked text.
enum RichCells {
    static func read(_ url: URL) -> [String: [Int: [Int: String]]] {
        guard let archive = try? Archive(url: url, accessMode: .read) else { return [:] }
        func data(_ path: String) -> Data? {
            guard let entry = archive[path] else { return nil }
            var d = Data()
            _ = try? archive.extract(entry, skipCRC32: true) { d.append($0) }
            return d
        }

        // Shared strings: only items with at least one bold run get marked text.
        var shared: [String?] = []
        if let sst = data("xl/sharedStrings.xml"),
           let doc = try? XMLDocument(data: sst, options: [.nodePreserveWhitespace]),
           let root = doc.rootElement() {
            shared = root.children(named: "si").map(markedText)
        }

        var out: [String: [Int: [Int: String]]] = [:]
        for entry in archive where entry.path.hasPrefix("xl/worksheets/") && entry.path.hasSuffix(".xml") {
            guard let xml = data(entry.path),
                  let doc = try? XMLDocument(data: xml, options: [.nodePreserveWhitespace]),
                  let sheetData = doc.rootElement()?.child(named: "sheetData") else { continue }
            var cells: [Int: [Int: String]] = [:]
            for row in sheetData.children(named: "row") {
                guard let r = row.rowNumber else { continue }
                for c in row.children(named: "c") {
                    let col = CellRef.column(of: c.attr("r") ?? "")
                    guard col >= 0 else { continue }
                    var marked: String?
                    switch c.attr("t") {
                    case "s":
                        if let v = c.child(named: "v")?.stringValue, let i = Int(v), i < shared.count { marked = shared[i] }
                    case "inlineStr":
                        if let isEl = c.child(named: "is") { marked = markedText(isEl) }
                    default:
                        break
                    }
                    if let marked { cells[r, default: [:]][col] = marked }
                }
            }
            if !cells.isEmpty { out[entry.path] = cells }
        }
        return out
    }

    /// Marked text for an <si> or <is> element if it has any bold run, else nil.
    static func markedText(_ element: XMLElement) -> String? {
        let runs = element.children(named: "r")
        guard !runs.isEmpty else { return nil }
        var parts: [FormattedText.Run] = []
        var anyBold = false
        for r in runs {
            let text = r.children(named: "t").map { $0.stringValue ?? "" }.joined()
            let bold = r.child(named: "rPr")?.child(named: "b").map { b in
                let v = b.attr("val")?.lowercased()
                return v == nil || v == "1" || v == "true"
            } ?? false
            anyBold = anyBold || (bold && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            parts.append(FormattedText.Run(text, bold: bold))
        }
        return anyBold ? FormattedText.marked(parts) : nil
    }
}
