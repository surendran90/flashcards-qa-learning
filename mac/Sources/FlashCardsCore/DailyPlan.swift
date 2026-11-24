import Foundation

/// Minutes per card. Starts from the card time box (reviews take a fifth of it) and switches to
/// your real average once a category has enough timed cards.
public struct CostModel: Sendable {
    public var overrides: [String: Int]
    public var timing: [String: TimingStats]
    public static let minSamples = 10

    public init(overrides: [String: Int] = [:], timing: [String: TimingStats] = [:]) {
        self.overrides = overrides
        self.timing = timing
    }

    public init(_ data: ProgressData) {
        self.init(overrides: data.categoryMinutes, timing: data.timing)
    }

    public func newMinutes(_ topic: String) -> Double {
        if let t = timing[topic], t.newCount >= Self.minSamples {
            return max(0.5, t.newSeconds / Double(t.newCount) / 60)
        }
        return Double(CardTiming.minutes(for: topic, overrides: overrides))
    }

    public func reviewMinutes(_ topic: String) -> Double {
        if let t = timing[topic], t.reviewCount >= Self.minSamples {
            return max(0.25, t.reviewSeconds / Double(t.reviewCount) / 60)
        }
        return max(1, (Double(CardTiming.minutes(for: topic, overrides: overrides)) / 5).rounded())
    }
}

/// FSRS revision load: what's due today and in the coming days.
public enum RevisionOutlook {
    public struct Day: Equatable, Sendable {
        public var day: String
        public var count: Int
        public var minutes: Double
    }

    /// Cards due on or before `day` (overdue cards count as due today).
    public static func dueKeys(_ data: ProgressData, keys: [String], on day: String) -> [String] {
        keys.filter { k in data.cards[k].map { $0.dueDay <= day } ?? false }
    }

    /// Revised today: practised today and not first introduced today.
    public static func revisedToday(_ data: ProgressData, keys: [String], today: String) -> Int {
        keys.filter { k in
            guard let r = data.cards[k] else { return false }
            return r.lastReviewed == today && r.introducedDay != today
        }.count
    }

    /// Due counts for `days` days starting today, from the current schedule (no simulation).
    public static func days(_ data: ProgressData, cards: [(key: String, topic: String)], today: String,
                            days: Int = 7, clock: DayClock = DayClock()) -> [Day] {
        let cost = CostModel(data)
        return (0..<max(1, days)).map { offset in
            let day = clock.add(offset, to: today)
            let due = cards.filter { c in
                guard let r = data.cards[c.key] else { return false }
                return offset == 0 ? r.dueDay <= day : r.dueDay == day
            }
            return Day(day: day, count: due.count, minutes: due.reduce(0) { $0 + cost.reviewMinutes($1.topic) })
        }
    }
}

/// Turns a written plan like
///
///     [Nov 25 ]
///     Revise as per algo
///     Daily two modules
///     Resume QA [Add + All]
///
/// into tasks per day. Lines about FSRS revision are skipped (the app shows revision itself),
/// bullets are stripped, and a task that names a category is linked to it.
public enum PlanText {
    public struct Parsed: Equatable, Sendable {
        public var tasksByDay: [String: [PlanTask]]
        public var skippedRevisionLines: Int
        public var unassignedLines: Int
    }

    static let months: [String: Int] = [
        "jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6, "jul": 7, "aug": 8,
        "sep": 9, "sept": 9, "oct": 10, "nov": 11, "dec": 12,
    ]

    /// "yyyy-MM-dd" for a header line such as "[Nov 25 ]", "Nov 25", "25 Nov", "[2026-11-25]"; else nil.
    /// Without a year, the date is placed within the year around `today`.
    public static func headerDay(_ raw: String, today: String, clock: DayClock = DayClock()) -> String? {
        var line = raw.trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("[") && line.hasSuffix("]") { line = String(line.dropFirst().dropLast()) }
        line = line.trimmingCharacters(in: CharacterSet(charactersIn: " :-")).lowercased()
        guard !line.isEmpty, line.count <= 24 else { return nil }

        if let d = clock.date(line), clock.key(d) == line { return line }

        let parts = line.replacingOccurrences(of: ",", with: " ").split(separator: " ").map(String.init)
        var month: Int?, day: Int?, year: Int?
        for p in parts {
            if let m = months[String(p.prefix(4))] ?? months[String(p.prefix(3))], p.first?.isLetter == true {
                month = m
            } else if let n = Int(p) ?? ordinal(p) {
                if n > 31 { year = n } else if day == nil { day = n }
            } else {
                return nil
            }
        }
        guard let month, let day, (1...31).contains(day) else { return nil }
        let todayYear = Int(today.prefix(4)) ?? 2000
        func key(_ y: Int) -> String { String(format: "%04d-%02d-%02d", y, month, day) }
        if let year { return key(year) }
        // Pick the year that puts the date closest to today (handles Dec → Jan).
        let candidates = [todayYear - 1, todayYear, todayYear + 1].map(key)
        return candidates.min { abs(clock.days(from: today, to: $0)) < abs(clock.days(from: today, to: $1)) }
    }

    /// "25th" → 25.
    static func ordinal(_ p: String) -> Int? {
        guard ["th", "st", "nd", "rd"].contains(where: { p.hasSuffix($0) }) else { return nil }
        return Int(p.dropLast(2))
    }

    static func isRevisionLine(_ s: String) -> Bool {
        let l = s.lowercased()
        return (l.hasPrefix("revise") || l.hasPrefix("revision")) && (l.contains("algo") || l.contains("fsrs") || l.contains("due"))
    }

    static func stripBullet(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespaces)
        for prefix in ["- ", "• ", "* ", "– ", "[ ] ", "[x] "] where t.lowercased().hasPrefix(prefix) {
            t = String(t.dropFirst(prefix.count))
        }
        let digits = t.prefix { $0.isNumber }
        if !digits.isEmpty, t.dropFirst(digits.count).hasPrefix(". ") || t.dropFirst(digits.count).hasPrefix(") ") {
            t = String(t.dropFirst(digits.count + 2))
        }
        return t.trimmingCharacters(in: .whitespaces)
    }

    /// The category a task names (longest match wins, case-insensitive), if any.
    public static func link(for text: String, categories: [String]) -> TaskLink? {
        let l = text.lowercased()
        let match = categories.filter { l.contains($0.lowercased()) }.max { $0.count < $1.count }
        return match.map { TaskLink(category: $0) }
    }

    public static func parse(_ text: String, today: String, categories: [String] = [],
                             clock: DayClock = DayClock()) -> Parsed {
        var out: [String: [PlanTask]] = [:]
        var current: String?
        var skipped = 0
        var unassigned = 0
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if let day = headerDay(line, today: today, clock: clock) {
                current = day
                continue
            }
            let task = stripBullet(line)
            guard !task.isEmpty else { continue }
            if isRevisionLine(task) { skipped += 1; continue }
            guard let day = current else { unassigned += 1; continue }
            out[day, default: []].append(PlanTask(text: task, link: link(for: task, categories: categories)))
        }
        return Parsed(tasksByDay: out, skippedRevisionLines: skipped, unassignedLines: unassigned)
    }
}
