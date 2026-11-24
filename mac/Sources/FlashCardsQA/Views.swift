import AppKit
import FlashCardsCore
import SwiftUI
import UniformTypeIdentifiers

private let categoryIcons = ["Resume QA": "📄", "Embedded QA": "⚙️"]

struct ContentView: View {
    @Environment(StudySession.self) private var session
    @Environment(CardTimer.self) private var timer

    /// The card whose timer is shown: only in Study and Practice.
    private var timedCard: Card? {
        session.mode == .study || session.mode == .running ? session.current : nil
    }
    private var timedCardID: String? { timedCard.map { "\($0.id)-\(session.mode == .study)" } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HeaderView()
                CategoryChips().padding(.bottom, 20)
                if !session.status.isEmpty { StatusBanner().padding(.bottom, 16) }
                BreakNudge()
                switch session.mode {
                case .start: StartView()
                case .study: StudyView()
                case .running: PracticeView()
                case .done: ResultsView()
                case .plan: PlanView()
                }
            }
            .frame(maxWidth: 1000)
            .padding(.horizontal, 26)
            .padding(.top, 30)
            .padding(.bottom, 60)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.bg)
        .foregroundStyle(Theme.ink)
        .frame(minWidth: 820, minHeight: 600)
        .task { await session.refresh() }
        .onChange(of: timedCardID, initial: true) { timer.show(timedCard) }
    }
}

// MARK: - Header

struct HeaderView: View {
    @Environment(StudySession.self) private var session
    @Environment(CardTimer.self) private var timer

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center) { title; Spacer(minLength: 16); actions }
            VStack(alignment: .leading, spacing: 14) { title; actions }
        }
        .padding(.bottom, 26)
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("STUDY AND PRACTICE").font(.system(size: 11)).kerning(2).foregroundStyle(Theme.muted)
            Text("💬 FlashCard Q/A Bank").font(.system(size: 30, weight: .bold))
            Text("Study questions and answers, or practice with flashcards.")
                .font(.system(size: 14)).foregroundStyle(Theme.muted)
        }
    }

    private var actions: some View {
        VStack(alignment: .trailing, spacing: 7) {
            HStack(spacing: 9) {
                Button("🗓 Study Plan") { session.openPlan() }
                    .buttonStyle(OutlineButtonStyle())
                Button("📂 Import Excel") { openImportPanel(session) }
                    .buttonStyle(OutlineButtonStyle())
                Button(session.loading ? "↻ Refreshing…" : "↻ Refresh") { Task { await session.refresh() } }
                    .buttonStyle(OutlineButtonStyle())
                    .disabled(session.loading)
            }
            Text((session.loading ? "Loading workbook…" : "\(session.cards.count) questions loaded")
                 + " · Today: \(Durations.short(timer.todayTotal)) studied")
                .font(.system(size: 12)).foregroundStyle(Theme.muted)
        }
        .lineLimit(1)
        .fixedSize()
    }
}

@MainActor
func openImportPanel(_ session: StudySession) {
    let panel = NSOpenPanel()
    panel.title = "Import Excel workbook"
    panel.allowedContentTypes = [
        UTType(filenameExtension: "xlsx"), UTType(filenameExtension: "xls"),
    ].compactMap { $0 }
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    if panel.runModal() == .OK, let url = panel.url {
        Task { await session.importWorkbook(url: url) }
    }
}

struct StatusBanner: View {
    @Environment(StudySession.self) private var session

    var body: some View {
        Text(session.status)
            .font(.system(size: 13))
            .foregroundStyle(session.statusIsError ? Theme.red : Theme.accent)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10).padding(.horizontal, 14)
            .background(session.statusIsError ? Theme.redSoft : Theme.accentSoft, in: RoundedRectangle(cornerRadius: 10))
            .textSelection(.enabled)
    }
}

// MARK: - Categories

struct CategoryChips: View {
    @Environment(StudySession.self) private var session

    var body: some View {
        FlowLayout(spacing: 7) {
            ForEach(["All"] + session.categories, id: \.self) { item in
                let active = session.topic == item
                Button {
                    session.setFilter(item)
                } label: {
                    Text(item == "All" ? item : "\(item) · \(session.count(for: item))")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(active ? .white : Theme.muted)
                        .padding(.vertical, 7).padding(.horizontal, 13)
                        .background(active ? Theme.accent : Theme.card, in: Capsule())
                        .overlay(Capsule().stroke(active ? Theme.accent : Theme.border))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct StartView: View {
    @Environment(StudySession.self) private var session

    var body: some View {
        @Bindable var session = session
        VStack(alignment: .leading, spacing: 18) {
            let todayLeft = session.todayRemaining
            if !session.cards.isEmpty && (todayLeft.new + todayLeft.review > 0) {
                Button { session.openPlan() } label: {
                    HStack(spacing: 8) {
                        Text("📌")
                        Text("Today's plan: \(todayLeft.new) new to learn · \(todayLeft.review) to revise")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Text("Open Study Plan →").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.accent)
                    }
                    .padding(.vertical, 11).padding(.horizontal, 16)
                    .panel(radius: 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if session.topic == "All" && !session.categories.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 165), spacing: 12)], spacing: 12) {
                    ForEach(session.categories, id: \.self) { item in
                        Button { session.setFilter(item) } label: {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(categoryIcons[item] ?? "📚").font(.system(size: 24))
                                Text(item).font(.system(size: 13, weight: .bold)).padding(.top, 9).padding(.bottom, 5)
                                Text("\(session.count(for: item))").font(.system(size: 21, weight: .heavy)).foregroundStyle(Theme.accent)
                                Text("questions").font(.system(size: 11)).foregroundStyle(Theme.muted)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 16).padding(.horizontal, 17)
                            .panel(radius: 14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 18) { summary; Spacer(minLength: 0); controls }
                VStack(alignment: .leading, spacing: 16) { summary; controls }
            }
            .padding(24)
            .panel()

            if session.topic != "All" {
                QuestionListView(topic: session.topic).id(session.topic)
            }

            if session.cards.isEmpty && !session.loading {
                Text("The app loads the configured OneDrive workbook on launch. It imports tabs whose cell A1 contains “QA”; use Refresh after editing that workbook.")
                    .font(.system(size: 14)).foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)
            }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(session.topic == "All" ? "All Categories" : session.topic).font(.system(size: 17, weight: .bold))
            (Text("\(session.practiceCount)").bold().foregroundStyle(Theme.accent)
                + Text(" questions ready")
                + Text(session.topic == "All" ? "" : " · \(session.filtered.count) available"))
                .foregroundStyle(Theme.muted)
        }
    }

    private var controls: some View {
        @Bindable var session = session
        return HStack(spacing: 14) {
            if session.topic != "All" {
                HStack(spacing: 8) {
                    Text("Question range").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted)
                    rangeField("From", text: $session.rangeFrom)
                    rangeField("To", text: $session.rangeTo)
                    Text(session.rangeValid ? "Inclusive" : "Enter 1–\(session.filtered.count), with From ≤ To")
                        .font(.system(size: 11))
                        .foregroundStyle(session.rangeValid ? Theme.muted : Theme.red)
                }
            }
            Toggle("🔀 Shuffle", isOn: $session.shuffle)
                .toggleStyle(.checkbox).font(.system(size: 13)).foregroundStyle(Theme.muted)
            Button("📖 Study") { session.startStudy() }
                .buttonStyle(FilledButtonStyle(color: Theme.inkButton))
                .disabled(!session.canStart)
            Button("▶ Start Practice") { session.start(retryWrong: false) }
                .buttonStyle(FilledButtonStyle(color: Theme.accent))
                .disabled(!session.canStart)
                .keyboardShortcut(.defaultAction)
        }
        .fixedSize()
    }

    private func rangeField(_ label: String, text: Binding<String>) -> some View {
        HStack(spacing: 5) {
            Text(label).font(.system(size: 12)).foregroundStyle(Theme.muted)
            TextField(label, text: text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 58)
                .accessibilityLabel("\(label) question number")
        }
    }
}

// MARK: - Cards

private struct ProgressBar: View {
    var fraction: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.border)
                Capsule().fill(Theme.accent).frame(width: geo.size.width * max(0, min(1, fraction)))
            }
        }
        .frame(height: 6)
        .animation(.easeOut(duration: 0.2), value: fraction)
    }
}

private struct CardView: View {
    var card: Card
    var showAnswer: Bool
    var centered: Bool

    var body: some View {
        VStack(alignment: centered ? .center : .leading, spacing: 0) {
            Text(card.topic)
                .font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.accent)
                .padding(.vertical, 5).padding(.horizontal, 11)
                .background(Theme.accentSoft, in: Capsule())
                .padding(.bottom, 18)
            Text(card.question)
                .font(Theme.questionFont(card.topic)).lineSpacing(5)
                .multilineTextAlignment(centered ? .center : .leading)
                .textSelection(.enabled)
            if showAnswer {
                VStack(alignment: .leading, spacing: 8) {
                    Divider().overlay(Theme.border).padding(.bottom, 12)
                    Text("ANSWER").font(.system(size: 11, weight: .bold)).kerning(1).foregroundStyle(Theme.muted)
                    if card.answer.isEmpty {
                        Text("No answer provided.").italic().foregroundStyle(Theme.muted)
                    } else {
                        Text(card.answer).font(Theme.answerFont(card.topic)).lineSpacing(6).textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 22)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 175, alignment: centered ? .top : .topLeading)
        .padding(30)
        .panel(radius: 18)
        .overlay(alignment: .topTrailing) { CardTimerView().padding(14) }
        .shadow(color: .black.opacity(0.05), radius: 14, y: 8)
    }
}

struct StudyView: View {
    @Environment(StudySession.self) private var session

    var body: some View {
        if let card = session.current {
            VStack(spacing: 0) {
                HStack {
                    Text("Card \(session.index + 1) / \(session.deck.count)")
                    Spacer()
                    Button("Back to categories") { session.reset() }
                        .buttonStyle(LinkButtonStyle()).keyboardShortcut(.cancelAction)
                }
                .font(.system(size: 13)).foregroundStyle(Theme.muted).padding(.bottom, 10)
                ProgressBar(fraction: Double(session.index + 1) / Double(session.deck.count)).padding(.bottom, 18)
                CardView(card: card, showAnswer: true, centered: false)
                HStack {
                    Button("← Previous") { session.previous() }
                        .buttonStyle(FilledButtonStyle(color: Theme.inkButton))
                        .disabled(session.index == 0)
                        .keyboardShortcut(.leftArrow, modifiers: [])
                    Spacer()
                    if session.review(for: card) == nil {
                        Button("✓ Already studied") { session.markAlreadyStudied() }
                            .buttonStyle(OutlineButtonStyle())
                            .keyboardShortcut("a", modifiers: [])
                            .help("You know this card already: it skips today's test and comes back for review in about 16 days (A)")
                    }
                    if session.index == session.deck.count - 1 {
                        // Retrieval practice: finish a study pass by testing yourself.
                        Button("✍️ Test yourself on these (\(session.deck.count))") { session.testStudiedCards() }
                            .buttonStyle(FilledButtonStyle(color: Theme.accent))
                            .keyboardShortcut(.rightArrow, modifiers: [])
                    } else {
                        Button("Next →") { session.next() }
                            .buttonStyle(FilledButtonStyle(color: Theme.accent))
                            .keyboardShortcut(.rightArrow, modifiers: [])
                    }
                }
                .padding(.top, 17)
                if session.studyingNewCards {
                    Text("New cards join your review schedule once you test yourself on them.")
                        .font(.system(size: 11)).foregroundStyle(Theme.muted).padding(.top, 12)
                }
            }
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
    }
}

struct PracticeView: View {
    @Environment(StudySession.self) private var session

    var body: some View {
        @Bindable var session = session
        if let card = session.current {
            VStack(spacing: 0) {
                HStack {
                    Text("Question \(session.index + 1) / \(session.deck.count)")
                    Spacer()
                    Text("✅ \(session.knewCount)　❌ \(session.missedCount)")
                    Spacer()
                    Button("End practice") { session.reset() }
                        .buttonStyle(LinkButtonStyle()).keyboardShortcut(.cancelAction)
                }
                .font(.system(size: 13)).foregroundStyle(Theme.muted).padding(.bottom, 10)
                ProgressBar(fraction: Double(session.index) / Double(session.deck.count)).padding(.bottom, 18)
                CardView(card: card, showAnswer: session.flipped, centered: true)
                HStack(spacing: 10) {
                    if !session.flipped {
                        Button("👁 Reveal Answer") { session.flipped = true }
                            .buttonStyle(FilledButtonStyle(color: Theme.accent))
                            .keyboardShortcut(.space, modifiers: [])
                    } else {
                        let preview = session.ratingPreview
                        ForEach(Rating.allCases, id: \.self) { rating in
                            Button { session.answer(rating) } label: {
                                VStack(spacing: 2) {
                                    Text("\(rating.emoji) \(rating.label)")
                                    Text(preview[rating].map { rating == .again ? "<\($0)d" : FSRS.intervalLabel($0) } ?? "")
                                        .font(.system(size: 11, weight: .semibold)).opacity(0.85)
                                }
                                .frame(minWidth: 70)
                            }
                            .buttonStyle(FilledButtonStyle(color: color(rating)))
                            .keyboardShortcut(KeyEquivalent(Character(String(rating.rawValue))), modifiers: [])
                        }
                    }
                }
                .padding(.top, 17)
                // Old shortcuts still work: K = Good, P = Again.
                .background {
                    if session.flipped {
                        Button("") { session.answer(.good) }.keyboardShortcut("k", modifiers: []).opacity(0)
                        Button("") { session.answer(.again) }.keyboardShortcut("p", modifiers: []).opacity(0)
                    }
                }
                if session.flipped && !session.isScheduled(card), let due = session.review(for: card)?.dueDay {
                    Text("Practice only — this card isn't due until \(due), so your rating won't change its schedule.")
                        .font(.system(size: 12)).foregroundStyle(Theme.muted).padding(.top, 10)
                }
                if !session.flipped && card.topic.lowercased().contains("program") {
                    Text("✍️ Write the code on paper (or in an editor) first, then reveal and compare.")
                        .font(.system(size: 12)).foregroundStyle(Theme.accent).padding(.top, 12)
                }
                if !session.flipped {
                    Button("Skip") { session.skip() }
                        .buttonStyle(LinkButtonStyle(underline: true))
                        .keyboardShortcut("s", modifiers: [])
                        .padding(.top, 12)
                }
                Text(session.flipped ? "How well did you recall it? Keys 1 Again · 2 Hard · 3 Good · 4 Easy — the time under each is when you'll see it next."
                                     : "Shortcuts: Space reveal · S skip · Esc end")
                    .multilineTextAlignment(.center)
                    .font(.system(size: 11)).foregroundStyle(Theme.muted.opacity(0.8)).padding(.top, 14)
            }
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
    }

    private func color(_ rating: Rating) -> Color {
        switch rating {
        case .again: return Theme.red
        case .hard: return Color(red: 0.85, green: 0.55, blue: 0.2)
        case .good: return Theme.accent
        case .easy: return Color(red: 0.25, green: 0.5, blue: 0.85)
        }
    }
}

struct ResultsView: View {
    @Environment(StudySession.self) private var session

    var body: some View {
        let missed = session.missedCards
        let total = max(session.deck.count, 1)
        let score = Int((Double(session.knewCount) / Double(total) * 100).rounded())
        VStack(spacing: 9) {
            VStack(spacing: 8) {
                Text(score >= 80 ? "🏆" : score >= 60 ? "💪" : "📚").font(.system(size: 40))
                Text("\(score)%").font(.system(size: 34, weight: .heavy)).foregroundStyle(Theme.accent)
                Text("\(session.knewCount) recalled · \(session.shakyCards.count) shaky · \(missed.count) forgot · \(session.deck.count) total")
                    .foregroundStyle(Theme.muted)
                HStack(spacing: 9) {
                    if !missed.isEmpty {
                        Button("🔁 Retry missed (\(missed.count))") { session.start(retryWrong: true) }
                            .buttonStyle(FilledButtonStyle(color: Theme.red))
                    }
                    Button("↻ Restart") { session.start(retryWrong: false) }
                        .buttonStyle(FilledButtonStyle(color: Theme.accent))
                    Button("Back to categories") { session.reset() }
                        .buttonStyle(FilledButtonStyle(color: Theme.subtle, foreground: Theme.muted))
                        .keyboardShortcut(.cancelAction)
                }
                .padding(.top, 6)
            }
            .frame(maxWidth: .infinity)
            .padding(30)
            .panel(radius: 18)
            .padding(.bottom, 9)

            ForEach(missed + session.shakyCards) { card in
                let shaky = session.results[card.id] == .hard
                VStack(alignment: .leading, spacing: 7) {
                    Text((shaky ? "😬 Shaky · " : "❌ Forgot · ") + card.topic)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(shaky ? Color(red: 0.85, green: 0.55, blue: 0.2) : Theme.red)
                    Text(card.question).font(Theme.questionFont(card.topic, size: 14))
                    Text(card.answer.isEmpty ? "No answer provided." : card.answer)
                        .font(Theme.answerFont(card.topic, size: 13))
                        .foregroundStyle(Theme.muted).lineSpacing(4)
                }
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(15)
                .panel(radius: 12)
            }
        }
        .frame(maxWidth: 700)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Settings

struct SettingsView: View {
    @AppStorage(StudySession.folderKey) private var folder = ""
    @Environment(StudySession.self) private var session
    @Environment(ProgressStore.self) private var store

    private func slotTime(_ index: Int, _ path: WritableKeyPath<StudySlot, Int>) -> Binding<Date> {
        Binding(
            get: {
                let minute = store.data.slots[index][keyPath: path]
                return Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                store.data.slots[index][keyPath: path] = (c.hour ?? 0) * 60 + (c.minute ?? 0)
                session.onPlanChanged?()
            })
    }

    private func slotBinding<V>(_ index: Int, _ path: WritableKeyPath<StudySlot, V>) -> Binding<V> {
        Binding(
            get: { store.data.slots[index][keyPath: path] },
            set: { store.data.slots[index][keyPath: path] = $0; session.onPlanChanged?() })
    }

    private func minutes(_ category: String) -> Binding<Int> {
        Binding(
            get: { CardTiming.minutes(for: category, overrides: store.data.categoryMinutes) },
            set: { store.data.categoryMinutes[category] = $0 })
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Workbook folder") {
                    Text(folder.isEmpty ? WorkbookLoader.defaultFolder : folder)
                        .lineLimit(3).truncationMode(.middle).textSelection(.enabled)
                        .frame(maxWidth: 380, alignment: .leading)
                }
                HStack {
                    Button("Choose Folder…") { chooseFolder() }
                    Button("Use Default") { folder = ""; Task { await session.refresh() } }
                        .disabled(folder.isEmpty)
                }
            } footer: {
                Text("The app looks for InterviewPrepare.xlsx (or Interview Prepare.xlsx) in this folder. It only reads the workbook and never writes to it.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section {
                ForEach(store.data.slots.indices, id: \.self) { i in
                    let slot = store.data.slots[i]
                    HStack(spacing: 10) {
                        Toggle("", isOn: slotBinding(i, \.enabled)).labelsHidden()
                        Text("\(slot.emoji) \(slot.name)").frame(width: 110, alignment: .leading)
                        DatePicker("", selection: slotTime(i, \.start), displayedComponents: .hourAndMinute).labelsHidden()
                        Text("–")
                        DatePicker("", selection: slotTime(i, \.end), displayedComponents: .hourAndMinute).labelsHidden()
                        Picker("", selection: slotBinding(i, \.focus)) {
                            ForEach(SlotFocus.allCases, id: \.self) { Text($0.label).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 190)
                    }
                    .disabled(false)
                    .opacity(slot.enabled ? 1 : 0.5)
                }
                HStack {
                    Button("Rebuild today's targets") { session.rebuildToday() }
                    Button("Reset to defaults") {
                        store.data.slots = StudySlot.defaults
                        session.onPlanChanged?()
                    }
                }
            } header: {
                Text("Daily sessions")
            } footer: {
                Text("Targets are planned when the day starts. After changing sessions, use Rebuild today's targets to re-plan today.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section {
                Stepper("Remind me \(store.data.notifyLeadMinutes) min before each session",
                        value: Binding(get: { store.data.notifyLeadMinutes },
                                       set: { store.data.notifyLeadMinutes = $0; session.onPlanChanged?() }),
                        in: 0...60, step: 5)
            } header: {
                Text("Reminders")
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Target recall: \(Int((store.data.desiredRetention * 100).rounded()))%")
                    Slider(value: Binding(get: { store.data.desiredRetention },
                                          set: { store.data.desiredRetention = ($0 * 100).rounded() / 100; session.onPlanChanged?() }),
                           in: 0.80...0.97, step: 0.01)
                }
            } header: {
                Text("Memory (FSRS)")
            } footer: {
                Text("FSRS schedules each review for when your chance of recalling the card falls to this level. Higher means more reviews and better recall; 90% is the recommended default.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section {
                if session.categories.isEmpty {
                    Text("Load a workbook to set time per category.").foregroundStyle(.secondary)
                }
                ForEach(session.categories, id: \.self) { category in
                    Stepper("\(category): \(CardTiming.minutes(for: category, overrides: store.data.categoryMinutes)) min",
                            value: minutes(category), in: 1...60)
                }
            } header: {
                Text("Card timer")
            } footer: {
                Text("Time box per card. Defaults: 20 min for program categories, 5 min for Q&A.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Saved progress") {
                    Text(store.fileURL.path)
                        .lineLimit(2).truncationMode(.middle).textSelection(.enabled)
                        .frame(maxWidth: 380, alignment: .leading)
                }
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([store.fileURL]) }
            } footer: {
                Text("Study time, timer state and review schedules are kept here, separate from your workbook.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 700, height: 640)
        .padding(.vertical, 8)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = URL(fileURLWithPath: folder.isEmpty ? WorkbookLoader.defaultFolder : folder)
        if panel.runModal() == .OK, let url = panel.url {
            folder = url.path
            Task { await session.refresh() }
        }
    }
}

// MARK: - Layout

/// Wrapping horizontal layout for the category chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for i in row.indices {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row { var indices: [Int] = []; var y: CGFloat = 0; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for (i, sub) in subviews.enumerated() {
            let size = sub.sizeThatFits(.unspecified)
            let needed = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if needed > width && !row.indices.isEmpty {
                rows.append(row)
                row = Row(y: row.y + row.height + spacing)
            }
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(i)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}
