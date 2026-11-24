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
    /// Cards marked "Already studied" in the current study deck (skipped by "Test yourself").
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
        return FSRS.preview(review(for: card), today: today, retention: progress.data.desiredRetention, clock: clock)
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
        categories = r.loadedSheets
        topic = "All"
        rangeFrom = "1"; rangeTo = ""
        reset()
        let sheets = r.loadedSheets.isEmpty
            ? " (no tabs with QA in cell A1 were found)"
            : " from \(r.loadedSheets.joined(separator: ", "))"
        let dupes = r.duplicatesSkipped > 0 ? " \(r.duplicatesSkipped) repeated questions were skipped." : ""
        ensureToday()
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

    // MARK: Study plan (sessions)

    var today: String { clock.key(Date()) }
    var nowMinute: Int { clock.minuteOfDay(Date()) }
    /// Bumped every minute by the app so time-based views (session status) refresh.
    var minuteTick = 0
    /// Called after targets change, so session reminders can be rescheduled.
    @ObservationIgnored var onPlanChanged: (() -> Void)?

    var plan: StudyPlan { progress.data.plan }

    /// Cards in the plan's categories (all when none are chosen), in workbook order.
    var planCards: [Card] {
        let chosen = Set(plan.categories)
        return cards.filter { chosen.isEmpty || chosen.contains($0.topic) }
    }
    var planScope: [PlanCard] { planCards.map { PlanCard(key: $0.key, topic: $0.topic) } }

    func review(for card: Card) -> CardReview? { progress.data.cards[card.key] }

    var dueCards: [Card] {
        let day = today
        return planCards.filter { SpacedRepetition.isDue(review(for: $0), on: day) }
    }
    var weakCards: [Card] { planCards.filter { SpacedRepetition.isWeak(review(for: $0)) } }
    var newCards: [Card] { planCards.filter { review(for: $0) == nil } }
    var todaysNewCards: [Card] { let d = today; return planCards.filter { review(for: $0)?.introducedDay == d } }

    var allSlots: [StudySlot] { progress.data.slots.filter(\.enabled).sorted { $0.start < $1.start } }
    var studySlots: [StudySlot] { SessionPlanner.studySlots(progress.data.slots) }

    func cards(for keys: [String]) -> [Card] {
        let byKey = Dictionary(cards.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        return keys.compactMap { byKey[$0] }
    }

    func target(for slot: StudySlot) -> SlotTarget {
        progress.data.dayTargets[today]?.slots[slot.id] ?? SlotTarget()
    }

    func status(for slot: StudySlot) -> SlotStatus {
        _ = minuteTick
        return SessionPlanner.status(of: slot, on: today, data: progress.data, nowMinute: nowMinute)
    }

    func isDoneToday(_ key: String) -> Bool { progress.data.isDone(key, on: today) }

    /// Keys of a session still to do today.
    func remaining(_ slot: StudySlot) -> (new: [String], review: [String]) {
        let t = target(for: slot)
        if t.skipped || t.rolledOver { return ([], []) }
        return (t.newKeys.filter { !isDoneToday($0) }, t.reviewKeys.filter { !isDoneToday($0) })
    }

    /// Today's remaining planned work across sessions.
    var todayRemaining: (new: Int, review: Int) {
        studySlots.reduce((0, 0)) { sum, slot in
            let r = remaining(slot)
            return (sum.0 + r.new.count, sum.1 + r.review.count)
        }
    }

    func forecast(days: Int = 14) -> Forecast {
        _ = minuteTick
        return SessionPlanner.forecast(progress.data, cards: planScope, today: today, nowMinute: nowMinute, days: days, clock: clock)
    }

    /// Locks today's targets, carries over missed days and ended sessions.
    func ensureToday() {
        guard !cards.isEmpty else { return }
        var data = progress.data
        SessionPlanner.catchUp(&data, today: today, clock: clock)
        SessionPlanner.lockDay(&data, cards: planScope, day: today, clock: clock)
        SessionPlanner.rollOver(&data, day: today, nowMinute: nowMinute, clock: clock)
        if data != progress.data {
            progress.data = data
            onPlanChanged?()
        }
    }

    /// Re-plans today's sessions (after changing session times or categories). Carried work is kept.
    func rebuildToday() {
        guard var dt = progress.data.dayTargets[today] else { ensureToday(); return }
        let carried = dt.slots.values.flatMap(\.carriedKeys).filter { !isDoneToday($0) }
        dt.carryInNew += carried.filter { progress.data.cards[$0] == nil }
        dt.carryInReview += carried.filter { progress.data.cards[$0] != nil }
        dt.slots = [:]
        dt.locked = false
        progress.data.dayTargets[today] = dt
        ensureToday()
    }

    /// "Busy today": move the rest of today's targets to tomorrow.
    func busyToday() {
        var data = progress.data
        SessionPlanner.skipRest(&data, day: today, clock: clock)
        progress.data = data
        onPlanChanged?()
    }

    /// Whether an answer to this card updates its FSRS schedule: new cards, due cards, and
    /// cards already reviewed today (same-day retries). Other cards are "practice only".
    func isScheduled(_ card: Card) -> Bool {
        guard let r = review(for: card) else { return true }
        return r.dueDay <= today || r.lastReviewed == today
    }

    private func recordReview(_ card: Card, rating: Rating) {
        guard isScheduled(card) else { return }
        let key = card.key
        progress.data.cards[key] = FSRS.review(
            progress.data.cards[key], rating: rating, topic: card.topic, today: today,
            retention: progress.data.desiredRetention, clock: clock)
        markDone(card)
    }

    private func markDone(_ card: Card) {
        progress.data.markDone(card.key, on: today)
        onPlanChanged?()
    }

    func openPlan() {
        reset()
        ensureToday()
        mode = .plan
    }

    /// Starts a session: new cards are studied first (then self-tested), reviews are practised mixed.
    func startSession(_ slot: StudySlot) {
        let r = remaining(slot)
        let newOnes = cards(for: r.new)
        if !newOnes.isEmpty {
            beginStudy(newOnes, newCards: true)
        } else {
            beginPractice(cards(for: r.review).shuffled())
        }
    }

    func startSessionReviews(_ slot: StudySlot) { beginPractice(cards(for: remaining(slot).review).shuffled()) }

    func startQuickRecall() { beginPractice(todaysNewCards.shuffled()) }

    /// From the end of a study deck: practise the same cards. New cards count as done only
    /// once rated here, which also gives them their first FSRS schedule.
    func testStudiedCards() {
        let rest = deck.filter { !alreadyStudied.contains($0.id) }
        if rest.isEmpty { reset(); return }
        beginPractice(rest.shuffled())
    }

    /// "Already studied": the card is known from before, so it gets an FSRS Easy first review
    /// (next review in about 16 days) and counts as done for today's session.
    func markAlreadyStudied() {
        guard let card = current, review(for: card) == nil else { return }
        progress.data.cards[card.key] = FSRS.review(
            nil, rating: .easy, topic: card.topic, today: today,
            retention: progress.data.desiredRetention, clock: clock)
        markDone(card)
        alreadyStudied.insert(card.id)
        if index + 1 < deck.count { index += 1 } else { testStudiedCards() }
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
