import FlashCardsCore
import Foundation
import Observation

enum Mode { case start, study, running, done, plan }

/// App state. A port of the state and handlers in `src/App.js`, plus study-plan entry points.
@MainActor @Observable
final class StudySession {
    static let folderKey = "workbookFolder"

    let progress: ProgressStore
    let clock = DayClock()
    /// What the Pomodoro timer credits time to; follows the last study/practice mode.
    private(set) var lastActivity: Activity = .study
    /// True when the current study deck came from "Learn new", so its end offers a self-test.
    private(set) var studyingNewCards = false
    /// Cards marked "Studied" in the current study deck (skipped by "Test yourself").
    private var alreadyStudied = Set<String>()

    // Editing the workbook
    /// The workbook the cards came from; edits are saved back to it.
    private(set) var sourceURL: URL?
    var editStatus = ""
    var editStatusIsError = false
    /// A save waiting for Excel to close the file.
    @ObservationIgnored var pendingEdit: EditOp?
    @ObservationIgnored var retryTask: Task<Void, Never>?

    init(progress: ProgressStore) {
        self.progress = progress
    }

    var cards: [Card] = []
    /// Section dividers in each category's question list (rows starting with "## ").
    var dividers: [SectionDivider] = []
    /// Where each QA sheet keeps its questions (used to add rows, even to empty categories).
    var sheetInfos: [SheetInfo] = []
    /// A category created this session; its question list opens expanded.
    var newlyCreatedCategory: String?
    var categories: [String] = []
    var loading = false
    var topic = "All"
    var shuffle = true
    var rangeFrom = "1"
    var rangeTo = ""
    var mode: Mode = .start {
        didSet {
            switch mode {
            case .study: lastActivity = .study
            case .running, .done: lastActivity = .revise
            default: break
            }
        }
    }
    var deck: [Card] = []
    var index = 0
    var flipped = false
    var results: [String: Rating] = [:]
    var status = ""
    var statusIsError = false
    private var statusToken = 0

    var folder: String {
        // FLASHCARDSQA_WORKBOOK_DIR lets testing use a copy instead of your real workbook.
        if let dir = ProcessInfo.processInfo.environment["FLASHCARDSQA_WORKBOOK_DIR"], !dir.isEmpty { return dir }
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
    var knewCount: Int { results.values.filter { $0 != .again }.count }
    var missedCount: Int { results.values.filter { $0 == .again }.count }
    var missedCards: [Card] { deck.filter { results[$0.id] == .again } }
    /// Recalled with effort; worth a quick second look.
    var shakyCards: [Card] { deck.filter { results[$0.id] == .hard } }

    /// Days until the next review for each rating of the current card.
    var ratingPreview: [Rating: Int] {
        guard let card = current, isScheduled(card) else { return [:] }
        return Scheduler.preview(review(for: card), today: today, retention: progress.data.desiredRetention,
                                 useCheckpoints: progress.data.useCheckpoints, clock: clock)
    }
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
        sourceURL = loaded.url
        cards = r.cards
        dividers = r.dividers
        sheetInfos = r.sheets
        categories = r.loadedSheets
        topic = "All"
        rangeFrom = "1"; rangeTo = ""
        reset()
        let sheets = r.loadedSheets.isEmpty
            ? " (no tabs with QA in cell A1 were found)"
            : " from \(r.loadedSheets.joined(separator: ", "))"
        let dupes = r.duplicatesSkipped > 0 ? " \(r.duplicatesSkipped) repeated questions were skipped." : ""
        onPlanChanged?()
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
        mode = .start; deck = []; index = 0; flipped = false; results = [:]; studyingNewCards = false
    }

    /// Category the timer credits: the card on screen, else the selected topic.
    var timeCategory: String {
        if mode == .study || mode == .running, let card = current { return card.topic }
        return topic
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
        beginPractice(shuffle ? source.shuffled() : source, keepResults: retryWrong)
    }

    func startStudy() {
        guard canStart else { return }
        beginStudy(pool, newCards: false)
    }

    private func beginPractice(_ cards: [Card], keepResults: Bool = false) {
        guard !cards.isEmpty else { return }
        deck = cards
        index = 0; flipped = false
        if !keepResults { results = [:] }
        studyingNewCards = false
        mode = .running
    }

    private func beginStudy(_ cards: [Card], newCards: Bool) {
        guard !cards.isEmpty else { return }
        deck = cards
        index = 0; flipped = false; results = [:]
        studyingNewCards = newCards
        alreadyStudied = []
        mode = .study
    }

    func answer(_ rating: Rating) {
        guard let card = current else { return }
        results[card.id] = rating
        recordReview(card, rating: rating)
        advance()
    }

    // MARK: Daily plan: FSRS revision first, then your own tasks

    var today: String { clock.key(Date()) }
    /// Bumped every minute by the app so date-based views refresh after midnight.
    var minuteTick = 0
    /// Called after reviews or tasks change, so the morning reminder can be rescheduled.
    @ObservationIgnored var onPlanChanged: (() -> Void)?

    func review(for card: Card) -> CardReview? { progress.data.cards[card.key] }

    /// Cards FSRS wants revised today (overdue ones included).
    var dueCards: [Card] {
        _ = minuteTick
        let day = today
        return cards.filter { SpacedRepetition.isDue(review(for: $0), on: day) }
    }
    var revisedTodayCount: Int {
        RevisionOutlook.revisedToday(progress.data, keys: cards.map(\.key), today: today)
    }
    var weakCards: [Card] { cards.filter { SpacedRepetition.isWeak(review(for: $0)) } }
    var newCards: [Card] { cards.filter { review(for: $0) == nil } }
    var todaysNewCards: [Card] { let d = today; return cards.filter { review(for: $0)?.introducedDay == d } }

    func revisionOutlook(days: Int = 7) -> [RevisionOutlook.Day] {
        _ = minuteTick
        return RevisionOutlook.days(progress.data, cards: cards.map { ($0.key, $0.topic) }, today: today, days: days, clock: clock)
    }

    func cards(for keys: [String]) -> [Card] {
        let byKey = Dictionary(cards.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        return keys.compactMap { byKey[$0] }
    }

    /// How many of these cards are due because of a 📅 fixed checkpoint vs a 🧠 FSRS date.
    func split(_ cards: [Card]) -> (fixed: Int, fsrs: Int) {
        cards.reduce((0, 0)) { sum, card in
            Scheduler.nextMethod(of: review(for: card), clock: clock) == .fixed ? (sum.0 + 1, sum.1) : (sum.0, sum.1 + 1)
        }
    }

    /// Cards due on `day` (overdue ones included for today).
    func cardsDue(on day: String) -> [Card] {
        let t = today
        return cards.filter { c in
            guard let r = review(for: c) else { return false }
            return day == t ? r.dueDay <= day : r.dueDay == day
        }
    }

    /// Put every studied card back on the checkpoints from today (Settings button).
    func restartCheckpointsToday() {
        Scheduler.restartAll(&progress.data, today: today)
        progress.data.checkpointsRestartedDay = today
        onPlanChanged?()
    }

    /// Revise every due card, mixed across categories.
    func startRevision() { beginPractice(dueCards.shuffled()) }

    /// Revise only one category's due cards.
    func startRevision(category: String) { beginPractice(dueCards.filter { $0.topic == category }.shuffled()) }

    // Tasks

    func tasks(on day: String) -> [PlanTask] { progress.data.tasks[day] ?? [] }

    /// Unfinished tasks from earlier days, newest first.
    var overdueTasks: [(day: String, task: PlanTask)] {
        let t = today
        return progress.data.tasks.filter { $0.key < t }.sorted { $0.key > $1.key }
            .flatMap { day, list in list.filter { !$0.done }.map { (day, $0) } }
    }

    func addTask(_ text: String, on day: String, link: TaskLink? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        progress.data.tasks[day, default: []].append(
            PlanTask(text: trimmed, link: link ?? PlanText.link(for: trimmed, categories: categories)))
        onPlanChanged?()
    }

    func updateTask(_ id: String, on day: String, _ change: (inout PlanTask) -> Void) {
        guard var list = progress.data.tasks[day], let i = list.firstIndex(where: { $0.id == id }) else { return }
        change(&list[i])
        progress.data.tasks[day] = list
        onPlanChanged?()
    }

    func deleteTask(_ id: String, on day: String) {
        progress.data.tasks[day]?.removeAll { $0.id == id }
        if progress.data.tasks[day]?.isEmpty == true { progress.data.tasks[day] = nil }
        onPlanChanged?()
    }

    func moveTask(_ id: String, from day: String, to newDay: String) {
        guard day != newDay, let task = progress.data.tasks[day]?.first(where: { $0.id == id }) else { return }
        deleteTask(id, on: day)
        progress.data.tasks[newDay, default: []].append(task)
        onPlanChanged?()
    }

    /// Drag and drop within a day: put `id` where `target` is.
    func moveTask(_ id: String, onto target: String, on day: String) {
        guard var list = progress.data.tasks[day],
              let from = list.firstIndex(where: { $0.id == id }),
              let to = list.firstIndex(where: { $0.id == target }), from != to else { return }
        let item = list.remove(at: from)
        list.insert(item, at: to)
        progress.data.tasks[day] = list
    }

    /// Adds a pasted plan (e.g. "[Nov 25 ]" headers with tasks under them) to your days.
    @discardableResult
    func importPlan(_ text: String) -> PlanText.Parsed {
        let parsed = PlanText.parse(text, today: today, categories: categories, clock: clock)
        for (day, list) in parsed.tasksByDay {
            let existing = Set((progress.data.tasks[day] ?? []).map { $0.text.lowercased() })
            progress.data.tasks[day, default: []].append(contentsOf: list.filter { !existing.contains($0.text.lowercased()) })
        }
        onPlanChanged?()
        return parsed
    }

    /// The questions a task's ▶ Start opens: a category, or the questions under one of its dividers.
    func cards(for link: TaskLink) -> [Card] {
        guard let section = link.section else { return cardsInSheet(of: link.category) }
        var inSection = false
        var out: [Card] = []
        for item in listItems(of: link.category) {
            switch item {
            case .divider(let d):
                if inSection { return out }
                inSection = d.title.caseInsensitiveCompare(section) == .orderedSame
            case .card(let c):
                if inSection { out.append(c) }
            }
        }
        return out
    }

    func startTask(_ task: PlanTask) {
        guard let link = task.link else { return }
        beginStudy(cards(for: link), newCards: false)
    }

    // Reviews

    /// Whether an answer to this card updates its FSRS schedule: new cards, due cards, and
    /// cards already reviewed today (same-day retries). Other cards are "practice only".
    func isScheduled(_ card: Card) -> Bool {
        guard let r = review(for: card) else { return true }
        return r.dueDay <= today || r.lastReviewed == today
    }

    private func recordReview(_ card: Card, rating: Rating) {
        guard isScheduled(card) else { return }
        let key = card.key
        progress.data.cards[key] = Scheduler.review(
            progress.data.cards[key], rating: rating, topic: card.topic, today: today,
            retention: progress.data.desiredRetention, useCheckpoints: progress.data.useCheckpoints, clock: clock)
        onPlanChanged?()
    }

    func openPlan() {
        reset()
        mode = .plan
    }

    func startQuickRecall() { beginPractice(todaysNewCards.shuffled()) }

    /// From the end of a study deck: practise the same cards (new ones get their first FSRS rating).
    func testStudiedCards() {
        let rest = deck.filter { !alreadyStudied.contains($0.id) }
        if rest.isEmpty { reset(); return }
        beginPractice(rest.shuffled())
    }

    /// A card is "studied" once it has an FSRS schedule (it will come back for revision).
    func isStudied(_ card: Card) -> Bool { review(for: card) != nil }

    /// Whether unsetting "Studied" would drop real practice history (more than the one Studied mark).
    func hasPracticeHistory(_ card: Card) -> Bool { (review(for: card)?.reviews ?? 0) > 1 }

    /// "Studied" toggle. Set: the card enters your schedule — checkpoints on days 1, 3, 7, 14 and
    /// FSRS, both from today (or FSRS alone if checkpoints are off).
    /// Unset: the card becomes new again.
    func toggleStudied(_ card: Card) {
        if isStudied(card) {
            progress.data.cards[card.key] = nil
            alreadyStudied.remove(card.id)
        } else {
            progress.data.cards[card.key] = Scheduler.review(
                nil, rating: .good, topic: card.topic, today: today,
                retention: progress.data.desiredRetention, useCheckpoints: progress.data.useCheckpoints, clock: clock)
            alreadyStudied.insert(card.id)
        }
        onPlanChanged?()
    }

    func skip() { advance() }

    private func advance() {
        if index + 1 >= deck.count { mode = .done } else { index += 1; flipped = false }
    }

    func previous() { index = max(0, index - 1) }
    func next() {
        index = min(deck.count - 1, index + 1)
    }
}
