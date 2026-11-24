import Foundation

/// A card in the plan's scope, in workbook order.
public struct PlanCard: Equatable, Sendable {
    public var key: String
    public var topic: String

    public init(key: String, topic: String) {
        self.key = key
        self.topic = topic
    }
}

/// Minutes per card. Starts from the card time box (5 / 20 min; reviews a fifth of that) and
/// switches to your real average once a category has enough timed cards.
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

public enum SlotStatus: Equatable, Sendable {
    case done, now, upcoming, missed, skipped
}

public struct SlotForecast: Equatable, Sendable {
    public var slotId: String
    public var newCount: Int
    public var reviewCount: Int
    public var minutes: Double
    public var carried: Int
}

public struct DayForecast: Equatable, Sendable {
    public var day: String
    public var slots: [SlotForecast]

    public var newCount: Int { slots.reduce(0) { $0 + $1.newCount } }
    public var reviewCount: Int { slots.reduce(0) { $0 + $1.reviewCount } }
    public var minutes: Double { slots.reduce(0) { $0 + $1.minutes } }
    public var carried: Int { slots.reduce(0) { $0 + $1.carried } }
}

public struct Forecast: Equatable, Sendable {
    public var days: [DayForecast]
    /// Day the last new card is planned to be learned; nil if it can't be reached.
    public var learnedBy: String?
    /// Day every card reaches a 7-day review gap; nil if beyond the horizon.
    public var masteredBy: String?
}

/// Session-based planning: daily targets per study session, carry-over of missed work,
/// and a finish-date forecast from the time you have each day.
public enum SessionPlanner {
    public static let horizonDays = 400

    public static func studySlots(_ slots: [StudySlot]) -> [StudySlot] {
        slots.filter { $0.enabled && $0.focus.isStudy && $0.minutes > 0 }.sorted { $0.start < $1.start }
    }

    static func dayIndex(_ day: String, clock: DayClock) -> Int {
        clock.days(from: "2000-01-01", to: day)
    }

    /// Topics in workbook order of first appearance.
    static func topicOrder(_ cards: [PlanCard]) -> [String] {
        var seen = Set<String>()
        return cards.compactMap { seen.insert($0.topic).inserted ? $0.topic : nil }
    }

    /// Round-robin across categories (starting at `rotation`) until the budget is used.
    static func pickNew(queues: inout [String: [PlanCard]], order: [String], rotation: Int,
                        budget: Double, cost: CostModel) -> [PlanCard] {
        guard !order.isEmpty else { return [] }
        let n = order.count
        let rotated = (0..<n).map { order[(($0 + rotation) % n + n) % n] }
        var picked: [PlanCard] = []
        var left = budget
        var progress = true
        while progress {
            progress = false
            for topic in rotated {
                guard let next = queues[topic]?.first else { continue }
                let c = cost.newMinutes(topic)
                guard c <= left + 0.001 else { continue }
                picked.append(next)
                queues[topic]?.removeFirst()
                left -= c
                progress = true
            }
        }
        return picked
    }

    // MARK: Locking a day

    /// Works out the day's session targets once, so they don't move while you work.
    public static func lockDay(_ data: inout ProgressData, cards: [PlanCard], day: String,
                               clock: DayClock = DayClock()) {
        var dt = data.dayTargets[day] ?? DayTargets()
        guard !dt.locked else { return }
        let slots = studySlots(data.slots)
        let cost = CostModel(data)
        let topicOf = Dictionary(cards.map { ($0.key, $0.topic) }, uniquingKeysWith: { a, _ in a })
        let inScope = Set(cards.map(\.key))

        let carriedNew = unique(dt.carryInNew.filter { inScope.contains($0) && data.cards[$0] == nil && !data.isDone($0, on: day) })
        let carriedReview = unique(dt.carryInReview.filter { inScope.contains($0) && !data.isDone($0, on: day) && !carriedNew.contains($0) })
        let taken = Set(carriedNew + carriedReview)

        var queues: [String: [PlanCard]] = [:]
        for card in cards where data.cards[card.key] == nil && !taken.contains(card.key) && !data.isDone(card.key, on: day) {
            queues[card.topic, default: []].append(card)
        }
        let order = topicOrder(cards)

        var due = cards.filter { c in
            guard !taken.contains(c.key), !data.isDone(c.key, on: day), let r = data.cards[c.key] else { return false }
            return r.dueDay <= day
        }.sorted { (data.cards[$0.key]!.dueDay, -data.cards[$0.key]!.lapses) < (data.cards[$1.key]!.dueDay, -data.cards[$1.key]!.lapses) }

        var targets: [String: SlotTarget] = [:]
        var rotation = dayIndex(day, clock: clock)
        for (i, slot) in slots.enumerated() {
            var target = SlotTarget()
            var budget = Double(slot.minutes)
            if i == 0 && !(carriedNew.isEmpty && carriedReview.isEmpty) {
                target.newKeys += carriedNew
                target.reviewKeys += carriedReview
                target.carriedKeys = carriedNew + carriedReview
                budget -= carriedNew.reduce(0) { $0 + cost.newMinutes(topicOf[$1] ?? "") }
                budget -= carriedReview.reduce(0) { $0 + cost.reviewMinutes(topicOf[$1] ?? "") }
            }
            switch slot.focus {
            case .learnNew:
                target.newKeys += pickNew(queues: &queues, order: order, rotation: rotation, budget: budget, cost: cost).map(\.key)
                rotation += 1
            case .review:
                while let next = due.first, budget >= cost.reviewMinutes(next.topic) - 0.001 {
                    target.reviewKeys.append(next.key)
                    budget -= cost.reviewMinutes(next.topic)
                    due.removeFirst()
                }
            case .jobSearch:
                break
            }
            targets[slot.id] = target
        }
        dt.slots = targets
        dt.locked = true
        dt.carryInNew = []
        dt.carryInReview = []
        data.dayTargets[day] = dt
        dt.learnedByAtLock = forecast(data, cards: cards, today: day, days: 1, clock: clock).learnedBy
        data.dayTargets[day] = dt
    }

    private static func unique(_ keys: [String]) -> [String] {
        var seen = Set<String>()
        return keys.filter { seen.insert($0).inserted }
    }

    // MARK: Carry-over

    private static func carryToTomorrow(_ data: inout ProgressData, from day: String, keys: [String], clock: DayClock) {
        let tomorrow = clock.add(1, to: day)
        var next = data.dayTargets[tomorrow] ?? DayTargets()
        for key in keys where !next.carryInNew.contains(key) && !next.carryInReview.contains(key) {
            if data.cards[key] == nil { next.carryInNew.append(key) } else { next.carryInReview.append(key) }
        }
        if next.locked {
            // Tomorrow is already planned: add to its first study session.
            if let first = studySlots(data.slots).first {
                var t = next.slots[first.id] ?? SlotTarget()
                for key in next.carryInNew where !t.newKeys.contains(key) { t.newKeys.append(key); t.carriedKeys.append(key) }
                for key in next.carryInReview where !t.reviewKeys.contains(key) { t.reviewKeys.append(key); t.carriedKeys.append(key) }
                next.slots[first.id] = t
            }
            next.carryInNew = []
            next.carryInReview = []
        }
        data.dayTargets[tomorrow] = next
    }

    /// Moves unfinished work from sessions that have ended into the next session (or tomorrow).
    public static func rollOver(_ data: inout ProgressData, day: String, nowMinute: Int, clock: DayClock = DayClock()) {
        guard var dt = data.dayTargets[day], dt.locked else { return }
        let slots = studySlots(data.slots)
        for (i, slot) in slots.enumerated() where slot.end <= nowMinute {
            guard var target = dt.slots[slot.id], !target.rolledOver, !target.skipped else { continue }
            let left = target.allKeys.filter { !data.isDone($0, on: day) }
            target.rolledOver = true
            dt.slots[slot.id] = target
            guard !left.isEmpty else { continue }
            if i + 1 < slots.count {
                var next = dt.slots[slots[i + 1].id] ?? SlotTarget()
                for key in left where !next.allKeys.contains(key) {
                    if target.newKeys.contains(key) { next.newKeys.append(key) } else { next.reviewKeys.append(key) }
                    next.carriedKeys.append(key)
                }
                dt.slots[slots[i + 1].id] = next
            } else {
                data.dayTargets[day] = dt
                carryToTomorrow(&data, from: day, keys: left, clock: clock)
                dt = data.dayTargets[day]!
            }
        }
        data.dayTargets[day] = dt
    }

    /// Rolls over every earlier day (the app may have been closed for days) so leftovers reach today.
    public static func catchUp(_ data: inout ProgressData, today: String, clock: DayClock = DayClock()) {
        guard let first = data.dayTargets.keys.min(), first < today else { return }
        var day = first
        var guardCount = 0
        while day < today && guardCount < 1000 {
            guardCount += 1
            if let dt = data.dayTargets[day] {
                if dt.locked {
                    rollOver(&data, day: day, nowMinute: 24 * 60, clock: clock)
                } else if !(dt.carryInNew.isEmpty && dt.carryInReview.isEmpty) {
                    carryToTomorrow(&data, from: day, keys: dt.carryInNew + dt.carryInReview, clock: clock)
                    data.dayTargets[day]?.carryInNew = []
                    data.dayTargets[day]?.carryInReview = []
                }
            }
            day = clock.add(1, to: day)
        }
    }

    /// "Busy today": moves everything left today to tomorrow.
    public static func skipRest(_ data: inout ProgressData, day: String, clock: DayClock = DayClock()) {
        guard var dt = data.dayTargets[day], dt.locked else { return }
        var left: [String] = []
        for slot in studySlots(data.slots) {
            guard var target = dt.slots[slot.id], !target.rolledOver, !target.skipped else { continue }
            left += target.allKeys.filter { !data.isDone($0, on: day) }
            target.skipped = true
            target.rolledOver = true
            dt.slots[slot.id] = target
        }
        data.dayTargets[day] = dt
        if !left.isEmpty { carryToTomorrow(&data, from: day, keys: unique(left), clock: clock) }
    }

    public static func status(of slot: StudySlot, on day: String, data: ProgressData, nowMinute: Int) -> SlotStatus {
        let target = data.dayTargets[day]?.slots[slot.id] ?? SlotTarget()
        if target.skipped { return .skipped }
        let total = target.allKeys.count
        let done = target.allKeys.filter { data.isDone($0, on: day) }.count
        if total > 0 && done == total { return .done }
        if nowMinute >= slot.end { return total == 0 ? .done : .missed }
        if nowMinute >= slot.start { return .now }
        return .upcoming
    }

    // MARK: Forecast

    private struct SimCard {
        var memory: FSRS.Memory?
        var last: String
        var due: String
    }

    /// Simulates future days session by session with FSRS, assuming targets are met and each
    /// recall is rated Good.
    public static func forecast(_ data: ProgressData, cards: [PlanCard], today: String, nowMinute: Int = 0,
                                days: Int = 14, clock: DayClock = DayClock()) -> Forecast {
        let slots = studySlots(data.slots)
        let cost = CostModel(data)
        let order = topicOrder(cards)
        let topicOf = Dictionary(cards.map { ($0.key, $0.topic) }, uniquingKeysWith: { a, _ in a })

        var sim: [String: SimCard] = [:]
        for c in cards {
            if let r = data.cards[c.key] { sim[c.key] = SimCard(memory: FSRS.memory(of: r), last: r.lastReviewed, due: r.dueDay) }
        }
        let retention = data.desiredRetention

        func advance(_ key: String, on day: String) {
            var s = sim[key] ?? SimCard(memory: nil, last: day, due: day)
            let m = FSRS.next(s.memory, rating: .good, elapsedDays: clock.days(from: s.last, to: day))
            s.memory = m
            s.last = day
            s.due = clock.add(FSRS.interval(stability: m.stability, retention: retention), to: day)
            sim[key] = s
        }

        // Today: the locked targets (what's left of them).
        let todayTargets = data.dayTargets[today]
        var plannedToday = Set<String>()
        var todayRow: [SlotForecast] = []
        for slot in slots {
            let t = todayTargets?.slots[slot.id] ?? SlotTarget()
            // Ended sessions have already passed their leftovers on.
            let skipped = t.skipped || t.rolledOver
            let newLeft = skipped ? [] : t.newKeys.filter { !data.isDone($0, on: today) && data.cards[$0] == nil }
            let revLeft = skipped ? [] : t.reviewKeys.filter { !data.isDone($0, on: today) }
            let minutes = newLeft.reduce(0) { $0 + cost.newMinutes(topicOf[$1] ?? "") }
                + revLeft.reduce(0) { $0 + cost.reviewMinutes(topicOf[$1] ?? "") }
            todayRow.append(SlotForecast(slotId: slot.id, newCount: newLeft.count, reviewCount: revLeft.count,
                                         minutes: minutes, carried: t.carriedKeys.filter { !data.isDone($0, on: today) }.count))
            for key in newLeft + revLeft { plannedToday.insert(key); advance(key, on: today) }
        }
        // Work carried into tomorrow from today is still waiting.
        var queues: [String: [PlanCard]] = [:]
        for c in cards where sim[c.key] == nil { queues[c.topic, default: []].append(c) }
        let carryIn = Set((data.dayTargets[clock.add(1, to: today)]?.carryInNew ?? []))

        var rows = [DayForecast(day: today, slots: todayRow)]
        let allKeys = cards.map(\.key)
        func unseenCount() -> Int { queues.values.reduce(0) { $0 + $1.count } }
        func allMastered() -> Bool {
            !allKeys.isEmpty && allKeys.allSatisfy { (sim[$0]?.memory?.stability ?? 0) >= FSRS.masteredStability }
        }

        var learnedBy: String? = unseenCount() == 0 && !cards.isEmpty ? today : nil
        var masteredBy: String? = allMastered() ? today : nil
        let canLearn = slots.contains { $0.focus == .learnNew }
        let canReview = slots.contains { $0.focus == .review }

        var offset = 1
        while offset <= horizonDays {
            if offset >= days && (learnedBy != nil || !canLearn) && (masteredBy != nil || !canReview) { break }
            let day = clock.add(offset, to: today)
            var rotation = dayIndex(day, clock: clock)
            var due = sim.filter { $0.value.due <= day }.map(\.key).sorted { sim[$0]!.due < sim[$1]!.due }
            var row: [SlotForecast] = []
            for (i, slot) in slots.enumerated() {
                var budget = Double(slot.minutes)
                var newCount = 0, reviewCount = 0, minutes = 0.0, carried = 0
                if offset == 1 && i == 0 && !carryIn.isEmpty {
                    carried = carryIn.count
                }
                switch slot.focus {
                case .learnNew:
                    let picked = pickNew(queues: &queues, order: order, rotation: rotation, budget: budget, cost: cost)
                    rotation += 1
                    for p in picked {
                        minutes += cost.newMinutes(p.topic)
                        advance(p.key, on: day)
                    }
                    newCount = picked.count
                case .review:
                    while let key = due.first, budget >= cost.reviewMinutes(topicOf[key] ?? "") - 0.001 {
                        let c = cost.reviewMinutes(topicOf[key] ?? "")
                        budget -= c
                        minutes += c
                        reviewCount += 1
                        advance(key, on: day)
                        due.removeFirst()
                    }
                case .jobSearch:
                    break
                }
                row.append(SlotForecast(slotId: slot.id, newCount: newCount, reviewCount: reviewCount,
                                        minutes: minutes, carried: carried))
            }
            if offset < days { rows.append(DayForecast(day: day, slots: row)) }
            if learnedBy == nil && unseenCount() == 0 && !cards.isEmpty { learnedBy = day }
            if masteredBy == nil && allMastered() { masteredBy = day }
            offset += 1
        }
        _ = plannedToday
        return Forecast(days: rows, learnedBy: learnedBy, masteredBy: masteredBy)
    }
}
