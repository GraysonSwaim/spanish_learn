import Foundation
import SwiftData

/// One sitting: a queue of cards, the one on screen, and how far it's been revealed.
@MainActor
@Observable
final class StudySession {
    enum Mode {
        /// Stage 0: both sides shown, then asked again later in the session.
        case intro
        case esEn, enEs, type
        /// Conjugation: say the table aloud (stages 1–3) or type it (4–5).
        case recite, grid
    }

    /// How much of the card is showing. Vocabulary: prompt → answer.
    /// Conjugación: word (the verb alone) → prompt (its meaning, and the typing boxes) → answer.
    enum Phase { case intro, word, prompt, answer }

    struct CellResult { var verdict: Verdict; var typed: String }

    private struct Undo {
        /// The card graded and every card a grade could move up behind it.
        let states: [(Card, CardState)]
        let queue: [Card]
        let fresh: [Card]
        let day: (reviewed: Int, correct: Int, newVocab: Int, newConj: Int)
        let done: Int, right: Int, answered: Int
        let missed: [Card]
    }

    private struct CardState {
        let stage: Int, ready: Bool, due: Date, interval: Int, reps: Int, lapses: Int
        let seen: Date?, lastReviewed: Date?, dropped: Date?

        init(_ c: Card) {
            (stage, ready, due, interval, reps, lapses) = (c.stage, c.ready, c.due, c.interval, c.reps, c.lapses)
            (seen, lastReviewed, dropped) = (c.seen, c.lastReviewed, c.dropped)
        }

        func restore(_ c: Card) {
            (c.stage, c.ready, c.due, c.interval, c.reps, c.lapses) = (stage, ready, due, interval, reps, lapses)
            (c.seen, c.lastReviewed, c.dropped) = (seen, lastReviewed, dropped)
        }
    }

    let tab: Tab
    let label: String
    /// What it's studying (a theme's id, a tense), so Home can pick it up again where it stopped.
    let key: String
    /// The daily session: it keeps going round stages 1–4, and new cards join as stage 1 makes room. A session for one
    /// stage's column asks each card once (a miss comes back a few cards later).
    let continuous: Bool
    private(set) var queue: [Card]
    private(set) var current: Card?
    private(set) var mode = Mode.intro
    private(set) var phase = Phase.intro
    private(set) var verdict: Verdict?
    private(set) var typed = ""
    private(set) var cells: [Int: CellResult] = [:]
    private(set) var done = 0
    private(set) var right = 0
    /// Cards graded, right or wrong.
    private(set) var answered = 0
    /// Cards missed this session, once each in the order they were missed: a mnemonic is asked for only the first time.
    private(set) var missed: [Card] = []
    /// The latest grades, drops and introductions, newest last, each one a step Deshacer can take back.
    private var history: [Undo] = []
    /// Bumped on every card change, so a delayed auto-advance can tell it's stale, and the view resets
    /// its drag and typing even when a missed card comes straight back (same id).
    private(set) var step = 0

    private let ctx: ModelContext
    private let verbs: [String: Card]
    /// Every card in the tab: the stages whose room decides what moves up.
    private let pool: [Card]
    /// New cards in the order they're introduced, for the daily session.
    private var fresh: [Card]
    let prefs: Prefs

    var isFinished: Bool { current == nil }
    var canUndo: Bool { !history.isEmpty }
    var remaining: Int { queue.count }

    /// `pool` is everything in the tab (the queue's cards when nil); `fresh` the new cards the daily session may bring in.
    init(queue: [Card], tab: Tab, label: String = "", key: String = "", pool: [Card]? = nil, fresh: [Card] = [], continuous: Bool = false,
         ctx: ModelContext, prefs: Prefs = .current) {
        self.queue = queue
        self.tab = tab
        self.label = label
        self.key = key
        self.pool = pool ?? queue
        self.fresh = fresh
        self.continuous = continuous
        self.ctx = ctx
        self.prefs = prefs
        self.verbs = Dictionary(Deck.allCards(ctx).filter { !$0.isConj }.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        if continuous { admit() }
        next()
    }

    /// Whether getting the card on screen right moves it up now, rather than leaving it ready for a place to open.
    var passMovesUp: Bool {
        guard let c = current else { return false }
        if c.stage >= 4 { return true }
        return pool.filter { !$0.isDropped && $0.stage == c.stage + 1 }.count < prefs.stageCap
    }

    // MARK: what's on the card

    /// The verb a conjugation card drills.
    func verb(of c: Card) -> Card? { verbs[c.verbID] }

    func forms(of c: Card) -> [String] { verb(of: c)?.forms(c.tense) ?? [] }

    /// The persons a table asks for: vosotros only when it's being practised.
    func asked(_ f: [String]) -> [Int] {
        (0..<6).filter { $0 < f.count && !f[$0].isEmpty && ($0 != Person.vosotros || prefs.vosotros) }
    }

    var canGrade: Bool { mode != .intro && phase == .answer }

    // MARK: moving through the queue

    private func next() {
        step += 1
        while let c = queue.first, c.isDropped || c.modelContext == nil { queue.removeFirst() }
        guard let c = queue.first else {
            current = nil
            try? ctx.save()
            return
        }
        current = c
        if c.isConj {
            mode = c.stage == 0 ? .intro : c.stage >= 4 ? .grid : .recite
        } else if c.stage == 0 {
            mode = .intro
        } else {
            mode = switch c.stage {
            case 1, 2: .esEn
            case 3: .enEs
            case 4: .type
            default: Bool.random() ? .type : .esEn
            }
            // Ajustes › Dirección overrides the stage. Typing still only starts at stage 4.
            let produce: Mode = c.stage >= 4 ? .type : .enEs
            switch prefs.direction {
            case .stage: break
            case .esEn: mode = .esEn
            case .enEs: mode = produce
            case .mixed: mode = Bool.random() ? .esEn : produce
            }
        }
        phase = mode == .intro ? .intro : c.isConj ? .word : .prompt
        verdict = nil
        typed = ""
        cells = [:]
        if prefs.autoSpeak && (mode == .intro || mode == .esEn) { speak() }
    }

    func speak() {
        guard let c = current else { return }
        Speaker.shared.speak(c.es, lang: prefs.voiceLang)
    }

    func showMeaning() {
        guard phase == .word else { return }
        phase = .prompt
    }

    func reveal() {
        guard phase == .prompt else { return }
        phase = .answer
        if prefs.autoSpeak && mode == .enEs { speak() }
    }

    func check(_ input: String) {
        guard let c = current, phase == .prompt else { return }
        typed = input
        verdict = TextMatch.check(input, against: c.es)
        phase = .answer
        if prefs.autoSpeak { speak() }
        // A right answer moves on by itself.
        if verdict == .exact { autoPass(after: 0.9) }
    }

    func checkGrid(_ inputs: [Int: String]) {
        guard let c = current, phase == .prompt else { return }
        let f = forms(of: c)
        for p in asked(f) {
            let t = inputs[p] ?? ""
            cells[p] = CellResult(verdict: TextMatch.check(TextMatch.dropPronoun(t, person: p), against: f[p]), typed: t)
        }
        let all = cells.values.allSatisfy { $0.verdict == .exact }
        verdict = all ? .exact : .wrong
        phase = .answer
        if all { autoPass(after: 1.2) }
    }

    private func autoPass(after seconds: Double) {
        let mine = step
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            if step == mine && canGrade { grade(true) }
        }
    }

    private func snapshot(_ c: Card) {
        let d = Deck.today(ctx)
        let moved = [c] + pool.filter { $0 !== c && $0.stage > 0 && $0.stage < 5 }
        history.append(Undo(states: moved.map { ($0, CardState($0)) }, queue: queue, fresh: fresh,
                            day: (d.reviewed, d.correct, d.newVocab, d.newConj), done: done, right: right, answered: answered, missed: missed))
        if history.count > Self.undoDepth { history.removeFirst() }
    }

    /// Put a new card at stage 1 and ask it again a few cards later.
    func introDone() {
        guard let c = current, mode == .intro else { return }
        snapshot(c)
        Scheduler.introduce(c)
        let d = Deck.today(ctx)
        switch tab {
        case .conj: d.newConj += 1
        case .vocab: d.newVocab += 1
        }
        queue.removeFirst()
        requeue(c)
        try? ctx.save()
        next()
    }

    func grade(_ pass: Bool) {
        guard let c = current, canGrade else { return }
        snapshot(c)
        let d = Deck.today(ctx)
        d.reviewed += 1
        queue.removeFirst()
        answered += 1
        if pass {
            Scheduler.pass(c, in: pool, cap: prefs.stageCap)
            d.correct += 1
            right += 1
            done += 1
            // Round again, behind everything else, until it's mastered.
            if continuous && c.stage < 5 { queue.append(c) }
        } else {
            let wasMastered = c.stage == 5
            Scheduler.fail(c, in: pool, cap: prefs.stageCap)
            if !missed.contains(where: { $0 === c }) { missed.append(c) }
            // Reviewing Dominada, a miss goes back to Producir to be mastered again there, not straight back here.
            if continuous || !wasMastered { requeue(c) }
        }
        if continuous { admit() }
        try? ctx.save()
        next()
    }

    /// New cards fill stage 1 while it has room, counting those already waiting to be introduced. They go to the
    /// front, so a place that opens is filled straight away.
    private func admit() {
        fresh.removeAll { $0.stage != 0 || $0.isDropped || $0.modelContext == nil }
        let waiting = queue.filter { $0.stage == 0 }
        var room = Scheduler.room(pool, cap: prefs.stageCap) - waiting.count
        var incoming: [Card] = []
        while room > 0, let c = fresh.first(where: { f in !waiting.contains { $0 === f } }) {
            fresh.removeAll { $0 === c }
            incoming.append(c)
            room -= 1
        }
        queue.insert(contentsOf: incoming, at: 0)
    }

    func drop() {
        guard let c = current else { return }
        snapshot(c)
        c.dropped = .now
        queue.removeAll { $0 === c }
        // Its place can go to a ready card below, or a new one.
        Scheduler.settle(pool, cap: prefs.stageCap)
        if continuous { admit() }
        try? ctx.save()
        next()
    }

    /// How many steps back Deshacer can go.
    static let undoDepth = 20

    /// Takes back the last grade, drop or introduction, and puts that card back on screen.
    func undo() {
        guard let u = history.popLast() else { return }
        for (c, state) in u.states { state.restore(c) }
        let d = Deck.today(ctx)
        (d.reviewed, d.correct, d.newVocab, d.newConj) = u.day
        queue = u.queue
        fresh = u.fresh
        done = u.done
        right = u.right
        answered = u.answered
        missed = u.missed
        try? ctx.save()
        next()
    }

    private func requeue(_ c: Card) {
        queue.insert(c, at: min(queue.count, Scheduler.relearnGap))
    }
}
