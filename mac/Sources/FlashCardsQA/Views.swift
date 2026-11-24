import AppKit
import FlashCardsCore
import SwiftUI
import UniformTypeIdentifiers

private let categoryIcons = ["Resume QA": "📄", "Embedded QA": "⚙️"]

struct ContentView: View {
    @Environment(StudySession.self) private var session

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HeaderView()
                CategoryChips().padding(.bottom, 20)
                if !session.status.isEmpty { StatusBanner().padding(.bottom, 16) }
                switch session.mode {
                case .start: StartView()
                case .study: StudyView()
                case .running: PracticeView()
                case .done: ResultsView()
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
    }
}

// MARK: - Header

struct HeaderView: View {
    @Environment(StudySession.self) private var session

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
        HStack(spacing: 9) {
            Text(session.loading ? "Loading workbook…" : "\(session.cards.count) questions loaded")
                .font(.system(size: 13)).foregroundStyle(Theme.muted)
            Button("📂 Import Excel") { openImportPanel(session) }
                .buttonStyle(OutlineButtonStyle())
            Button(session.loading ? "↻ Refreshing…" : "↻ Refresh") { Task { await session.refresh() } }
                .buttonStyle(OutlineButtonStyle())
                .disabled(session.loading)
        }
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
                .font(.system(size: 19, weight: .bold)).lineSpacing(5)
                .multilineTextAlignment(centered ? .center : .leading)
                .textSelection(.enabled)
            if showAnswer {
                VStack(alignment: .leading, spacing: 8) {
                    Divider().overlay(Theme.border).padding(.bottom, 12)
                    Text("ANSWER").font(.system(size: 11, weight: .bold)).kerning(1).foregroundStyle(Theme.muted)
                    if card.answer.isEmpty {
                        Text("No answer provided.").italic().foregroundStyle(Theme.muted)
                    } else {
                        Text(card.answer).font(.system(size: 14)).lineSpacing(6).textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 22)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 175, alignment: centered ? .top : .topLeading)
        .padding(30)
        .panel(radius: 18)
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
                    Button("Next →") { session.next() }
                        .buttonStyle(FilledButtonStyle(color: Theme.accent))
                        .disabled(session.index == session.deck.count - 1)
                        .keyboardShortcut(.rightArrow, modifiers: [])
                }
                .padding(.top, 17)
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
                        Button("✅ I knew it") { session.answer(true) }
                            .buttonStyle(FilledButtonStyle(color: Theme.accent))
                            .keyboardShortcut("k", modifiers: [])
                        Button("❌ Practice again") { session.answer(false) }
                            .buttonStyle(FilledButtonStyle(color: Theme.red))
                            .keyboardShortcut("p", modifiers: [])
                    }
                }
                .padding(.top, 17)
                if !session.flipped {
                    Button("Skip") { session.skip() }
                        .buttonStyle(LinkButtonStyle(underline: true))
                        .keyboardShortcut("s", modifiers: [])
                        .padding(.top, 12)
                }
                Text(session.flipped ? "Shortcuts: K knew it · P practice again" : "Shortcuts: Space reveal · S skip · Esc end")
                    .font(.system(size: 11)).foregroundStyle(Theme.muted.opacity(0.8)).padding(.top, 14)
            }
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
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
                Text("\(session.knewCount) knew · \(missed.count) to practice · \(session.deck.count) total")
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

            ForEach(missed) { card in
                VStack(alignment: .leading, spacing: 7) {
                    Text(card.topic).font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.red)
                    Text(card.question).font(.system(size: 14, weight: .bold))
                    Text(card.answer.isEmpty ? "No answer provided." : card.answer)
                        .font(.system(size: 13)).foregroundStyle(Theme.muted).lineSpacing(4)
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
        }
        .formStyle(.grouped)
        .frame(width: 560)
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
