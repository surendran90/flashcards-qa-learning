import FlashCardsCore
import SwiftUI
import UniformTypeIdentifiers

/// The selected category's questions: drag to reorder, click to see or edit the answer,
/// add and delete. Every change is saved straight to the workbook.
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

    private var questions: [Card] { session.cardsInSheet(of: topic) }
    private var fileName: String { session.sourceURL?.lastPathComponent ?? "the workbook" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.muted).frame(width: 14)
                    Text("Questions (\(questions.count))").font(.system(size: 15, weight: .bold))
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
                Text(session.canEdit
                     ? "Drag ≡ to reorder. Click a question to see its answer or edit it. Changes save to \(fileName) automatically (backups are kept)."
                     : "\(fileName) is read-only here — only .xlsx workbooks can be edited from the app.")
                    .font(.system(size: 12)).foregroundStyle(Theme.muted)

                LazyVStack(spacing: 6) {
                    ForEach(Array(questions.enumerated()), id: \.element.id) { index, card in
                        row(index: index, card: card)
                    }
                }

                addSection
            }
        }
        .padding(20)
        .panel()
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

    // MARK: Rows

    @ViewBuilder
    private func row(index: Int, card: Card) -> some View {
        let open = openID == card.id
        let isEditing = editingCard?.id == card.id
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted)
                    .frame(width: 16)
                    .contentShape(Rectangle())
                    .help("Drag to reorder")
                    .draggable(card.key) {
                        Text(card.question).font(.system(size: 12, weight: .semibold)).padding(8)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 8))
                    }
                Text("\(index + 1).").font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.muted)
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
                    Text(card.answer.isEmpty ? "No answer yet." : card.answer)
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
                    .disabled(!session.canEdit)
                    .padding(.leading, 54)
                }
            }
        }
        .padding(.vertical, 9).padding(.horizontal, 12)
        .background(open ? Theme.bg : Theme.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(dropTarget == card.key ? Theme.accent : Theme.border, lineWidth: dropTarget == card.key ? 2 : 1))
        .dropDestination(for: String.self) { items, _ in
            guard let key = items.first else { return false }
            move(key, onto: card)
            return true
        } isTargeted: { targeted in
            dropTarget = targeted ? card.key : (dropTarget == card.key ? nil : dropTarget)
        }
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
            TextEditor(text: $draftA)
                .font(Theme.answerFont(topic, size: 13))
                .frame(minHeight: 140)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))
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
        if openID == card.id {
            if editingCard != nil { finishEditing() }
            openID = nil
        } else {
            if editingCard != nil { finishEditing() }
            openID = card.id
        }
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
        let a = draftA.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q != card.question || a != card.answer else { return }
        guard !q.isEmpty else { warning = "The question can't be empty."; return }
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
                TextEditor(text: $newA)
                    .font(Theme.answerFont(topic, size: 13))
                    .frame(minHeight: 110)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))
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
            Button("＋ Add question") { adding = true; warning = nil }
                .buttonStyle(OutlineButtonStyle())
                .disabled(!session.canEdit || questions.isEmpty)
        }
    }

    private func addQuestion() async {
        guard let template = questions.last else { return }
        let q = newQ.trimmingCharacters(in: .whitespacesAndNewlines)
        let a = newA.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !session.isDuplicate(q) else {
            warning = "Another card already has this question."
            return
        }
        saving = true
        let ok = await session.save(.add(template: template, question: q, answer: a))
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

    // MARK: Reordering

    private func move(_ key: String, onto target: Card) {
        dropTarget = nil
        var list = questions
        guard let from = list.firstIndex(where: { $0.key == key }),
              let to = list.firstIndex(where: { $0.id == target.id }), from != to else { return }
        let item = list.remove(at: from)
        list.insert(item, at: to)
        Task { await session.save(.reorder(list)) }
    }
}
