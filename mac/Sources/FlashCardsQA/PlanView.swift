import Charts
import FlashCardsCore
import SwiftUI

private let dayFormat: DateFormatter = {
    let f = DateFormatter()
    f.setLocalizedDateFormatFromTemplate("EEE d MMM")
    return f
}()

private func dayLabel(_ key: String, clock: DayClock, today: String) -> String {
    if key == today { return "Today" }
    if key == clock.add(1, to: today) { return "Tomorrow" }
    return clock.date(key).map { dayFormat.string(from: $0) } ?? key
}

struct PlanView: View {
    @Environment(StudySession.self) private var session
    @Environment(SessionNotifier.self) private var notifier

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("🗓 Study Plan").font(.system(size: 22, weight: .bold))
                    Text("Daily sessions sized to your time. Missed work moves to the next session.")
                        .font(.system(size: 13)).foregroundStyle(Theme.muted)
                }
                Spacer()
                Button("Back to categories") { session.reset() }
                    .buttonStyle(LinkButtonStyle()).keyboardShortcut(.cancelAction)
            }
            if session.cards.isEmpty {
                Text("Load a workbook first (Refresh or Import Excel) to build a plan.")
                    .foregroundStyle(Theme.muted).padding(24).frame(maxWidth: .infinity).panel()
            } else {
                OverviewPanel()
                TodayPanel()
                UpcomingPanel()
                CategoryProgressPanel()
            }
            TimeStatsPanel()
            ResearchNote()
        }
        .onAppear {
            session.ensureToday()
            notifier.requestPermission()
        }
    }
}

private struct SectionTitle: View {
    var text: String
    var body: some View {
        Text(text.uppercased()).font(.system(size: 11, weight: .bold)).kerning(1.2).foregroundStyle(Theme.muted)
    }
}

private struct ProgressLine: View {
    var label: String
    var value: Int
    var total: Int
    var color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label).font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(value) / \(total) · \(total == 0 ? 0 : Int((Double(value) / Double(total) * 100).rounded()))%")
                    .font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.muted)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.border)
                    Capsule().fill(color).frame(width: total == 0 ? 0 : geo.size.width * CGFloat(value) / CGFloat(total))
                }
            }
            .frame(height: 10)
        }
    }
}

// MARK: - Overview: finish dates and overall progress

private struct OverviewPanel: View {
    @Environment(StudySession.self) private var session
    @Environment(ProgressStore.self) private var store

    var body: some View {
        let cards = session.planCards
        let learned = cards.filter { session.review(for: $0) != nil }.count
        let mastered = cards.filter { SpacedRepetition.status(session.review(for: $0)) == .mastered }.count
        let forecast = session.forecast(days: 1)
        let atLock = store.data.dayTargets[session.today]?.learnedByAtLock

        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                estimate("All cards learned by", forecast.learnedBy, slip: slip(from: atLock, to: forecast.learnedBy))
                estimate("Mastered (3-week memory) by", forecast.masteredBy, slip: nil)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Study time per day").font(.system(size: 12)).foregroundStyle(Theme.muted)
                    Text(Durations.short(Double(session.studySlots.reduce(0) { $0 + $1.minutes } * 60)))
                        .font(.system(size: 22, weight: .heavy))
                    Text("\(session.studySlots.count) sessions · change in Settings (⌘,)")
                        .font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
                .padding(.vertical, 10).padding(.horizontal, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.bg, in: RoundedRectangle(cornerRadius: 10))
            }
            ProgressLine(label: "Learned", value: learned, total: cards.count, color: Theme.red.opacity(0.8))
            ProgressLine(label: "Mastered", value: mastered, total: cards.count, color: Theme.accent)
            CategoryPicker()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    private func slip(from planned: String?, to now: String?) -> Int? {
        guard let planned, let now else { return nil }
        let d = session.clock.days(from: planned, to: now)
        return d == 0 ? nil : d
    }

    private func estimate(_ title: String, _ day: String?, slip: Int?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 12)).foregroundStyle(Theme.muted)
            Text(day.map { dayLabel($0, clock: session.clock, today: session.today) } ?? "—")
                .font(.system(size: 22, weight: .heavy))
            if let day {
                let n = session.clock.days(from: session.today, to: day)
                Text(n <= 0 ? "on track for today" : "in \(n) day\(n == 1 ? "" : "s")")
                    .font(.system(size: 11)).foregroundStyle(Theme.muted)
            } else {
                Text("add a learning session in Settings").font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
            if let slip {
                Text(slip > 0 ? "⚠︎ \(slip) day\(slip == 1 ? "" : "s") later than this morning" : "▲ \(-slip) day\(slip == -1 ? "" : "s") earlier than this morning")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(slip > 0 ? Theme.red : Theme.accent)
            }
        }
        .padding(.vertical, 10).padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.bg, in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct CategoryPicker: View {
    @Environment(StudySession.self) private var session
    @Environment(ProgressStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Categories in the plan (none selected = all). Changes apply from tomorrow, or use Rebuild in Settings.")
                .font(.system(size: 12)).foregroundStyle(Theme.muted)
            FlowLayout(spacing: 7) {
                ForEach(session.categories, id: \.self) { category in
                    let on = store.data.plan.categories.contains(category)
                    Button {
                        if on { store.data.plan.categories.removeAll { $0 == category } }
                        else { store.data.plan.categories.append(category) }
                    } label: {
                        Text((on ? "✓ " : "") + category + " · \(CardTiming.minutes(for: category, overrides: store.data.categoryMinutes))m")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(on ? .white : Theme.muted)
                            .padding(.vertical, 6).padding(.horizontal, 12)
                            .background(on ? Theme.accent : Theme.card, in: Capsule())
                            .overlay(Capsule().stroke(on ? Theme.accent : Theme.border))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Today's sessions

private struct TodayPanel: View {
    @Environment(StudySession.self) private var session
    @Environment(SessionNotifier.self) private var notifier

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionTitle(text: "Today's sessions")
                Spacer()
                if notifier.authorized == false {
                    Text("🔕 Reminders are off — allow notifications for FlashCardsQA in System Settings › Notifications.")
                        .font(.system(size: 11)).foregroundStyle(Theme.red)
                } else if notifier.scheduledCount > 0 {
                    Text("🔔 \(notifier.scheduledCount) reminders scheduled, \(session.progress.data.notifyLeadMinutes) min before each session")
                        .font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
            }
            ForEach(session.allSlots) { slot in
                if slot.focus.isStudy {
                    SessionRow(slot: slot)
                } else {
                    HStack(spacing: 10) {
                        Text(slot.emoji)
                        Text("\(slot.timeRange)  \(slot.name)").font(.system(size: 13, weight: .semibold))
                        Text("Applications, follow-ups, lunch. Not counted as study.")
                            .font(.system(size: 12)).foregroundStyle(Theme.muted)
                    }
                    .padding(.vertical, 10).padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.bg.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
                }
            }
            HStack(spacing: 10) {
                Button("🗓 Busy today (interview / applications)") { session.busyToday() }
                    .buttonStyle(OutlineButtonStyle())
                    .disabled(session.todayRemaining.new + session.todayRemaining.review == 0)
                    .help("Moves everything left today to tomorrow")
                Button("🔁 Quick recall: today's new (\(session.todaysNewCards.count))") { session.startQuickRecall() }
                    .buttonStyle(OutlineButtonStyle())
                    .disabled(session.todaysNewCards.isEmpty)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }
}

private struct SessionRow: View {
    @Environment(StudySession.self) private var session
    @Environment(ProgressStore.self) private var store
    let slot: StudySlot

    var body: some View {
        let target = session.target(for: slot)
        let status = session.status(for: slot)
        let total = target.allKeys.count
        let done = target.allKeys.filter { session.isDoneToday($0) }.count
        let left = session.remaining(slot)
        let carriedLeft = target.carriedKeys.filter { !session.isDoneToday($0) }.count

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(slot.emoji).font(.system(size: 18))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(slot.name) · \(slot.timeRange)").font(.system(size: 14, weight: .bold))
                    Text(slot.focus.label).font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
                badge(status)
                Spacer()
                if !left.new.isEmpty {
                    Button("📖 Learn \(left.new.count) new") { session.startSession(slot) }
                        .buttonStyle(FilledButtonStyle(color: Theme.accent))
                }
                if !left.review.isEmpty {
                    Button("🔁 Revise \(left.review.count)") { session.startSessionReviews(slot) }
                        .buttonStyle(FilledButtonStyle(color: left.new.isEmpty ? Theme.red : Theme.inkButton))
                }
            }
            Text(describe(target))
                .font(.system(size: 12)).foregroundStyle(Theme.muted)
            if carriedLeft > 0 {
                Text("↪ \(carriedLeft) carried over from an earlier session")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.red)
            }
            if status == .missed && left.new.isEmpty && left.review.isEmpty && done < total {
                Text("Time's up — \(total - done) moved to the next session")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.red)
            }
            if total > 0 {
                ProgressLine(label: "Done", value: done, total: total, color: status == .done ? Theme.accent : Theme.red.opacity(0.75))
            }
        }
        .padding(14)
        .background(status == .now ? Theme.accentSoft : Theme.bg, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(status == .now ? Theme.accent : .clear))
    }

    private func describe(_ target: SlotTarget) -> String {
        if target.allKeys.isEmpty { return "Nothing due — free time, or use Quick recall below." }
        let cost = CostModel(store.data)
        var parts: [String] = []
        let newCards = session.cards(for: target.newKeys)
        let reviewCards = session.cards(for: target.reviewKeys)
        if !newCards.isEmpty { parts.append("Learn \(newCards.count) new: \(breakdown(newCards))") }
        if !reviewCards.isEmpty { parts.append("Revise \(reviewCards.count): \(breakdown(reviewCards))") }
        let minutes = newCards.reduce(0) { $0 + cost.newMinutes($1.topic) } + reviewCards.reduce(0) { $0 + cost.reviewMinutes($1.topic) }
        return parts.joined(separator: " · ") + " · ~\(Int(minutes.rounded())) min"
    }

    private func breakdown(_ cards: [Card]) -> String {
        Dictionary(grouping: cards, by: \.topic).mapValues(\.count)
            .sorted { $0.value > $1.value }.map { "\($0.key) ×\($0.value)" }.joined(separator: ", ")
    }

    @ViewBuilder private func badge(_ status: SlotStatus) -> some View {
        switch status {
        case .done: pill("Done ✓", Theme.accent)
        case .now: pill("Now", Theme.accent)
        case .upcoming: pill("Upcoming", Theme.muted)
        case .missed: pill("Missed → carried", Theme.red)
        case .skipped: pill("Skipped (busy)", Theme.muted)
        }
    }

    private func pill(_ text: String, _ color: Color) -> some View {
        Text(text).font(.system(size: 11, weight: .bold)).foregroundStyle(color)
            .padding(.vertical, 3).padding(.horizontal, 8)
            .background(color.opacity(0.12), in: Capsule())
    }
}

// MARK: - Next 14 days

private struct UpcomingPanel: View {
    @Environment(StudySession.self) private var session

    var body: some View {
        let forecast = session.forecast()
        let slots = session.studySlots
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "Next \(forecast.days.count) days")
            Grid(alignment: .leading, horizontalSpacing: 22, verticalSpacing: 7) {
                GridRow {
                    Text("Day")
                    ForEach(slots) { Text("\($0.emoji) \($0.name)") }
                    Text("Time")
                    Text("")
                }
                .font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.muted)
                ForEach(forecast.days, id: \.day) { day in
                    GridRow {
                        Text(dayLabel(day.day, clock: session.clock, today: session.today))
                            .fontWeight(day.day == session.today ? .bold : .regular)
                        ForEach(day.slots, id: \.slotId) { s in
                            Text(cell(s)).foregroundStyle(s.newCount + s.reviewCount == 0 ? Theme.muted : Theme.ink)
                        }
                        Text("~\(Durations.short(day.minutes * 60))").foregroundStyle(Theme.muted)
                        if day.carried > 0 {
                            Text("↪ \(day.carried) carried").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.red)
                        } else {
                            Text("")
                        }
                    }
                    .font(.system(size: 13).monospacedDigit())
                }
            }
            Text("Today shows what's left. Later days assume you keep up and recall correctly; misses push work forward.")
                .font(.system(size: 11)).foregroundStyle(Theme.muted)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    private func cell(_ s: SlotForecast) -> String {
        var parts: [String] = []
        if s.newCount > 0 { parts.append("\(s.newCount) new") }
        if s.reviewCount > 0 { parts.append("\(s.reviewCount) rev") }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }
}

// MARK: - Progress by category

private struct CategoryProgressPanel: View {
    @Environment(StudySession.self) private var session

    var body: some View {
        let groups = Dictionary(grouping: session.planCards, by: \.topic)
        let order = session.categories.filter { groups[$0] != nil }
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionTitle(text: "Progress by category")
                Spacer()
                legend(Theme.border, "New")
                legend(Theme.red.opacity(0.75), "Learning")
                legend(Theme.accent, "Mastered (3+ week memory)")
            }
            ForEach(order, id: \.self) { category in
                let cards = groups[category] ?? []
                let counts = Dictionary(grouping: cards) { SpacedRepetition.status(session.review(for: $0)) }
                    .mapValues(\.count)
                let learned = cards.count - (counts[.new] ?? 0)
                let weak = cards.filter { SpacedRepetition.isWeak(session.review(for: $0)) }.count
                HStack(spacing: 12) {
                    Text(category).font(.system(size: 13, weight: .semibold)).frame(width: 200, alignment: .leading)
                        .lineLimit(1)
                    GeometryReader { geo in
                        HStack(spacing: 0) {
                            segment(counts[.mastered] ?? 0, cards.count, geo.size.width, Theme.accent)
                            segment(counts[.learning] ?? 0, cards.count, geo.size.width, Theme.red.opacity(0.75))
                            segment(counts[.new] ?? 0, cards.count, geo.size.width, Theme.border)
                        }
                        .clipShape(Capsule())
                    }
                    .frame(height: 10)
                    Text("\(learned)/\(cards.count) learned" + (weak > 0 ? " · \(weak) weak" : ""))
                        .font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.muted)
                        .frame(width: 170, alignment: .trailing)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    private func segment(_ n: Int, _ total: Int, _ width: CGFloat, _ color: Color) -> some View {
        Rectangle().fill(color).frame(width: total == 0 ? 0 : width * CGFloat(n) / CGFloat(total))
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).font(.system(size: 11)).foregroundStyle(Theme.muted)
        }
    }
}

// MARK: - Time stats

private struct TimeStatsPanel: View {
    @Environment(ProgressStore.self) private var store
    @Environment(StudySession.self) private var session

    private struct Point: Identifiable {
        let id = UUID()
        let day: Date
        let activity: String
        let minutes: Double
    }

    var body: some View {
        let log = store.data.timeLog
        let clock = session.clock
        let today = session.today
        let week = (0..<7).map { clock.add(-$0, to: today) }
        let fortnight = (0..<14).reversed().map { clock.add(-$0, to: today) }
        let points = fortnight.flatMap { day in
            Activity.allCases.map { a in
                Point(day: clock.date(day) ?? Date(), activity: a.label, minutes: log.total(day: day, activity: a) / 60)
            }
        }
        let timing = store.data.timing.sorted { $0.key < $1.key }
        let slowest = store.data.cardSeconds.sorted { $0.value > $1.value }.prefix(5)
            .compactMap { pair in session.cards(for: [pair.key]).first.map { ($0, pair.value) } }

        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(text: "Study time")
            HStack(spacing: 12) {
                block("Today", log.total(day: today), log.total(day: today, activity: .study), log.total(day: today, activity: .revise))
                block("Last 7 days", log.total(days: week), log.total(days: week, activity: .study), log.total(days: week, activity: .revise))
                block("All time", log.total(), log.total(activity: .study), log.total(activity: .revise))
            }
            Chart(points) { p in
                BarMark(x: .value("Day", p.day, unit: .day), y: .value("Minutes", p.minutes))
                    .foregroundStyle(by: .value("Activity", p.activity))
            }
            .chartForegroundStyleScale(["Studying": Theme.accent, "Revising": Theme.red])
            .chartYAxisLabel("minutes")
            .frame(height: 170)

            if timing.isEmpty {
                Text("Start the ⏱ timer on a card to track time per card.")
                    .font(.system(size: 12)).foregroundStyle(Theme.muted)
            } else {
                HStack(alignment: .top, spacing: 30) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Average time per card").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted)
                        ForEach(timing, id: \.key) { item in
                            HStack {
                                Text(item.key).font(.system(size: 13))
                                Spacer(minLength: 16)
                                Text(avg(item.value)).font(.system(size: 13).monospacedDigit()).foregroundStyle(Theme.muted)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Slowest cards").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted)
                        ForEach(slowest, id: \.0.id) { card, seconds in
                            HStack {
                                Text(card.question).font(.system(size: 13)).lineLimit(1)
                                Spacer(minLength: 16)
                                Text(Durations.short(seconds)).font(.system(size: 13, weight: .semibold).monospacedDigit())
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    private func avg(_ t: TimingStats) -> String {
        var parts: [String] = []
        if t.newCount > 0 { parts.append("learn \(Durations.short(t.newSeconds / Double(t.newCount)))") }
        if t.reviewCount > 0 { parts.append("revise \(Durations.short(t.reviewSeconds / Double(t.reviewCount)))") }
        return parts.joined(separator: " · ")
    }

    private func block(_ title: String, _ total: Double, _ study: Double, _ revise: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 12)).foregroundStyle(Theme.muted)
            Text(Durations.short(total)).font(.system(size: 22, weight: .heavy))
            Text("Studying \(Durations.short(study)) · Revising \(Durations.short(revise))")
                .font(.system(size: 11)).foregroundStyle(Theme.muted)
        }
        .padding(.vertical, 10).padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.bg, in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Research and tips

private struct ResearchNote: View {
    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                point("FSRS scheduling", "Each card has its own memory model (stability, difficulty, recall chance). FSRS-5, the scheduler in Anki since 2023, sets the next review for when your recall would drop to your target (90%), so easy cards wait longer and hard ones come back sooner. It needs fewer reviews than older fixed or SM-2 schedules for the same recall.")
                point("Spacing effect", "Reviews spread over growing gaps beat cramming; FSRS picks the gaps per card. (Ebbinghaus; Cepeda et al., 2006)")
                point("Rate honestly", "Again = forgot, Hard = got it with effort, Good = recalled, Easy = instant. Honest ratings make the schedule fit you.")
                point("Retrieval practice", "Recalling an answer strengthens memory more than re-reading, so new cards end with \"Test yourself\" and reviews use Practice mode. (Roediger & Karpicke, 2006)")
                point("Interleaving", "Mixing categories helps you tell topics apart: new cards rotate across categories and reviews are shuffled. (Rohrer & Taylor, 2007)")
                point("Morning for new material", "Learn new cards when you're freshest; do applications at midday when focus dips anyway.")
                point("Evening review", "A short review before sleep helps memories settle overnight.")
                point("Time boxes and breaks", "5 minutes per Q&A and 20 per C program keeps you from over-polishing one card; take 10 minutes off after ~50 minutes of focus.")
                point("Interview or busy day", "Use \"Busy today\" — the plan moves the work and shows the new finish date instead of letting cards pile up silently.")
            }
            .padding(.top, 8)
        } label: {
            Text("Why this plan works · tips for job-hunt study days").font(.system(size: 13, weight: .semibold))
        }
        .padding(16)
        .panel()
    }

    private func point(_ title: String, _ text: String) -> some View {
        (Text(title + ": ").bold() + Text(text))
            .font(.system(size: 12)).foregroundStyle(Theme.ink)
            .fixedSize(horizontal: false, vertical: true)
    }
}
