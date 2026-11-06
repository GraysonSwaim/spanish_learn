import Foundation
import SwiftData

/// A different word on a scanned page: its dictionary form, how hard it is, and how it's written there.
nonisolated struct PageWord: Codable, Equatable {
    var spanish: String
    /// 1 foundational, 2 intermediate, 3 advanced.
    var level: Int
    var forms: [String]

    /// One entry per word when a scan came back in several stretches, in reading order.
    static func merged(_ batches: [[PageWord]]) -> [PageWord] {
        var out: [PageWord] = []
        var place: [String: Int] = [:]
        for w in batches.joined() {
            let key = TextMatch.noArticle(w.spanish)
            if let i = place[key] {
                out[i].forms += w.forms.filter { !out[i].forms.contains($0) }
            } else {
                place[key] = out.count
                out.append(w)
            }
        }
        return out
    }
}

/// What a tapped word's colour says: still being looked up, already in the library, or new to it.
nonisolated enum MarkColor: Hashable {
    case pending, seen, new
}

/// The one library of words: each word once, however many pages it turns up on, all studied together with the
/// foundational words first. Pages feed it and tapped words add to it.
@MainActor
enum Library {
    static let levelNames = [1: "Básicas", 2: "Intermedias", 3: "Avanzadas"]
    private static let unknownLevel = 2

    // MARK: each word once

    /// What a card's Spanish is found under: without its article, and each of its "/" alternatives.
    nonisolated static func keys(_ es: String) -> [String] {
        ([es] + TextMatch.alternatives(es)).map(TextMatch.noArticle).filter { !$0.isEmpty }
    }

    /// Every word card by its keys, set-aside ones too, so a word discarded doesn't come back.
    static func index(_ cards: [Card]) -> [String: Card] {
        var out: [String: Card] = [:]
        for c in cards where !c.isConj {
            for k in keys(c.es) where out[k] == nil { out[k] = c }
        }
        return out
    }

    static func find(_ es: String, in index: [String: Card]) -> Card? {
        keys(es).lazy.compactMap { index[$0] }.first
    }

    // MARK: studying

    /// One session over the whole library. `first` (card ids) comes before the rest: the words of the page about to be
    /// read. Then new words go foundational first, so the commonest words are learned first.
    static func plan(_ cards: [Card], first: Set<String> = []) -> (pool: [Card], queue: [Card], fresh: [Card]) {
        let pool = cards.filter { $0.kind == .word }
        let daily = Scheduler.dailyQueue(pool)
        let queue = daily.filter { first.contains($0.id) } + daily.filter { !first.contains($0.id) }
        let fresh = Scheduler.unseen(pool, staggerTenses: false, verbs: []).enumerated().sorted { a, b in
            let rank = { (c: Card) in (first.contains(c.id) ? 0 : 1, c.level ?? unknownLevel) }
            let (x, y) = (rank(a.element), rank(b.element))
            return x != y ? x < y : a.offset < b.offset
        }.map(\.element)
        return (pool, queue, fresh)
    }

    // MARK: feeding it a page

    /// The page's words not in the library yet, foundational first, and in reading order within a level.
    static func newWords(_ page: [PageWord], index: [String: Card]) -> [PageWord] {
        let new = page.filter { find($0.spanish, in: index) == nil }
        return new.enumerated().sorted { ($0.element.level, $0.offset) < ($1.element.level, $1.offset) }.map(\.element)
    }

    /// The library's cards for a page: its words that are in the library, and any tapped on it.
    static func cards(on reading: Reading, in cards: [Card]) -> [Card] {
        let index = index(cards)
        var out = (reading.pageWords ?? []).compactMap { find($0.spanish, in: index) }
        out += cards.filter { c in !c.isConj && c.sourceList.contains { $0.title == reading.title } }
        var seen = Set<String>()
        return out.filter { !$0.isDropped && seen.insert($0.id).inserted }
    }

    /// A page's cards still to learn, or back for review.
    static func toStudy(_ cards: [Card]) -> [Card] {
        cards.filter { $0.stage < 5 || Scheduler.isDue($0) }
    }

    /// Adds the page's next new words to the library, up to `limit`. The rest can follow later, or come in from another
    /// page. Returns how many were added.
    @discardableResult
    static func addNext(from reading: Reading, limit: Int, ctx: ModelContext) async throws(Tutor.Failure) -> Int {
        let batch = Array(newWords(reading.pageWords ?? [], index: index(Deck.allCards(ctx))).prefix(limit))
        guard !batch.isEmpty else { return 0 }
        let places = batch.map { place(of: $0, in: reading.lines) }
        let items = places.map { Tutor.GlossInput(text: $0.form, sentence: $0.sentence) }
        let glosses = try await Tutor.gloss(items)

        // Looked at again: a tap may have added one of them while Claude was answering.
        let index = index(Deck.allCards(ctx))
        var recs: [CardRecord] = []
        var sentences: [String: String] = [:]
        for (i, g) in glosses.prefix(batch.count).enumerated() where !g.english.isEmpty {
            let w = batch[i]
            guard find(w.spanish, in: index) == nil else { continue }
            let es = spanish(of: w.spanish, from: g)
            recs.append(CardRecord(es: es, en: g.english, ex: places[i].sentence, exWord: places[i].form, notes: g.note,
                                   tags: "lectura nivel\(w.level)"))
            sentences[TextMatch.cardID(es)] = places[i].sentence
        }
        Deck.importRecords(recs, into: ctx)
        let byID = Deck.cardsByID(ctx)
        for (id, sentence) in sentences { byID[id]?.addSource(title: reading.title, sentence: sentence) }
        try? ctx.save()
        return recs.count
    }

    /// The word as the page's list has it, with the article Claude's card gave it when that's all that differs.
    nonisolated private static func spanish(of lemma: String, from g: Tutor.Gloss) -> String {
        TextMatch.noArticle(g.spanish) == TextMatch.noArticle(lemma) ? g.spanish : lemma
    }

    /// Where a word first turns up: the form written there, and its sentence.
    nonisolated static func place(of w: PageWord, in lines: [String]) -> (form: String, sentence: String) {
        for (l, line) in lines.enumerated() {
            for form in w.forms {
                guard let places = Lectura.find(form, in: line), let first = places.first, let last = places.last else { continue }
                let run = Run(line: l, first: first, last: last, text: form)
                return (form, Lectura.sentence(of: run, in: line))
            }
        }
        let form = w.forms.first ?? w.spanish
        return (form, form)
    }

    // MARK: words tapped while reading

    /// Words tapped that aren't settled yet: not found in the library or added to it.
    static func unresolved(_ reading: Reading) -> [Run] {
        Lectura.runs(lines: reading.lines, marks: reading.marks).filter { !reading.carded.contains($0.id) }
    }

    /// Settles a tapped word. In the library already: it stays one card, gains this reading, and comes back for review
    /// (yellow). New: a card is added (green). The page's list knows most forms, so most taps needn't ask Claude.
    static func record(_ run: Run, in reading: Reading, claude: Bool = true, ctx: ModelContext) async throws(Tutor.Failure) {
        let sentence = reading.lines[safe: run.line].map { Lectura.sentence(of: run, in: $0) } ?? run.text
        let onPage = pageWord(run.text, in: reading.pageWords ?? [])

        if let c = find(onPage?.spanish ?? run.text, in: index(Deck.allCards(ctx))) {
            settle(run, in: reading, card: c, sentence: sentence, isNew: false)
            return
        }
        let gloss: Tutor.Gloss
        if let have = reading.glosses[run.id] {
            gloss = have
        } else if let g = try await Tutor.gloss([Tutor.GlossInput(text: run.text, sentence: sentence)], claude: claude).first {
            gloss = g
        } else {
            throw .other
        }
        // Now its dictionary form is known ("tengo" is tener), and another tap may have added it meanwhile.
        let es = onPage.map { spanish(of: $0.spanish, from: gloss) } ?? gloss.spanish
        if let c = find(es, in: index(Deck.allCards(ctx))) {
            settle(run, in: reading, card: c, sentence: sentence, isNew: false)
            return
        }
        guard !gloss.english.isEmpty else { throw .other }
        let level = onPage.map { " nivel\($0.level)" } ?? ""
        Deck.importRecords([CardRecord(es: es, en: gloss.english, ex: sentence, exWord: run.text, notes: gloss.note,
                                       tags: "lectura" + level)], into: ctx)
        guard let c = Deck.cardsByID(ctx)[TextMatch.cardID(es)] else { throw .other }
        settle(run, in: reading, card: c, sentence: sentence, isNew: true)
    }

    private static func settle(_ run: Run, in reading: Reading, card c: Card, sentence: String, isNew: Bool) {
        c.addSource(title: reading.title, sentence: sentence)
        // Due now: it comes up in the next session, at the stage it's at.
        if !isNew, c.stage > 0 { c.due = .now }
        var g = reading.glosses
        g[run.id] = Tutor.Gloss(spanish: c.es, english: c.en, note: c.notes, isNew: isNew)
        reading.glosses = g
        if !reading.carded.contains(run.id) { reading.carded.append(run.id) }
        try? c.modelContext?.save()
    }

    /// Takes back a tap. A word it had just added goes too, unless it's been studied since.
    static func forget(_ run: Run, in reading: Reading, ctx: ModelContext) {
        var g = reading.glosses
        if let gloss = g[run.id], gloss.isNew == true, let c = find(gloss.spanish, in: index(Deck.allCards(ctx))), c.stage == 0 {
            Deck.delete([c], ctx: ctx)
        }
        g[run.id] = nil
        reading.glosses = g
        reading.carded.removeAll { $0 == run.id }
        try? ctx.save()
    }

    nonisolated private static func pageWord(_ text: String, in page: [PageWord]) -> PageWord? {
        let key = TextMatch.strip(text)
        return page.first { $0.forms.contains { TextMatch.strip($0) == key } }
    }

    // MARK: levels for words that don't have one

    private static var running = false
    /// Cards already asked about while the app has been open.
    private static var asked = Set<String>()

    /// Words added by hand or before levels existed get theirs in the background, new ones first since only they wait
    /// for their turn by level.
    static func fillLevels(_ ctx: ModelContext) async {
        guard Tutor.consented, Tutor.base != nil, !running else { return }
        running = true
        defer { running = false }
        while true {
            let todo = Array(Deck.allCards(ctx)
                .filter { !$0.isConj && !$0.isDropped && $0.level == nil && !asked.contains($0.id) }
                .sorted { ($0.stage == 0 ? 0 : 1, $0.order) < ($1.stage == 0 ? 0 : 1, $1.order) }
                .prefix(40))
            guard !todo.isEmpty else { return }
            asked.formUnion(todo.map(\.id))
            guard let levels = try? await Tutor.levels(todo.map(\.es)) else { return }
            for (c, l) in zip(todo, levels) where c.modelContext != nil { c.level = l }
            try? ctx.save()
        }
    }
}
