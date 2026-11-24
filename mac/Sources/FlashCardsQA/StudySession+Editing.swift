import FlashCardsCore
import Foundation

/// A change to the workbook from the question list.
enum EditOp: Sendable {
    case update(Card, question: String, answer: String)
    case add(template: Card, question: String, answer: String)
    case reorder([Card])
    case delete(Card)
}

extension StudySession {
    var canEdit: Bool { sourceURL?.pathExtension.lowercased() == "xlsx" }
    var backupFolder: URL { progress.fileURL.deletingLastPathComponent().appendingPathComponent("backups", isDirectory: true) }
    var isWaitingForExcel: Bool { pendingEdit != nil }

    /// Whether another card already has this question (questions must be unique).
    func isDuplicate(_ question: String, excluding card: Card? = nil) -> Bool {
        let key = CardKey.make(question)
        return cards.contains { $0.key == key && $0.id != card?.id }
    }

    func cardsInSheet(of topic: String) -> [Card] { cards.filter { $0.topic == topic } }

    /// Saves one change to the workbook, reloads it, and updates the study plan.
    @discardableResult
    func save(_ op: EditOp) async -> Bool {
        guard let url = sourceURL, canEdit else {
            setEditStatus("This workbook can't be edited from the app (only .xlsx files can).", error: true)
            return false
        }
        if let pending = pendingEdit {
            // While waiting for Excel, only newer text for the same card replaces the queued save.
            if case .update(let a, _, _) = pending, case .update(let b, _, _) = op, a.id == b.id {
                pendingEdit = op
            } else {
                setEditStatus("\(url.lastPathComponent) is open in Excel. Close it there first; your earlier change is waiting to be saved.", error: true)
            }
            return false
        }
        setEditStatus("Saving…")
        let backups = backupFolder
        do {
            try await Task.detached { try Self.write(op, to: url, backups: backups) }.value
            if case .update(let card, let question, _) = op {
                progress.data.renameCard(from: card.key, to: CardKey.make(question))
            }
            await reloadAfterEdit(url)
            setEditStatus("Saved to \(url.lastPathComponent) ✓")
            return true
        } catch let error as WorkbookWriterError {
            if case .locked = error {
                pendingEdit = op
                startRetry(url)
            }
            setEditStatus(error.localizedDescription, error: true)
            return false
        } catch {
            setEditStatus("Couldn't save: \(error.localizedDescription)", error: true)
            return false
        }
    }

    nonisolated static func write(_ op: EditOp, to url: URL, backups: URL) throws {
        switch op {
        case .update(let card, let q, let a):
            guard let sheet = card.sheetPath else { throw WorkbookWriterError.sheetNotFound(card.sourceSheet) }
            try WorkbookWriter.setCells(url, sheetPath: sheet, row: card.excelRow,
                                        cells: [card.questionColumn: q, card.answerColumn: a], backupFolder: backups)
        case .add(let template, let q, let a):
            guard let sheet = template.sheetPath else { throw WorkbookWriterError.sheetNotFound(template.sourceSheet) }
            try WorkbookWriter.appendRow(url, sheetPath: sheet,
                                         cells: [template.questionColumn: q, template.answerColumn: a], backupFolder: backups)
        case .reorder(let cards):
            guard let sheet = cards.first?.sheetPath else { return }
            try WorkbookWriter.reorderRows(url, sheetPath: sheet, order: cards.map(\.excelRow), backupFolder: backups)
        case .delete(let card):
            guard let sheet = card.sheetPath else { throw WorkbookWriterError.sheetNotFound(card.sourceSheet) }
            try WorkbookWriter.deleteRow(url, sheetPath: sheet, row: card.excelRow, backupFolder: backups)
        }
    }

    /// Re-reads the workbook after a save, keeping the selected category and screen.
    func reloadAfterEdit(_ url: URL) async {
        guard let loaded = try? await Task.detached(operation: { try WorkbookLoader.load(url: url) }).value else { return }
        cards = loaded.result.cards
        categories = loaded.result.loadedSheets
        if topic != "All" && !categories.contains(topic) { topic = "All" }
        rangeTo = String(max(1, count(for: topic)))
        ensureToday()
        onPlanChanged?()
    }

    /// Retries the waiting save every 10 seconds until Excel closes the file.
    private func startRetry(_ url: URL) {
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard let self, let op = self.pendingEdit else { return }
                if WorkbookWriter.isLocked(url) { continue }
                self.pendingEdit = nil
                await self.save(op)
                return
            }
        }
    }

    func setEditStatus(_ text: String, error: Bool = false) {
        editStatus = text
        editStatusIsError = error
    }
}
