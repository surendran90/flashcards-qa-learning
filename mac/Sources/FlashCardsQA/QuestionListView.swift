import FlashCardsCore
import SwiftUI
import UniformTypeIdentifiers

/// The selected category's questions and section dividers: drag to reorder, click a question to
/// see or edit the answer, double-click a divider to rename it, add and delete. Every change is
/// saved straight to the workbook.
struct QuestionListView: View {
    @Environment(StudySession.self) private var session
    let topic: String

    @State private var expanded = false
    @State private var openID: String?
    @State private var editingCard: Card?
    @State private var draftQ = ""
    @State private var draftA = ""
    @State private var saveTask: Task<Void, Never>?
    @State private var saving = false
    @State private var warning: String?
    @State private var adding = false
    @State private var newQ = ""
    @State private var newA = ""
    @State private var confirmDelete: Card?
    @State private var dropTarget: String?
    @State private var renamingDivider: SectionDivider?
    @State private var dividerDraft = ""
    /// Titles being saved, shown right away instead of the old name.
    @State private var pendingTitles: [String: String] = [:]
    @FocusState private var dividerFieldFocused: Bool

    private var items: [ListItem] { session.listItems(of: topic) }
    private var questionCount: Int { session.cardsInSheet(of: topic).count }
    private var sectionCount: Int { session.dividers.filter { $0.sheet == topic }.count }
    private var sheet: SheetInfo? { session.sheetInfo(for: topic) }
    private var fileName: String { session.sourceURL?.lastPathComponent ?? "the workbook" }
    private var canEdit: Bool { session.canEdit && sheet?.path != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.muted).frame(width: 14)
                    Text("Questions (\(questionCount))").font(.system(size: 15, weight: .bold))
                    if sectionCount > 0 {
                        Text("· \(sectionCount) section\(sectionCount == 1 ? "" : "s")")
                            .font(.system(size: 13)).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    if !session.editStatus.isEmpty {
                        Text(session.editStatus)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(session.editStatusIsError ? Theme.red : Theme.accent)
                            .lineLimit(2)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                Text(canEdit
                     ? "Drag ≡ to reorder questions and dividers. Click a question to see or edit its answer; double-click a divider to rename it. Changes save to \(fileName) automatically (backups are kept)."
                     : "\(fileName) is read-only here — only .xlsx workbooks can be edited from the app.")
                    .font(.system(size: 12)).foregroundStyle(Theme.muted)

                if items.isEmpty && !adding {
                    Text("No questions yet. Add the first one below.")
                        .font(.system(size: 13)).foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                }

                LazyVStack(spacing: 6) {
                    ForEach(numbered, id: \.item.id) { entry in
                        switch entry.item {
                        case .card(let card): row(number: entry.number, card: card)
                        case .divider(let divider): dividerRow(divider)
                        }
                    }
                }

                addSection
            }
        }
        .padding(20)
        .panel()
        .onAppear {
            if session.newlyCreatedCategory == topic {
                expanded = true
                adding = true
                session.newlyCreatedCategory = nil
            }
        }
        .confirmationDialog("Delete this question from \(fileName)?", isPresented: Binding(
            get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }), presenting: confirmDelete) { card in
            Button("Delete", role: .destructive) {
                Task {
                    if await session.save(.delete(card)) { openID = nil; editingCard = nil }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { card in
            Text("“\(card.question)” will be removed from the \(card.sourceSheet) sheet. A backup of the workbook is kept.")
        }
    }

    /// Items with question numbers (dividers don't take a number).
    private var numbered: [(item: ListItem, number: Int)] {
        var n = 0
        return items.map { item in
            if case .card = item { n += 1 }
            return (item, n)
        }
    }

    // MARK: Drag and drop

    private func dragHandle(_ id: String, preview: String) -> some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted)
            .frame(width: 16)
            .contentShape(Rectangle())
            .help("Drag to reorder")
            .draggable(id) {
                Text(preview).font(.system(size: 12, weight: .semibold)).padding(8)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 8))
            }
    }

    private func move(_ id: String, onto target: ListItem) {
        dropTarget = nil
        guard canEdit, let path = sheet?.path else { return }
        var list = items
        guard let from = list.firstIndex(where: { $0.id == id }),
              let to = list.firstIndex(where: { $0.id == target.id }), from != to else { return }
        let item = list.remove(at: from)
        list.insert(item, at: to)
        Task { await session.save(.reorder(sheetPath: path, rows: list.map(\.excelRow))) }
    }

    private func dropZone<V: View>(_ item: ListItem, _ content: V) -> some View {
        content.dropDestination(for: String.self) { ids, _ in
            guard let id = ids.first else { return false }
            move(id, onto: item)
            return true
        } isTargeted: { targeted in
            dropTarget = targeted ? item.id : (dropTarget == item.id ? nil : dropTarget)
        }
    }

    // MARK: Divider rows

    @ViewBuilder
    private func dividerRow(_ divider: SectionDivider) -> some View {
        let item = ListItem.divider(divider)
        let renaming = renamingDivider?.id == divider.id
        dropZone(item, HStack(spacing: 10) {
            dragHandle(item.id, preview: "§ " + divider.title)
            Rectangle().fill(Theme.accent.opacity(0.6)).frame(width: 18, height: 2)
            if renaming {
                TextField("Section name", text: $dividerDraft)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13, weight: .bold))
                    .frame(maxWidth: 360)
                    .focused($dividerFieldFocused)
                    .onSubmit { commitRename() }
                    .onExitCommand { renamingDivider = nil }
                    .onChange(of: dividerFieldFocused) { _, focused in if !focused { commitRename() } }
            } else {
                let shown = pendingTitles[divider.id] ?? divider.title
                Text(shown.isEmpty ? "Untitled section" : shown)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Theme.accent)
                    .help("Double-click to rename")
            }
            Rectangle().fill(Theme.accent.opacity(0.6)).frame(height: 2)
            if !renaming && canEdit {
                Menu {
                    Button("Rename") { beginRename(divider) }
                    Button("Delete divider", role: .destructive) {
                        if let sheet { Task { await session.save(.deleteDivider(divider, sheet: sheet)) } }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").foregroundStyle(Theme.muted)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
        .padding(.vertical, 8).padding(.horizontal, 12)
        .background(Theme.accentSoft.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(dropTarget == item.id ? Theme.accent : .clear, lineWidth: 2))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { if canEdit { beginRename(divider) } })
    }

    private func beginRename(_ divider: SectionDivider) {
        renamingDivider = divider
        dividerDraft = divider.title
        DispatchQueue.main.async { dividerFieldFocused = true }
    }

    private func commitRename() {
        guard let divider = renamingDivider else { return }
        renamingDivider = nil
        let title = dividerDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard title != divider.title, !title.isEmpty, let sheet else { return }
        pendingTitles[divider.id] = title
        Task {
            await session.save(.renameDivider(divider, sheet: sheet, title: title))
            pendingTitles[divider.id] = nil
        }
    }

    private func addDivider() {
        guard let sheet else { return }
        Task {
            if await session.save(.addDivider(sheet: sheet, title: "New section")),
               let created = session.dividers.filter({ $0.sheet == topic }).max(by: { $0.excelRow < $1.excelRow }) {
                beginRename(created)
            }
        }
    }

    // MARK: Question rows

    @ViewBuilder
    private func row(number: Int, card: Card) -> some View {
        let item = ListItem.card(card)
        let open = openID == card.id
        let isEditing = editingCard?.id == card.id
        dropZone(item, VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                dragHandle(item.id, preview: card.question)
                Text("\(number).").font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.muted)
                    .frame(width: 28, alignment: .trailing)
                Text(card.question)
                    .font(Theme.questionFont(topic, size: 13))
                    .lineLimit(open ? nil : 1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                statusChip(card)
            }
            .contentShape(Rectangle())
            .onTapGesture { toggle(card) }

            if open {
                if isEditing {
                    editor
                } else {
                    FormattedAnswer(text: card.answer.isEmpty ? "No answer yet." : card.answer)
                        .font(Theme.answerFont(topic, size: 13))
                        .foregroundStyle(card.answer.isEmpty ? Theme.muted : Theme.ink)
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 54)
                    HStack(spacing: 8) {
                        Button("✏️ Edit") { beginEditing(card) }
                            .buttonStyle(OutlineButtonStyle())
                        Button("🗑 Delete") { confirmDelete = card }
                            .buttonStyle(OutlineButtonStyle())
                    }
                    .disabled(!canEdit)
                    .padding(.leading, 54)
                }
            }
        }
        .padding(.vertical, 9).padding(.horizontal, 12)
        .background(open ? Theme.bg : Theme.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(dropTarget == item.id ? Theme.accent : Theme.border, lineWidth: dropTarget == item.id ? 2 : 1)))
    }

    private func statusChip(_ card: Card) -> some View {
        let status = SpacedRepetition.status(session.review(for: card))
        let color: Color = status == .mastered ? Theme.accent : status == .learning ? Theme.red : Theme.muted
        return Text(status.label)
            .font(.system(size: 10, weight: .bold)).foregroundStyle(color)
            .padding(.vertical, 2).padding(.horizontal, 7)
            .background(color.opacity(0.12), in: Capsule())
    }

    // MARK: Editing

    private var editor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("QUESTION").font(.system(size: 10, weight: .bold)).kerning(1).foregroundStyle(Theme.muted)
            TextField("Question", text: $draftQ, axis: .vertical)
                .font(Theme.questionFont(topic, size: 13))
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
            Text("ANSWER").font(.system(size: 10, weight: .bold)).kerning(1).foregroundStyle(Theme.muted)
            AnswerEditor(text: $draftA, topic: topic)
            if let warning {
                Text(warning).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.red)
            }
            HStack {
                Text(saving ? "Saving…" : "Saves automatically as you type.")
                    .font(.system(size: 11)).foregroundStyle(Theme.muted)
                Spacer()
                Button("Done") { finishEditing() }
                    .buttonStyle(FilledButtonStyle(color: Theme.accent))
                    .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(.leading, 54)
        .onChange(of: draftQ) { scheduleSave() }
        .onChange(of: draftA) { scheduleSave() }
    }

    private func toggle(_ card: Card) {
        if editingCard != nil { finishEditing() }
        openID = openID == card.id ? nil : card.id
    }

    private func beginEditing(_ card: Card) {
        editingCard = card
        draftQ = card.question
        draftA = card.answer
        warning = nil
    }

    private func finishEditing() {
        saveTask?.cancel()
        Task {
            await saveDraft()
            editingCard = nil
        }
    }

    private func scheduleSave() {
        guard editingCard != nil else { return }
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            await saveDraft()
        }
    }

    /// Saves the editor's text if it changed; keeps the editor pointed at the reloaded card.
    private func saveDraft() async {
        guard let card = editingCard, !saving else { return }
        let q = draftQ.trimmingCharacters(in: .whitespacesAndNewlines)
        let a = FormattedText.trimmed(draftA)
        guard q != card.question || a != card.answer else { return }
        guard !q.isEmpty else { warning = "The question can't be empty."; return }
        guard SectionDivider.title(of: q) == nil else { warning = "Questions can't start with ## (that marks a divider)."; return }
        guard !session.isDuplicate(q, excluding: card) else {
            warning = "Another card already has this question, so it wasn't saved."
            return
        }
        warning = nil
        saving = true
        let ok = await session.save(.update(card, question: q, answer: a))
        saving = false
        if ok, let reloaded = session.cards.first(where: { $0.id == card.id }) {
            if editingCard?.id == card.id { editingCard = reloaded }
            openID = reloaded.id
        }
    }

    // MARK: Adding

    @ViewBuilder
    private var addSection: some View {
        if adding {
            VStack(alignment: .leading, spacing: 8) {
                Text("NEW QUESTION").font(.system(size: 10, weight: .bold)).kerning(1).foregroundStyle(Theme.muted)
                TextField("Question", text: $newQ, axis: .vertical)
                    .font(Theme.questionFont(topic, size: 13))
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                AnswerEditor(text: $newA, topic: topic, minHeight: 110)
                if let warning, editingCard == nil {
                    Text(warning).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.red)
                }
                HStack {
                    Button("Cancel") { adding = false; newQ = ""; newA = ""; warning = nil }
                        .buttonStyle(OutlineButtonStyle())
                    Spacer()
                    Button("＋ Add to \(topic)") { Task { await addQuestion() } }
                        .buttonStyle(FilledButtonStyle(color: Theme.accent))
                        .disabled(newQ.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || saving)
                        .keyboardShortcut(.return, modifiers: .command)
                }
            }
            .padding(12)
            .background(Theme.bg, in: RoundedRectangle(cornerRadius: 10))
        } else {
            HStack(spacing: 8) {
                Button("＋ Add question") { adding = true; warning = nil }
                    .buttonStyle(OutlineButtonStyle())
                Button("＋ Divider") { addDivider() }
                    .buttonStyle(OutlineButtonStyle())
                    .help("Add a section divider at the end; drag it where you want it and double-click to rename")
            }
            .disabled(!canEdit)
        }
    }

    private func addQuestion() async {
        guard let sheet else { return }
        let q = newQ.trimmingCharacters(in: .whitespacesAndNewlines)
        let a = FormattedText.trimmed(newA)
        guard SectionDivider.title(of: q) == nil else {
            warning = "Questions can't start with ## (that marks a divider). Use ＋ Divider instead."
            return
        }
        guard !session.isDuplicate(q) else {
            warning = "Another card already has this question."
            return
        }
        saving = true
        let ok = await session.save(.add(sheet: sheet, question: q, answer: a))
        saving = false
        if ok {
            adding = false
            newQ = ""
            newA = ""
            warning = nil
            let key = CardKey.make(q)
            openID = session.cards.first { $0.key == key }?.id
        }
    }
}
