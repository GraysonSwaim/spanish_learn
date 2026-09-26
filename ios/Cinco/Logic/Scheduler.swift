import Foundation

enum Tab: String, CaseIterable {
    case vocab, conj

    var name: String { self == .vocab ? "Vocabulario" : "Conjugación" }
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
    /// Days before the next review once a card reaches this stage.
    let interval: Int
    let blurb: String

    static let all: [StageInfo] = [
        StageInfo(name: "Nueva", interval: 0, blurb: ""),
        StageInfo(name: "Aprender", interval: 0, blurb: "Conoces la palabra con las dos caras a la vista y te la preguntan más tarde en la misma sesión."),
        StageInfo(name: "Reconocer", interval: 1, blurb: "Ves el español y recuerdas el inglés. Vuelve al día siguiente."),
        StageInfo(name: "Recordar", interval: 3, blurb: "Ves el inglés y dices el español en voz alta antes de mirar. Vuelve a los 3 días."),
        StageInfo(name: "Producir", interval: 7, blurb: "Ves el inglés y escribes el español. Los acentos cuentan, pero un casi se marca en vez de fallarse. Vuelve a los 7 días."),
        StageInfo(name: "Dominada", interval: 21, blurb: "Escribir o reconocer, al azar. Vuelve a los 21 días y luego el plazo se duplica cada vez, hasta 120 días. Un fallo la baja una etapa."),
    ]
}

struct DeckCounts {
    var due = 0, unseen = 0, total = 0, dropped = 0
    var byStage = [0, 0, 0, 0, 0, 0]
}

/// The five-stage schedule, the same rules as the web app. Pure functions over cards, so they're testable.
enum Scheduler {
    /// Cards between a miss and its retry.
    static let relearnGap = 5
    /// Mastered cards never sleep longer than this many days.
    static let maxInterval = 120
    /// A card due within this window is studied now rather than making you come back.
    static let lookahead: TimeInterval = 15 * 60
    static let retryDelay: TimeInterval = 10 * 60

    static func inTab(_ c: Card, tab: Tab, tense: String) -> Bool {
        switch tab {
        case .vocab: !c.isConj
        case .conj: c.isConj && (tense == Tense.random || c.tense == tense)
        }
    }

    static func counts(_ cards: [Card], now: Date = .now) -> DeckCounts {
        var n = DeckCounts()
        for c in cards {
            if c.isDropped { n.dropped += 1; continue }
            n.total += 1
            n.byStage[c.stage] += 1
            if c.stage == 0 { n.unseen += 1 } else if c.due <= now { n.due += 1 }
        }
        return n
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

    /// Reviews first (oldest due first), then today's share of new cards, so a backlog never gets buried.
    static func dailyQueue(_ cards: [Card], newRoom: Int, staggerTenses: Bool, verbs: [Card], now: Date = .now) -> [Card] {
        let due = cards.filter { !$0.isDropped && $0.stage > 0 && $0.due <= now.addingTimeInterval(lookahead) }
            .sorted { $0.due < $1.due }
        return due + unseen(cards, staggerTenses: staggerTenses, verbs: verbs).prefix(max(0, newRoom))
    }

    /// Everything at one stage, due or not, for practising a single column.
    static func stageQueue(_ cards: [Card], stage: Int) -> [Card] {
        cards.filter { !$0.isDropped && $0.stage == stage }.sorted { $0.due < $1.due }
    }

    /// A new card has been shown with both sides: it joins stage 1 and is asked again later this session.
    static func introduce(_ c: Card, now: Date = .now) {
        c.stage = 1
        c.interval = 0
        c.due = now.addingTimeInterval(retryDelay)
        c.seen = now
    }

    static func pass(_ c: Card, now: Date = .now) {
        c.reps += 1
        c.lastReviewed = now
        if c.stage < 5 {
            c.stage += 1
            c.interval = StageInfo.all[c.stage].interval
        } else {
            c.interval = min(maxInterval, (c.interval > 0 ? c.interval : 21) * 2)
        }
        c.due = c.interval > 0
            ? Calendar.current.date(byAdding: .day, value: c.interval, to: Calendar.current.startOfDay(for: now))!
            : now.addingTimeInterval(retryDelay)
    }

    /// A miss drops one stage (never below 1) and comes back a few cards later.
    static func fail(_ c: Card, now: Date = .now) {
        c.reps += 1
        c.lastReviewed = now
        c.lapses += 1
        c.stage = max(1, c.stage - 1)
        c.interval = 0
        c.due = now.addingTimeInterval(retryDelay)
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
