import Foundation

/// Focus seconds per day, activity and category.
public struct TimeLog: Codable, Equatable, Sendable {
    /// day "yyyy-MM-dd" → activity raw value → category → seconds
    public var days: [String: [String: [String: Double]]] = [:]

    /// Ticks further apart than this mean the Mac slept or the app stalled; that gap is not counted.
    public static let maxTickGap: Double = 60

    public init() {}

    /// Seconds from one tick to the next that may be credited.
    public static func creditable(_ elapsed: Double) -> Double {
        elapsed > 0 && elapsed <= maxTickGap ? elapsed : 0
    }

    public mutating func add(_ seconds: Double, day: String, activity: Activity, category: String) {
        guard seconds > 0 else { return }
        days[day, default: [:]][activity.rawValue, default: [:]][category, default: 0] += seconds
    }

    public func total(day: String, activity: Activity? = nil) -> Double {
        guard let entry = days[day] else { return 0 }
        return entry.reduce(0) { sum, pair in
            guard activity == nil || pair.key == activity!.rawValue else { return sum }
            return sum + pair.value.values.reduce(0, +)
        }
    }

    public func total(days keys: [String], activity: Activity? = nil) -> Double {
        keys.reduce(0) { $0 + total(day: $1, activity: activity) }
    }

    public func total(activity: Activity? = nil) -> Double {
        total(days: Array(days.keys), activity: activity)
    }

    /// Category → seconds across the given days (all days when nil).
    public func byCategory(days keys: [String]? = nil) -> [String: Double] {
        var out: [String: Double] = [:]
        for key in keys ?? Array(days.keys) {
            for (_, categories) in days[key] ?? [:] {
                for (category, seconds) in categories { out[category, default: 0] += seconds }
            }
        }
        return out
    }
}

public enum Durations {
    /// "1h 25m", "12m", "45s"
    public static func short(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        if s >= 3600 { return "\(s / 3600)h \((s % 3600) / 60)m" }
        if s >= 60 { return "\(s / 60)m" }
        return "\(s)s"
    }

    /// "18:42"
    public static func clock(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded(.up)))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}
