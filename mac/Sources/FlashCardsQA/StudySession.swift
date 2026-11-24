import FlashCardsCore
import Foundation
import Observation

enum Mode { case start, study, running, done }

/// App state. A direct port of the state and handlers in `src/App.js`.
@MainActor @Observable
final class StudySession {
    static let folderKey = "workbookFolder"

    var cards: [Card] = []
    var categories: [String] = []
    var loading = false
    var topic = "All"
    var shuffle = true
    var rangeFrom = "1"
    var rangeTo = ""
    var mode: Mode = .start
    var deck: [Card] = []
    var index = 0
    var flipped = false
    var results: [String: Bool] = [:]
    var status = ""
    var statusIsError = false
    private var statusToken = 0

    var folder: String {
        let saved = UserDefaults.standard.string(forKey: Self.folderKey) ?? ""
        return saved.isEmpty ? WorkbookLoader.defaultFolder : saved
    }

    // MARK: Derived values

    var filtered: [Card] { cards.filter { topic == "All" || $0.topic == topic } }
    func count(for category: String) -> Int {
        category == "All" ? cards.count : cards.filter { $0.topic == category }.count
    }
    private var rangeStart: Int? { Int(rangeFrom.trimmingCharacters(in: .whitespaces)) }
    private var rangeEnd: Int? { rangeTo.isEmpty ? filtered.count : Int(rangeTo.trimmingCharacters(in: .whitespaces)) }
    var rangeValid: Bool {
        if topic == "All" { return true }
        guard let s = rangeStart, let e = rangeEnd else { return false }
        return s >= 1 && e >= s && e <= filtered.count
    }
    var practiceCount: Int {
        if topic == "All" { return filtered.count }
        guard rangeValid, let s = rangeStart, let e = rangeEnd else { return 0 }
        return e - s + 1
    }
    var canStart: Bool { !loading && !filtered.isEmpty && rangeValid }
    var knewCount: Int { results.values.filter { $0 }.count }
    var missedCount: Int { results.values.filter { !$0 }.count }
    var missedCards: [Card] { deck.filter { results[$0.id] == false } }
    var current: Card? { deck.indices.contains(index) ? deck[index] : nil }

    private var pool: [Card] {
        guard topic != "All", let s = rangeStart, let e = rangeEnd, rangeValid else { return filtered }
        return Array(filtered[(s - 1)..<e])
    }

    // MARK: Loading

    func refresh() async {
        loading = true
        setStatus("Loading the latest workbook from OneDrive…")
        let folder = self.folder
        do {
            let loaded = try await Task.detached { try WorkbookLoader.loadDefault(folder: folder) }.value
            apply(loaded, source: loaded.fileName)
        } catch {
            setStatus("Could not load the OneDrive workbook: \(error.localizedDescription)", error: true)
        }
        loading = false
    }

    func importWorkbook(url: URL) async {
        setStatus("Reading selected workbook…")
        do {
            let loaded = try await Task.detached { try WorkbookLoader.load(url: url) }.value
            if loaded.result.loadedSheets.isEmpty {
                let tabs = loaded.sheetNames.isEmpty ? "none" : loaded.sheetNames.joined(separator: ", ")
                setStatus("No tabs with QA in cell A1 were found. Workbook tabs detected: \(tabs).", error: true)
            } else {
                apply(loaded, source: loaded.fileName)
            }
        } catch {
            setStatus("Could not read this workbook. \(error.localizedDescription)", error: true)
        }
        clearStatus(after: 8)
    }

    private func apply(_ loaded: LoadedWorkbook, source: String) {
        let r = loaded.result
        cards = r.cards
        categories = r.loadedSheets
        topic = "All"
        rangeFrom = "1"; rangeTo = ""
        reset()
        let sheets = r.loadedSheets.isEmpty
            ? " (no tabs with QA in cell A1 were found)"
            : " from \(r.loadedSheets.joined(separator: ", "))"
        let dupes = r.duplicatesSkipped > 0 ? " \(r.duplicatesSkipped) repeated questions were skipped." : ""
        setStatus("Loaded \(r.cards.count) questions from \(source)\(sheets).\(dupes)")
    }

    private func setStatus(_ text: String, error: Bool = false) {
        status = text
        statusIsError = error
        statusToken += 1
    }

    private func clearStatus(after seconds: Double) {
        let token = statusToken
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            if token == statusToken { status = "" }
        }
    }

    // MARK: Actions

    func reset() {
        mode = .start; deck = []; index = 0; flipped = false; results = [:]
    }

    func setFilter(_ value: String) {
        topic = value
        rangeFrom = "1"
        rangeTo = String(max(1, count(for: value)))
        reset()
    }

    func start(retryWrong: Bool) {
        let source = retryWrong ? missedCards : pool
        guard !source.isEmpty, retryWrong || rangeValid else { return }
        deck = shuffle ? source.shuffled() : source
        index = 0; flipped = false
        if !retryWrong { results = [:] }
        mode = .running
    }

    func startStudy() {
        guard canStart else { return }
        deck = pool
        index = 0
        mode = .study
    }

    func answer(_ knew: Bool) {
        guard let card = current else { return }
        results[card.id] = knew
        advance()
    }

    func skip() { advance() }

    private func advance() {
        if index + 1 >= deck.count { mode = .done } else { index += 1; flipped = false }
    }

    func previous() { index = max(0, index - 1) }
    func next() { index = min(deck.count - 1, index + 1) }
}
