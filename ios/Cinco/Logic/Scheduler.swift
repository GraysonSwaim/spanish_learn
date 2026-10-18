import Foundation

enum Tab: String, CaseIterable {
    case vocab, conj

    var name: String {
        switch self {
        case .vocab: "Vocabulario"
        case .conj: "Conjugación"
        }
    }
}

/// Which way a word card is asked once it's past stage 1 (Ajustes › Dirección).
enum Direction: String, CaseIterable {
    case stage, esEn = "es-en", enEs = "en-es", mixed

    var label: String {
        switch self {
        case .stage: "Etapa"
        case .esEn: "Es→In"
        case .enEs: "In→Es"
        case .mixed: "Mezcla"
        }
    }

    var blurb: String {
        switch self {
        case .stage: "Sigue la etapa: primero español, luego inglés"
        case .esEn: "Siempre ves el español y recuerdas el inglés"
        case .enEs: "Siempre ves el inglés y produces el español"
        case .mixed: "Al azar en cada tarjeta"
        }
    }
}

struct StageInfo {
    let name: String
    let blurb: String

    static let all: [StageInfo] = [
        StageInfo(name: "Nueva", blurb: ""),
        StageInfo(name: "Aprender", blurb: "Conoces la palabra con las dos caras a la vista y te la preguntan unas tarjetas después."),
        StageInfo(name: "Reconocer", blurb: "Ves el español y recuerdas el inglés."),
        StageInfo(name: "Recordar", blurb: "Ves el inglés y dices el español en voz alta antes de mirar."),
        StageInfo(name: "Producir", blurb: "Ves el inglés y escribes el español. Los acentos cuentan, pero un casi se marca en vez de fallarse."),
        StageInfo(name: "Dominada", blurb: "Escribir o reconocer, al azar. Vuelve a la semana, y cada acierto tras la espera la duplica: 2 semanas, 4, 8… Un fallo la baja a Producir."),
    ]
}

struct DeckCounts {
    /// Stages 1–4, which are always studied, and the Dominada cards whose week (or more) is up.
    var due = 0, unseen = 0, total = 0, dropped = 0
    var byStage = [0, 0, 0, 0, 0, 0]
}

/// The five stages as a pipeline: stages 1–4 each hold at most `cap` cards (Ajustes › Tarjetas por etapa), a card moves
/// up only into a stage with room, and a new card comes in only when stage 1 has room. A miss drops a card one stage
/// even into a full one, so it holds up the cards behind it until a correct answer makes room again. There's no wait
/// between stages 1–4; Dominada has no cap and is reviewed weekly, then every 2, 4, 8… weeks. Pure functions over cards,
/// so they're testable.
enum Scheduler {
    /// Cards between a miss and its retry.
    static let relearnGap = 5
    static let defaultCap = 5
    /// Days before a newly mastered card is reviewed.
    static let masteredInterval = 7
    /// A Dominada card due within this window counts as due now.
    static let lookahead: TimeInterval = 15 * 60

    static func inTab(_ c: Card, tab: Tab, tense: String) -> Bool {
        switch tab {
        case .vocab: c.kind == .word
        case .conj: c.isConj && (tense == Tense.random || c.tense == tense)
        }
    }

    static func isDue(_ c: Card, now: Date = .now) -> Bool {
        c.stage > 0 && (c.stage < 5 || c.due <= now.addingTimeInterval(lookahead))
    }

    static func counts(_ cards: [Card], now: Date = .now) -> DeckCounts {
        var n = DeckCounts()
        for c in cards {
            if c.isDropped { n.dropped += 1; continue }
            n.total += 1
            n.byStage[c.stage] += 1
            if c.stage == 0 { n.unseen += 1 } else if isDue(c, now: now) { n.due += 1 }
        }
        return n
    }

    /// How many new cards stage 1 can take.
    static func room(_ cards: [Card], cap: Int) -> Int {
        max(0, cap - cards.filter { !$0.isDropped && $0.stage == 1 }.count)
    }

    /// New cards in the order they'll be introduced. `cards` is everything in the tab; `verbs` all verb cards.
    /// Aleatorio staggers the tenses: a verb's present comes first and each later tense arrives three verbs
    /// further on, so one verb's tables don't all arrive together.
    static func unseen(_ cards: [Card], staggerTenses: Bool, verbs: [Card]) -> [Card] {
        let fresh = cards.filter { !$0.isDropped && $0.stage == 0 }.sorted { $0.order < $1.order }
        guard staggerTenses else { return fresh }
        var rank: [String: Int] = [:]
        for (i, v) in verbs.sorted(by: { $0.order < $1.order }).enumerated() { rank[v.id] = i }
        let key = { (c: Card) -> Int in
            guard c.isConj else { return .max }
            return (rank[c.verbID] ?? verbs.count) + Tense.index(of: c.tense) * 3
        }
        return fresh.enumerated().sorted { a, b in
            let (ka, kb) = (key(a.element), key(b.element))
            if ka != kb { return ka < kb }
            let (ta, tb) = (Tense.index(of: a.element.tense), Tense.index(of: b.element.tense))
            return ta != tb ? ta < tb : a.offset < b.offset
        }.map(\.element)
    }

    /// Everything in stages 1–4, the least recently seen first, taking turns with the Dominada cards that are due
    /// (oldest first), so neither buries the other. New cards join as stage 1 makes room (`StudySession`).
    static func dailyQueue(_ cards: [Card], now: Date = .now) -> [Card] {
        let live = cards.filter { !$0.isDropped }
        let working = live.filter { $0.stage > 0 && $0.stage < 5 }
            .sorted { ($0.lastReviewed ?? .distantPast) < ($1.lastReviewed ?? .distantPast) }
        let mastered = live.filter { $0.stage == 5 && isDue($0, now: now) }.sorted { $0.due < $1.due }
        var out: [Card] = []
        for i in 0..<max(working.count, mastered.count) {
            if i < working.count { out.append(working[i]) }
            if i < mastered.count { out.append(mastered[i]) }
        }
        return out
    }

    /// Everything at one stage, due or not, for practising a single column.
    static func stageQueue(_ cards: [Card], stage: Int) -> [Card] {
        cards.filter { !$0.isDropped && $0.stage == stage }.sorted { $0.due < $1.due }
    }

    /// A new card has been shown with both sides: it joins stage 1 and is asked again a few cards later.
    static func introduce(_ c: Card, now: Date = .now) {
        c.stage = 1
        c.ready = false
        c.interval = 0
        c.due = now
        c.seen = now
    }

    /// Right: the card is ready to move up and does if there's room (`settle`). A Dominada card's wait doubles, but
    /// only when it was reviewed once the wait was up; an early review leaves its schedule alone.
    static func pass(_ c: Card, in pool: [Card], cap: Int, now: Date = .now) {
        c.reps += 1
        c.lastReviewed = now
        if c.stage == 5 {
            guard isDue(c, now: now) else { return }
            c.interval = max(masteredInterval, c.interval) * 2
            c.due = day(c.interval, after: now)
        } else {
            c.ready = true
            settle(pool + [c], cap: cap, now: now)
        }
    }

    /// Wrong: the card drops one stage (never below 1), even into a full stage, and the place it left can take a ready
    /// card from below. A Dominada card drops to Producir and starts over at a week when it's mastered again.
    static func fail(_ c: Card, in pool: [Card], cap: Int, now: Date = .now) {
        c.reps += 1
        c.lastReviewed = now
        c.lapses += 1
        c.ready = false
        c.stage = max(1, c.stage - 1)
        c.interval = 0
        c.due = now
        settle(pool + [c], cap: cap, now: now)
    }

    /// Moves ready cards up wherever there's room, from the top stage down, so a place opening at the top passes all
    /// the way back. Within a stage, the card that's waited longest goes first.
    static func settle(_ pool: [Card], cap: Int, now: Date = .now) {
        var seen = Set<ObjectIdentifier>()
        let live = pool.filter { !$0.isDropped && $0.stage > 0 && $0.stage < 5 && seen.insert(ObjectIdentifier($0)).inserted }
        var count = [0, 0, 0, 0, 0, 0]
        for c in live { count[c.stage] += 1 }
        for s in stride(from: 4, through: 1, by: -1) {
            let waiting = live.filter { $0.stage == s && $0.ready }
                .sorted { ($0.lastReviewed ?? .distantPast) < ($1.lastReviewed ?? .distantPast) }
            for c in waiting {
                guard s == 4 || count[s + 1] < cap else { break }
                count[s] -= 1
                count[s + 1] += 1
                c.ready = false
                c.stage = s + 1
                if c.stage == 5 {
                    c.interval = masteredInterval
                    c.due = day(masteredInterval, after: now)
                } else {
                    c.due = now
                }
            }
        }
    }

    /// Once, when the pipeline arrived: stages 1 and 2 had piled up far past any cap. Each keeps the `cap` cards known
    /// best (fewest misses, then most practice) and the rest go back to the front of the new cards. Cards over the cap
    /// in stages 3 and 4 stay and work their way up.
    static func trim(_ pool: [Card], cap: Int) {
        let live = pool.filter { !$0.isDropped }
        var front = (live.map(\.order).min() ?? 0) - 1
        for s in [2, 1] {
            let ranked = live.filter { $0.stage == s }.sorted { ($0.lapses, -$0.reps, $0.order) < ($1.lapses, -$1.reps, $1.order) }
            for c in ranked.dropFirst(cap).sorted(by: { $0.order > $1.order }) {
                c.stage = 0
                c.ready = false
                c.interval = 0
                c.due = .distantPast
                c.order = front
                front -= 1
            }
        }
    }

    private static func day(_ days: Int, after now: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: Calendar.current.startOfDay(for: now))!
    }

    /// Consecutive days with at least one review, counting today only once something's been reviewed.
    static func streak(_ logs: [String: DayLog], today: Date = .now) -> Int {
        let cal = Calendar.current
        var d = today
        if (logs[DayLog.key(for: d)]?.reviewed ?? 0) == 0 { d = cal.date(byAdding: .day, value: -1, to: d)! }
        var n = 0
        while (logs[DayLog.key(for: d)]?.reviewed ?? 0) > 0 {
            n += 1
            d = cal.date(byAdding: .day, value: -1, to: d)!
        }
        return n
    }
}
