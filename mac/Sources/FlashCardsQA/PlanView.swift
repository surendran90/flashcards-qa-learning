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
    @Environment(RevisionReminder.self) private var reminder

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("🗓 Study Plan").font(.system(size: 22, weight: .bold))
                    Text("Revise first — FSRS decides what's due. Then work through your own plan for the day.")
                        .font(.system(size: 13)).foregroundStyle(Theme.muted)
                }
                Spacer()
                Button("Back to categories") { session.reset() }
                    .buttonStyle(LinkButtonStyle()).keyboardShortcut(.cancelAction)
            }
            if session.cards.isEmpty {
                Text("Load a workbook first (Refresh or Import Excel) to see what's due.")
                    .foregroundStyle(Theme.muted).padding(24).frame(maxWidth: .infinity).panel()
            } else {
                RevisionPanel()
            }
            TasksPanel()
            NotesPanel()
            AlgorithmPanel()
            TimeStatsPanel()
            ResearchNote()
        }
        .onAppear { reminder.requestPermission() }
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

// MARK: - 1. Revise first

private struct RevisionPanel: View {
    @Environment(StudySession.self) private var session

    var body: some View {
        let due = session.dueCards
        let revised = session.revisedTodayCount
        let outlook = session.revisionOutlook(days: 7)
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(text: "1 · Revise first")
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 2) {
                    if due.isEmpty {
                        Text(revised > 0 ? "✅ Revision done" : "Nothing due")
                            .font(.system(size: 26, weight: .heavy)).foregroundStyle(Theme.accent)
                        Text(revised > 0 ? "\(revised) card\(revised == 1 ? "" : "s") revised today — on to your plan."
                                         : "No cards are due today. Go straight to your plan.")
                            .font(.system(size: 12)).foregroundStyle(Theme.muted)
                    } else {
                        Text("\(due.count) to revise").font(.system(size: 30, weight: .heavy)).foregroundStyle(Theme.red)
                        let split = session.split(due)
                        HStack(spacing: 8) {
                            if split.fixed > 0 { methodChip("📅 \(split.fixed) by fixed checkpoint", Theme.fixed) }
                            if split.fsrs > 0 { methodChip("🧠 \(split.fsrs) by FSRS", Theme.fsrs) }
                            Text("~\(Durations.short((outlook.first?.minutes ?? 0) * 60))"
                                 + (revised > 0 ? " · \(revised) already revised today" : ""))
                                .font(.system(size: 12)).foregroundStyle(Theme.muted)
                        }
                    }
                }
                Spacer()
                if !due.isEmpty {
                    Button("🔁 Start revision (\(due.count))") { session.startRevision() }
                        .buttonStyle(FilledButtonStyle(color: Theme.red))
                        .keyboardShortcut("r", modifiers: [.command, .shift])
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Coming up").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.muted)
                HStack(spacing: 6) {
                    ForEach(Array(outlook.enumerated()), id: \.offset) { i, day in
                        VStack(spacing: 2) {
                            Text(i == 0 ? "Today" : i == 1 ? "Tmrw" : shortDay(day.day))
                                .font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.muted)
                            Text("\(day.count)").font(.system(size: 15, weight: .heavy).monospacedDigit())
                                .foregroundStyle(day.count == 0 ? Theme.muted : Theme.ink)
                            let s = session.split(session.cardsDue(on: day.day))
                            HStack(spacing: 4) {
                                if s.fixed > 0 { Text("📅\(s.fixed)").foregroundStyle(Theme.fixed) }
                                if s.fsrs > 0 { Text("🧠\(s.fsrs)").foregroundStyle(Theme.fsrs) }
                            }
                            .font(.system(size: 9, weight: .bold))
                            .frame(height: 11)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(Theme.bg, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                HStack(spacing: 10) {
                    methodChip("📅 Fixed: 1, 3, 7, 14 days after studying", Theme.fixed)
                    methodChip("🧠 FSRS: from the day you study, by how well you remember", Theme.fsrs)
                    Text("A card comes back on whichever date is first.")
                        .font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
            }
            Divider().padding(.vertical, 2)
            CategoryProgressPanel()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    private func methodChip(_ text: String, _ color: Color) -> some View {
        Text(text).font(.system(size: 11, weight: .bold)).foregroundStyle(color)
            .padding(.vertical, 3).padding(.horizontal, 8)
            .background(color.opacity(0.14), in: Capsule())
            .fixedSize()
    }

    private func shortDay(_ key: String) -> String {
        guard let d = session.clock.date(key) else { return key }
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEE")
        return f.string(from: d)
    }
}

// MARK: - 2. Your plan (self-written tasks)

/// 3 · Study notes: your own phases and priorities, saved with your progress.
private struct NotesPanel: View {
    @Environment(StudySession.self) private var session
    @State private var editing = false
    @State private var draft = ""

    private var notes: String { session.progress.data.studyNotes ?? "" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionTitle(text: "3 · Study notes")
                Spacer()
                if editing {
                    Button("Cancel") { editing = false }
                        .buttonStyle(LinkButtonStyle())
                    Button("Save") { save() }
                        .buttonStyle(FilledButtonStyle(color: Theme.accent))
                        .keyboardShortcut("s", modifiers: .command)
                } else {
                    Button("✏️ Edit notes") { startEditing() }
                        .buttonStyle(OutlineButtonStyle())
                }
            }
            if editing {
                TextEditor(text: $draft)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 260)
                    .background(Theme.bg, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))
                Text("Start a line with * or - for a bullet; a line above bullets becomes a heading. ⌘S saves.")
                    .font(.system(size: 11)).foregroundStyle(Theme.muted)
            } else if notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("No notes yet. Select Edit notes to write your phases, priorities or reminders.")
                    .font(.system(size: 13)).foregroundStyle(Theme.muted)
            } else {
                rendered
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { startEditing() }
                    .help("Double-click to edit")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    private var rendered: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(StudyNotes.lines(notes).enumerated()), id: \.offset) { _, line in
                switch line {
                case .heading(let t):
                    Text(t).font(.system(size: 14, weight: .bold)).padding(.top, 4)
                case .bullet(let t):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(Theme.accent).font(.system(size: 13, weight: .bold))
                        Text(t).font(.system(size: 13))
                    }
                    .padding(.leading, 10)
                case .text(let t):
                    Text(t).font(.system(size: 13))
                case .gap:
                    Spacer().frame(height: 6)
                }
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func startEditing() {
        draft = notes
        editing = true
    }

    private func save() {
        session.progress.data.studyNotes = draft
        session.progress.saveNow()
        editing = false
    }
}

private struct TasksPanel: View {
    @Environment(StudySession.self) private var session
    @State private var dayOffset = 0
    @State private var newTask = ""
    @State private var editingID: String?
    @State private var editDraft = ""
    @State private var showPaste = false
    @State private var dropTarget: String?
    @FocusState private var editFocused: Bool

    private var day: String { session.clock.add(dayOffset, to: session.today) }

    var body: some View {
        let tasks = session.tasks(on: day)
        let doneCount = tasks.filter(\.done).count
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionTitle(text: "2 · Your plan")
                Spacer()
                Button("📋 Paste plan…") { showPaste = true }
                    .buttonStyle(OutlineButtonStyle())
                    .help("Paste a written plan with [Nov 25] style date headers")
            }
            HStack(spacing: 10) {
                Button { dayOffset -= 1 } label: { Image(systemName: "chevron.left") }.buttonStyle(.plain)
                Text(dayTitle).font(.system(size: 15, weight: .bold)).frame(minWidth: 150)
                Button { dayOffset += 1 } label: { Image(systemName: "chevron.right") }.buttonStyle(.plain)
                if dayOffset != 0 {
                    Button("Today") { dayOffset = 0 }.buttonStyle(LinkButtonStyle(underline: true))
                }
                Spacer()
                if !tasks.isEmpty {
                    Text("\(doneCount)/\(tasks.count) done").font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.muted)
                }
            }

            if dayOffset == 0 && !session.overdueTasks.isEmpty {
                overdueSection
            }

            VStack(spacing: 6) {
                ForEach(tasks) { task in row(task) }
            }
            if tasks.isEmpty {
                Text(dayOffset == 0 ? "No tasks for today yet. Add one below, or paste your written plan."
                                    : "Nothing planned for this day yet.")
                    .font(.system(size: 12)).foregroundStyle(Theme.muted)
            }

            HStack(spacing: 8) {
                TextField("Add a task, e.g. “All sorting in C Programs + linked list” — press Return", text: $newTask)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { add() }
                Button("＋ Add") { add() }
                    .buttonStyle(FilledButtonStyle(color: Theme.accent))
                    .disabled(newTask.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Text("Tip: a task that names a category (e.g. “Resume QA”) gets a ▶ Start button. Use the link menu to point it at a category or one of its sections.")
                .font(.system(size: 11)).foregroundStyle(Theme.muted)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
        .sheet(isPresented: $showPaste) { PastePlanSheet() }
    }

    private var dayTitle: String {
        switch dayOffset {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case -1: return "Yesterday"
        default:
            let f = DateFormatter()
            f.setLocalizedDateFormatFromTemplate("EEE d MMM")
            return session.clock.date(day).map { f.string(from: $0) } ?? day
        }
    }

    private func add() {
        session.addTask(newTask, on: day)
        newTask = ""
    }

    private var overdueSection: some View {
        let overdue = session.overdueTasks
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Unfinished from earlier (\(overdue.count))")
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.red)
                Spacer()
                Button("Move all to today") {
                    for item in overdue { session.moveTask(item.task.id, from: item.day, to: session.today) }
                }
                .buttonStyle(LinkButtonStyle(underline: true))
            }
            ForEach(overdue, id: \.task.id) { item in
                HStack {
                    Text(item.task.text).font(.system(size: 13)).lineLimit(1)
                    Spacer()
                    Button("→ Today") { session.moveTask(item.task.id, from: item.day, to: session.today) }
                        .buttonStyle(LinkButtonStyle(underline: true))
                    Button { session.updateTask(item.task.id, on: item.day) { $0.done = true } } label: {
                        Image(systemName: "checkmark")
                    }
                    .buttonStyle(.plain).help("Mark done")
                }
                .padding(.vertical, 6).padding(.horizontal, 10)
                .background(Theme.redSoft, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    @ViewBuilder
    private func row(_ task: PlanTask) -> some View {
        let linkCards = task.link.map(session.cards(for:)) ?? []
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.muted)
                .draggable(task.id)
            Button { session.updateTask(task.id, on: day) { $0.done.toggle() } } label: {
                Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(task.done ? Theme.accent : Theme.muted)
            }
            .buttonStyle(.plain)
            if editingID == task.id {
                TextField("Task", text: $editDraft)
                    .textFieldStyle(.roundedBorder)
                    .focused($editFocused)
                    .onSubmit { commitEdit(task) }
                    .onExitCommand { editingID = nil }
                    .onChange(of: editFocused) { _, f in if !f { commitEdit(task) } }
            } else {
                Text(task.text)
                    .font(.system(size: 14, weight: .semibold))
                    .strikethrough(task.done)
                    .foregroundStyle(task.done ? Theme.muted : Theme.ink)
                    .onTapGesture(count: 2) { editingID = task.id; editDraft = task.text; DispatchQueue.main.async { editFocused = true } }
                    .help("Double-click to edit")
            }
            Spacer()
            linkMenu(task)
            if task.link != nil {
                Button("▶ Start (\(linkCards.count))") { session.startTask(task) }
                    .buttonStyle(FilledButtonStyle(color: Theme.accent))
                    .disabled(linkCards.isEmpty)
            }
            Menu {
                if dayOffset != 1 {
                    Button("Move to tomorrow") { session.moveTask(task.id, from: day, to: session.clock.add(1, to: session.today)) }
                }
                if dayOffset != 0 {
                    Button("Move to today") { session.moveTask(task.id, from: day, to: session.today) }
                }
                Button("Edit") { editingID = task.id; editDraft = task.text; DispatchQueue.main.async { editFocused = true } }
                Divider()
                Button("Delete", role: .destructive) { session.deleteTask(task.id, on: day) }
            } label: {
                Image(systemName: "ellipsis.circle").foregroundStyle(Theme.muted)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        }
        .padding(.vertical, 8).padding(.horizontal, 12)
        .background(task.done ? Theme.bg : Theme.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(dropTarget == task.id ? Theme.accent : Theme.border,
                                                           lineWidth: dropTarget == task.id ? 2 : 1))
        .dropDestination(for: String.self) { ids, _ in
            guard let id = ids.first else { return false }
            session.moveTask(id, onto: task.id, on: day)
            dropTarget = nil
            return true
        } isTargeted: { t in dropTarget = t ? task.id : (dropTarget == task.id ? nil : dropTarget) }
    }

    private func linkMenu(_ task: PlanTask) -> some View {
        Menu {
            Button("No link") { session.updateTask(task.id, on: day) { $0.link = nil } }
            Divider()
            ForEach(session.categories, id: \.self) { category in
                let sections = session.dividers.filter { $0.sheet == category }
                if sections.isEmpty {
                    Button(category) { session.updateTask(task.id, on: day) { $0.link = TaskLink(category: category) } }
                } else {
                    Menu(category) {
                        Button("Whole category") { session.updateTask(task.id, on: day) { $0.link = TaskLink(category: category) } }
                        Divider()
                        ForEach(sections) { d in
                            Button(d.title) { session.updateTask(task.id, on: day) { $0.link = TaskLink(category: category, section: d.title) } }
                        }
                    }
                }
            }
        } label: {
            Text(task.link?.label ?? "🔗 Link")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(task.link == nil ? Theme.muted : Theme.accent)
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Link this task to a category or section so ▶ Start opens those questions")
    }

    private func commitEdit(_ task: PlanTask) {
        guard editingID == task.id else { return }
        editingID = nil
        let text = editDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text != task.text else { return }
        session.updateTask(task.id, on: day) { $0.text = text }
    }
}

/// Paste a written plan ("[Nov 25 ]" headers with tasks under them) to fill your days.
private struct PastePlanSheet: View {
    @Environment(StudySession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        let preview = PlanText.parse(text, today: session.today, categories: session.categories, clock: session.clock)
        VStack(alignment: .leading, spacing: 10) {
            Text("Paste your plan").font(.system(size: 16, weight: .bold))
            Text("Start each day with a date line such as [Nov 25] or 25 Nov, then one task per line. Lines like “Revise as per algo” are skipped — the app shows revision for you.")
                .font(.system(size: 12)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $text)
                .font(.system(size: 13, design: .monospaced))
                .frame(minHeight: 260)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))
            let days = preview.tasksByDay.keys.sorted()
            if !days.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(days, id: \.self) { d in
                        let tasks = preview.tasksByDay[d] ?? []
                        Text("\(d): " + tasks.map { $0.text + ($0.link.map { " 🔗\($0.category)" } ?? "") }.joined(separator: " · "))
                            .font(.system(size: 11)).foregroundStyle(Theme.ink).lineLimit(2)
                    }
                    if preview.skippedRevisionLines > 0 {
                        Text("Skipped \(preview.skippedRevisionLines) revision line\(preview.skippedRevisionLines == 1 ? "" : "s").")
                            .font(.system(size: 11)).foregroundStyle(Theme.muted)
                    }
                    if preview.unassignedLines > 0 {
                        Text("\(preview.unassignedLines) line\(preview.unassignedLines == 1 ? "" : "s") before the first date were ignored.")
                            .font(.system(size: 11)).foregroundStyle(Theme.red)
                    }
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(OutlineButtonStyle()).keyboardShortcut(.cancelAction)
                Button("Add \(preview.tasksByDay.values.map(\.count).reduce(0, +)) tasks") {
                    session.importPlan(text)
                    dismiss()
                }
                .buttonStyle(FilledButtonStyle(color: Theme.accent))
                .disabled(preview.tasksByDay.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 620)
    }
}

// MARK: - Algorithm

private struct AlgorithmPanel: View {
    @Environment(ProgressStore.self) private var store

    var body: some View {
        let target = Int((store.data.desiredRetention * 100).rounded())
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                SectionTitle(text: "How your reviews are scheduled")
                Spacer()
                SettingsLink { Text("Change target recall…").font(.system(size: 12, weight: .semibold)) }
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("🧠 FSRS-5").font(.system(size: 18, weight: .heavy))
                Text("Free Spaced Repetition Scheduler — the default in Anki since 2023 · target recall \(target)%")
                    .font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
            VStack(alignment: .leading, spacing: 5) {
                line("Memory model", "each card has its own stability (how long you'll remember it), difficulty, and chance of recall today.")
                line("Fixed checkpoints", store.data.useCheckpoints
                     ? "a newly studied card is revised 1, 3, 7 and 14 days later, whatever you rate it (Again restarts them). FSRS runs alongside from the same day; the card comes back on whichever date is first. After day 14 only FSRS is left."
                     : "off — FSRS schedules every card from the start (turn on in Settings › Memory).")
                line("Next review (FSRS)", "set for the day your chance of recall drops to \(target)% — easy cards wait longer, hard ones return sooner.")
                line("Your ratings", "❌ Again (forgot) · 😬 Hard · ✅ Good · ⭐ Easy. ✓ Studied (in Study mode) starts the checkpoints and FSRS.")
                line("Practice only", "answering a card that isn't due yet doesn't change its schedule.")
                line("Mastered", "when FSRS expects you to still recall the card three weeks later.")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    private func line(_ title: String, _ text: String) -> some View {
        (Text(title + ": ").bold() + Text(text))
            .font(.system(size: 12)).foregroundStyle(Theme.ink)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Studied cards and their FSRS schedule, per category

/// Per category: how many cards you've studied, and where they stand in FSRS. "Due today" uses
/// the same rule as "Revise first", so the numbers match. Expand a row to see each studied card.
private struct CategoryProgressPanel: View {
    @Environment(StudySession.self) private var session
    @State private var expanded: Set<String> = []

    private struct Row {
        var name: String
        var total = 0, studied = 0, dueToday = 0, next7 = 0, mastered = 0, weak = 0
    }

    var body: some View {
        let today = session.today
        let weekEnd = session.clock.add(7, to: today)
        let groups = Dictionary(grouping: session.cards, by: \.topic)
        let order = session.categories.filter { groups[$0] != nil }
        let rows: [Row] = order.map { name in
            var r = Row(name: name)
            for card in groups[name] ?? [] {
                r.total += 1
                guard let rev = session.review(for: card) else { continue }
                r.studied += 1
                if rev.dueDay <= today { r.dueToday += 1 } else if rev.dueDay <= weekEnd { r.next7 += 1 }
                if SpacedRepetition.status(rev) == .mastered { r.mastered += 1 }
                if SpacedRepetition.isWeak(rev) { r.weak += 1 }
            }
            return r
        }
        let all = rows.reduce(into: Row(name: "All categories")) { t, r in
            t.total += r.total; t.studied += r.studied; t.dueToday += r.dueToday
            t.next7 += r.next7; t.mastered += r.mastered; t.weak += r.weak
        }

        VStack(alignment: .leading, spacing: 10) {
            Text("By category").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.muted)
            Text("Studied = cards in your FSRS schedule (marked Studied or rated in Practice). ▶ Revise does one category's due cards; expand a category to see when each studied card comes back.")
                .font(.system(size: 11)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                GridRow {
                    Text("Category"); Text("Studied"); Text("Due today"); Text("Next 7 days"); Text("Mastered"); Text("Weak"); Text("")
                }
                .font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.muted)
                ForEach(rows, id: \.name) { r in
                    rowView(r, bold: false)
                    if expanded.contains(r.name) {
                        GridRow {
                            cardList(groups[r.name] ?? [])
                                .gridCellColumns(7)
                        }
                    }
                }
                Divider().gridCellUnsizedAxes(.horizontal)
                rowView(all, bold: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func rowView(_ r: Row, bold: Bool) -> some View {
        let canExpand = !bold && r.studied > 0
        GridRow {
            Button {
                guard canExpand else { return }
                if expanded.contains(r.name) { expanded.remove(r.name) } else { expanded.insert(r.name) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: expanded.contains(r.name) ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(canExpand ? Theme.muted : .clear)
                    Text(r.name).font(.system(size: 13, weight: bold ? .heavy : .semibold)).lineLimit(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(minWidth: 200, alignment: .leading)

            HStack(spacing: 8) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.border)
                        Capsule().fill(Theme.accent)
                            .frame(width: r.total == 0 ? 0 : geo.size.width * CGFloat(r.studied) / CGFloat(r.total))
                    }
                }
                .frame(width: 90, height: 8)
                Text("\(r.studied)/\(r.total)").font(.system(size: 12, weight: bold ? .bold : .regular).monospacedDigit())
                    .fixedSize()
            }
            count(r.dueToday, color: Theme.red, bold: bold)
            count(r.next7, color: Theme.ink, bold: bold)
            count(r.mastered, color: Theme.accent, bold: bold)
            count(r.weak, color: Theme.red, bold: bold)
            if !bold && r.dueToday > 0 {
                Button { session.startRevision(category: r.name) } label: {
                    Text("▶ Revise (\(r.dueToday))")
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                        .padding(.vertical, 4).padding(.horizontal, 9)
                        .background(Theme.red, in: Capsule())
                        .fixedSize()
                }
                .buttonStyle(.plain)
            } else {
                Text("")
            }
        }
    }

    private func count(_ n: Int, color: Color, bold: Bool) -> some View {
        Text(n == 0 ? "–" : "\(n)")
            .font(.system(size: 13, weight: bold ? .heavy : .semibold).monospacedDigit())
            .foregroundStyle(n == 0 ? Theme.muted : color)
    }

    /// Studied cards of one category, soonest due first.
    private func cardList(_ cards: [Card]) -> some View {
        let studied = cards.compactMap { c in session.review(for: c).map { (c, $0) } }
            .sorted { $0.1.dueDay < $1.1.dueDay }
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(studied, id: \.0.id) { card, rev in
                HStack(spacing: 10) {
                    Text(Rating(rawValue: rev.lastRating ?? 3)?.emoji ?? "✅").font(.system(size: 11))
                    Text(card.question).font(Theme.questionFont(card.topic, size: 12)).lineLimit(1)
                    Spacer(minLength: 12)
                    PhaseBadge(review: rev, compact: true)
                    Text(dueLabel(rev.dueDay))
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(rev.dueDay <= session.today ? Theme.red : Theme.ink)
                        .frame(width: 130, alignment: .trailing)
                }
                .padding(.vertical, 4).padding(.horizontal, 10)
                .background(Theme.bg, in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(.leading, 18)
    }

    private func dueLabel(_ day: String) -> String {
        let n = session.clock.days(from: session.today, to: day)
        if n < 0 { return "overdue \(-n)d" }
        if n == 0 { return "due today" }
        if n == 1 { return "tomorrow" }
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("d MMM")
        return "in \(n)d · " + (session.clock.date(day).map { f.string(from: $0) } ?? day)
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
                point("Revise first", "Clearing due cards in the morning keeps the backlog from growing; FSRS has already picked the right ones.")
                point("Evening review", "A short review before sleep helps memories settle overnight.")
                point("Time boxes and breaks", "5 minutes per Q&A and 20 per C program keeps you from over-polishing one card; take 10 minutes off after ~50 minutes of focus.")
                point("Interview or busy day", "Still do the revision (it's usually short), then move the day's tasks to tomorrow from each task's ⋯ menu.")
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
