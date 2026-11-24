import Foundation

/// Answer text with bold runs. Inside the app, bold is marked with two private-use characters
/// (never typed by users and never shown); the workbook stores real Excel bold runs instead.
public enum FormattedText {
    public static let boldStart: Character = "\u{E000}"
    public static let boldEnd: Character = "\u{E001}"

    public struct Run: Equatable, Sendable {
        public var text: String
        public var bold: Bool

        public init(_ text: String, bold: Bool) {
            self.text = text
            self.bold = bold
        }
    }

    public static func hasFormatting(_ s: String) -> Bool {
        s.contains(boldStart) || s.contains(boldEnd)
    }

    /// The text without bold markers.
    public static func plain(_ s: String) -> String {
        hasFormatting(s) ? String(s.filter { $0 != boldStart && $0 != boldEnd }) : s
    }

    /// Splits marked text into runs (adjacent runs with the same weight are merged, empty ones dropped).
    public static func runs(_ s: String) -> [Run] {
        var out: [Run] = []
        var current = ""
        var bold = false
        func flush() {
            guard !current.isEmpty else { return }
            if let last = out.last, last.bold == bold {
                out[out.count - 1].text += current
            } else {
                out.append(Run(current, bold: bold))
            }
            current = ""
        }
        for ch in s {
            if ch == boldStart { flush(); bold = true }
            else if ch == boldEnd { flush(); bold = false }
            else { current.append(ch) }
        }
        flush()
        return out
    }

    /// Builds marked text from runs.
    public static func marked(_ runs: [Run]) -> String {
        var s = ""
        for run in runs where !run.text.isEmpty {
            s += run.bold ? "\(boldStart)\(run.text)\(boldEnd)" : run.text
        }
        return s
    }

    /// Normalises marked text (merges runs, drops empty bold runs).
    public static func normalized(_ s: String) -> String {
        hasFormatting(s) ? marked(runs(s)) : s
    }

    /// Trims whitespace at both ends while keeping bold markers balanced.
    public static func trimmed(_ s: String) -> String {
        guard hasFormatting(s) else { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
        var r = runs(s)
        while let first = r.first {
            let t = String(first.text.drop(while: { $0.isWhitespace }))
            if t.isEmpty { r.removeFirst() } else { r[0].text = t; break }
        }
        while let last = r.last {
            var t = last.text
            while let c = t.last, c.isWhitespace { t.removeLast() }
            if t.isEmpty { r.removeLast() } else { r[r.count - 1].text = t; break }
        }
        return marked(r)
    }
}
