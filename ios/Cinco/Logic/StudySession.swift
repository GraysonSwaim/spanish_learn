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

    /// How much of the card is showing. Vocabulary: prompt → answer, and a verb adds forms (its tables).
    /// Conjugación: word (the verb alone) → prompt (its meaning, and the typing boxes) → answer.
    enum Phase { case intro, word, prompt, answer, forms }

    struct CellResult { var verdict: Verdict; var typed: String }

    private struct Undo {
        let card: Card
        let state: CardState
        let queue: [Card]
        let day: (reviewed: Int, correct: Int, newVocab: Int, newConj: Int)
        let done: Int, right: Int
    }

    private struct CardState {
        let stage: Int, due: Date, interval: Int, reps: Int, lapses: Int
        let seen: Date?, lastReviewed: Date?, dropped: Date?

        init(_ c: Card) {
            (stage, due, interval, reps, lapses) = (c.stage, c.due, c.interval, c.reps, c.lapses)
            (seen, lastReviewed, dropped) = (c.seen, c.lastReviewed, c.dropped)
        }

        func restore(_ c: Card) {
            (c.stage, c.due, c.interval, c.reps, c.lapses) = (stage, due, interval, reps, lapses)
            (c.seen, c.lastReviewed, c.dropped) = (seen, lastReviewed, dropped)
        }
    }

    let tab: Tab
    let label: String
    private(set) var queue: [Card]
    private(set) var current: Card?
    private(set) var mode = Mode.intro
    private(set) var phase = Phase.intro
    private(set) var verdict: Verdict?
    private(set) var typed = ""
    private(set) var cells: [Int: CellResult] = [:]
    private(set) var done = 0
    private(set) var right = 0
    private var undoState: Undo?
    /// Bumped on every card change, so a delayed auto-advance can tell it's stale.
    private var step = 0

    private let ctx: ModelContext
    private let verbs: [String: Card]
    let prefs: Prefs

    var isFinished: Bool { current == nil }
    var remaining: Int { queue.count }
    var canUndo: Bool { undoState != nil }

    init(queue: [Card], tab: Tab, label: String = "", ctx: ModelContext, prefs: Prefs = .current) {
        self.queue = queue
        self.tab = tab
        self.label = label
        self.ctx = ctx
        self.prefs = prefs
        self.verbs = Dictionary(Deck.allCards(ctx).filter { !$0.isConj }.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        next()
    }

    // MARK: what's on the card

    /// The verb a conjugation card drills.
    func verb(of c: Card) -> Card? { verbs[c.verbID] }

    func forms(of c: Card) -> [String] { verb(of: c)?.forms(c.tense) ?? [] }

    /// The persons a table asks for: vosotros only when it's being practised.
    func asked(_ f: [String]) -> [Int] {
        (0..<6).filter { $0 < f.count && !f[$0].isEmpty && ($0 != Person.vosotros || prefs.vosotros) }
    }

    /// A verb in Vocabulario takes three steps: the word, its meaning, then its tables. It's graded after the tables.
    var showsForms: Bool { current.map { !$0.isConj && $0.isVerb } ?? false }

    var canGrade: Bool {
        guard mode != .intro else { return false }
        return phase == (showsForms ? .forms : .answer)
    }

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

    func speak(_ text: String? = nil) {
        guard let c = current else { return }
        Speaker.shared.speak(text ?? c.es, lang: prefs.voiceLang)
    }

    /// Reads a whole table aloud, one form after another.
    func speakTable() {
        guard let c = current else { return }
        let f = forms(of: c)
        speak(asked(f).map { TextMatch.spokenText(f[$0]) }.joined(separator: ", "))
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

    func showForms() {
        guard phase == .answer, showsForms else { return }
        phase = .forms
    }

    func check(_ input: String) {
        guard let c = current, phase == .prompt else { return }
        typed = input
        verdict = TextMatch.check(input, against: c.es)
        phase = .answer
        if prefs.autoSpeak { speak() }
        // A right answer moves on by itself, unless there are verb tables still to see.
        if verdict == .exact && !showsForms { autoPass(after: 0.9) }
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
        undoState = Undo(card: c, state: CardState(c), queue: queue,
                         day: (d.reviewed, d.correct, d.newVocab, d.newConj), done: done, right: right)
    }

    /// Put a new card at stage 1 and ask it again a few cards later.
    func introDone() {
        guard let c = current, mode == .intro else { return }
        snapshot(c)
        Scheduler.introduce(c)
        let d = Deck.today(ctx)
        if tab == .conj { d.newConj += 1 } else { d.newVocab += 1 }
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
        if pass {
            Scheduler.pass(c)
            d.correct += 1
            right += 1
            done += 1
        } else {
            Scheduler.fail(c)
            requeue(c)
        }
        try? ctx.save()
        next()
    }

    func drop() {
        guard let c = current else { return }
        snapshot(c)
        c.dropped = .now
        queue.removeAll { $0 === c }
        try? ctx.save()
        next()
    }

    func undo() {
        guard let u = undoState else { return }
        u.state.restore(u.card)
        let d = Deck.today(ctx)
        (d.reviewed, d.correct, d.newVocab, d.newConj) = u.day
        queue = u.queue
        done = u.done
        right = u.right
        undoState = nil
        try? ctx.save()
        next()
    }

    private func requeue(_ c: Card) {
        queue.insert(c, at: min(queue.count, Scheduler.relearnGap))
    }
}
