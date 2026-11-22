import Foundation
import SwiftData

/// One question on a prueba's sheet.
nonisolated struct PruebaItem: Identifiable, Equatable {
    /// Why the word is on the sheet. A proof or graduation question, passed, graduates the word; the sample is random,
    /// and says how much of the library is holding. A new sheet asked for after one is marked brings back its misses
    /// (`retry`) and words no sheet has asked yet (`unseen`); neither counts in the estimate, as neither is random.
    enum Kind: String, Codable { case proof, graduation, sample, retry, unseen }
    /// I. Escribe en español: the English, and the Spanish typed. II. Une: matched to its meaning. III. Completa: the word
    /// picked for the gap in a sentence.
    enum Format { case write, match, cloze }

    /// The card's id.
    let id: String
    let kind: Kind
    var format: Format
    let spanish: String
    let english: String
    /// For a gap: the sentence, the word as it's written there, the four choices, and the sentence's English.
    var sentence = ""
    var form = ""
    var options: [String] = []
    var sentenceEnglish = ""
    /// For explaining a miss: the card's own sentence and its English, its note, and its mnemonic.
    var example = ""
    var exampleEnglish = ""
    var note = ""
    var mnemonic = ""

    /// The sentence with its word taken out.
    var gapped: String {
        guard let r = sentence.range(of: form, options: .caseInsensitive) else { return sentence }
        return sentence.replacingCharacters(in: r, with: "_____")
    }
}

/// How an answer was marked: right or not, and what the red pen writes beside it.
nonisolated struct PruebaMark: Equatable {
    var right: Bool
    /// Right, but with a slip worth pointing out (an accent, the article).
    var near = false
    var note = ""
}

/// A prueba as kept on this device, for Home: how it went, and the sample's share right, which is the estimate of how much
/// of the library is held.
nonisolated struct PruebaRecord: Codable, Equatable {
    var date: Date
    var total: Int
    var right: Int
    /// Words that graduated on this sheet.
    var learned: Int
    var sampleTotal: Int
    var sampleRight: Int
    /// What Claude cost for it. Missing from sheets kept before it was counted.
    var cost: Double?
}

/// A short test on paper, after each session or whenever asked for: the words owed a test (a "Ya la sé" whose week is
/// up, or a word at the two-week wait) and a random sample of the rest of what's been mastered. Nothing is marked until
/// it's handed in, and only then do the words move.
@MainActor
@Observable
final class Prueba {
    enum State { case answering, marking, marked }

    static let size = 12
    /// At most half the sheet is owed words, so the sample is always at least half.
    static let maxOwed = size / 2
    static let maxGaps = 3
    /// Fewer words than this mastered, and there's no sheet.
    static let least = 3

    private(set) var items: [PruebaItem]
    private let cards: [String: Card]
    private let ctx: ModelContext
    let date: Date

    var typed: [String: String] = [:]
    /// Section II: each Spanish word's id to the id of the meaning it was matched with.
    var matched: [String: String] = [:]
    /// Section III: the choice picked for each gap.
    var chosen: [String: String] = [:]
    private(set) var state = State.answering
    private(set) var marks: [String: PruebaMark] = [:]
    /// Words that graduated when it was handed in.
    private(set) var learned: [String] = []
    /// What Claude cost for this sheet: its gaps, and its second look at written answers.
    private(set) var cost = 0.0
    /// Claude's tip for each miss, to remember it by. Asked for once the sheet is marked.
    private(set) var tips: [String: String] = [:]
    private(set) var explaining = false

    private init(items: [PruebaItem], cards: [String: Card], ctx: ModelContext, now: Date) {
        self.items = items
        self.cards = cards
        self.ctx = ctx
        self.date = now
        meanings = items.filter { $0.format == .match }.shuffled()
    }

    /// A sheet for now, or nil when too little has been mastered to make one. `refresh`: a new sheet asked for after one
    /// is marked, which asks its misses (`again`) first and brings in words no sheet has asked yet.
    static func make(_ ctx: ModelContext, refresh: Bool = false, again: [String] = [], now: Date = .now) -> Prueba? {
        var rng = SystemRandomNumberGenerator()
        let picked = pick(Deck.allCards(ctx).filter { $0.kind == .word }, again: again, unseenFirst: refresh,
                          asked: PruebaLog.asked, now: now, using: &rng)
        guard picked.count >= least else { return nil }
        return Prueba(items: layout(picked, using: &rng), cards: Dictionary(picked.map { ($0.card.id, $0.card) }) { a, _ in a },
                      ctx: ctx, now: now)
    }

    // MARK: choosing the words

    /// The owed words first, latest first, then a random sample of every other mastered word, graduated ones included.
    /// A "Ya la sé" isn't sampled before its week is up: right after saying it, a right answer proves nothing.
    /// A new sheet after a marked one asks its misses first (`again`), then the owed words, then (`unseenFirst`) words no
    /// sheet has asked yet, and fills up with the sample.
    static func pick(_ words: [Card], size: Int = size, again: [String] = [], unseenFirst: Bool = false,
                     asked: Set<String> = [], now: Date = .now,
                     using rng: inout some RandomNumberGenerator) -> [(card: Card, kind: PruebaItem.Kind)] {
        let byID = Dictionary(words.map { ($0.id, $0) }) { a, _ in a }
        let retry = again.compactMap { byID[$0] }.filter { !$0.isDropped && $0.stage > 0 }.prefix(size)
        var taken = Set(retry.map(\.id))
        let owed = words.filter { !taken.contains($0.id) && Scheduler.owedToTest($0, now: now) }
            .sorted { $0.due < $1.due }.prefix(min(maxOwed, size - retry.count))
        taken.formUnion(owed.map(\.id))
        let sampleable = { (c: Card) in !c.isDropped && c.stage == 5 && !taken.contains(c.id) && !Scheduler.isClaimed(c) }
        var out = retry.map { ($0, PruebaItem.Kind.retry) } + owed.map { ($0, Scheduler.isClaimed($0) ? .proof : .graduation) }
        if unseenFirst {
            let unseen = words.filter { sampleable($0) && !asked.contains($0.id) }.shuffled(using: &rng).prefix(size - out.count)
            taken.formUnion(unseen.map(\.id))
            out += unseen.map { ($0, .unseen) }
        }
        let rest = words.filter(sampleable).shuffled(using: &rng).prefix(size - out.count)
        return out + rest.map { ($0, .sample) }
    }

    /// Common words are written: they're the ones needed to say things. Rare ones are matched: reading needs them
    /// recognised. Proofs are always written. A few sampled words with a sentence are put up for a gap, which only
    /// happens if Claude sends back the wrong choices (`fillGaps`). Matching takes three or more, so fewer are written.
    static func layout(_ picked: [(card: Card, kind: PruebaItem.Kind)],
                       using rng: inout some RandomNumberGenerator) -> [PruebaItem] {
        var out = picked.map { p in
            let c = p.card
            let common = c.level == 1 || c.pages >= 3
            var item = PruebaItem(id: c.id, kind: p.kind, format: p.kind == .proof || common ? .write : .match,
                                  spanish: c.es, english: c.en, example: c.ex, exampleEnglish: c.exEn,
                                  note: c.notes, mnemonic: c.mnemonic)
            if hasGap(c) { (item.sentence, item.form) = (c.ex, c.exWord) }
            return item
        }
        if out.count { $0.format == .match } < 3 {
            for i in out.indices where out[i].format == .match { out[i].format = .write }
        }
        // Rare words with a sentence first: a gap is kinder to them than writing.
        let gaps = out.indices.filter { [.sample, .unseen].contains(out[$0].kind) && !out[$0].sentence.isEmpty }
            .sorted { (out[$0].format == .match ? 0 : 1) < (out[$1].format == .match ? 0 : 1) }
        let candidates = Set(gaps.prefix(maxGaps))
        for i in out.indices where !candidates.contains(i) { (out[i].sentence, out[i].form) = ("", "") }
        return out
    }

    /// A card's own sentence with its word in it, for a gap.
    static func hasGap(_ c: Card) -> Bool {
        !c.ex.isEmpty && !c.exWord.isEmpty && c.ex.range(of: c.exWord, options: .caseInsensitive) != nil
    }

    // MARK: sections

    func section(_ f: PruebaItem.Format) -> [PruebaItem] { items.filter { $0.format == f } }

    /// The question's number on the sheet, counting through the sections in order.
    func number(_ id: String) -> Int {
        let order = section(.write) + section(.match) + section(.cloze)
        return (order.firstIndex { $0.id == id } ?? 0) + 1
    }

    /// Section II's meanings, in an order of their own.
    private(set) var meanings: [PruebaItem] = []

    /// Claude Sonnet's wrong choices turn the candidates into gaps. Without them, a candidate keeps its other question.
    func fillGaps() async {
        let want = items.filter { !$0.sentence.isEmpty && $0.format != .cloze }
        guard !want.isEmpty, state == .answering,
              let (got, spent) = try? await Tutor.quiz(want.map { Tutor.QuizInput(spanish: $0.spanish, english: $0.english, sentence: $0.sentence, form: $0.form) }),
              got.count == want.count
        else { return }
        cost += spent
        var rng = SystemRandomNumberGenerator()
        for (w, g) in zip(want, got) where g.options.count == 3 {
            guard let i = items.firstIndex(where: { $0.id == w.id }) else { continue }
            items[i].format = .cloze
            items[i].options = ([w.form] + g.options).shuffled(using: &rng)
            items[i].sentenceEnglish = g.english
        }
        // A match section left with fewer than three is written instead.
        if section(.match).count < 3 {
            for i in items.indices where items[i].format == .match { items[i].format = .write }
        }
        meanings = section(.match).shuffled()
    }

    // MARK: handing it in

    /// Marks the sheet: the phone first, then Claude Sonnet looks again at written answers the phone marked wrong, since
    /// a right word the card doesn't list (a synonym, another region's word) is still right. Then every word moves.
    func handIn() async {
        guard state == .answering else { return }
        state = .marking
        var out: [String: PruebaMark] = [:]
        for item in items { out[item.id] = Self.markHere(item, typed: typed[item.id], matched: matched[item.id], chosen: chosen[item.id]) }
        let doubtful = items.filter { $0.format == .write && out[$0.id]?.right == false && !TextMatch.norm(typed[$0.id] ?? "").isEmpty }
        if !doubtful.isEmpty,
           let (again, spent) = try? await Tutor.grade(doubtful.map { Tutor.GradeInput(english: $0.english, spanish: $0.spanish, typed: typed[$0.id] ?? "") }),
           again.count == doubtful.count {
            cost += spent
            for (item, g) in zip(doubtful, again) {
                switch g.verdict {
                case .right: out[item.id] = PruebaMark(right: true, note: g.note)
                case .close: out[item.id] = PruebaMark(right: true, near: true, note: g.note)
                case .wrong: out[item.id]?.note = g.note
                case .none: break
                }
            }
        }
        apply(out)
        await explain()
    }

    /// What the phone can mark alone. A written answer is judged on the word itself: the article isn't asked for, nor a
    /// little word joined to it ("entre de" for "entre", "darse cuenta" for "darse cuenta de"), so neither makes it wrong
    /// or even a slip. Only a missing or wrong accent is pointed out, and it's still right.
    static func markHere(_ item: PruebaItem, typed: String?, matched: String?, chosen: String?) -> PruebaMark {
        switch item.format {
        case .write:
            let t = typed ?? ""
            guard !TextMatch.norm(t).isEmpty else { return PruebaMark(right: false) }
            let alts = TextMatch.alternatives(item.spanish)
            if alts.contains(where: { bare($0, accents: true) == bare(t, accents: true) }) { return PruebaMark(right: true) }
            if let a = alts.first(where: { bare($0, accents: false) == bare(t, accents: false) }) {
                return PruebaMark(right: true, near: true, note: "Se escribe con acento: \(TextMatch.noArticleKeepingAccents(a)).")
            }
            return PruebaMark(right: false)
        case .match: return PruebaMark(right: matched == item.id)
        case .cloze: return PruebaMark(right: chosen == item.form)
        }
    }

    /// The word itself, for marking: no case, punctuation, article, or a little word after it. With `accents` false, no
    /// accents either (ñ stays).
    nonisolated static func bare(_ s: String, accents: Bool) -> String {
        let base = accents ? TextMatch.norm(s) : TextMatch.strip(s)
        return base.replacing(/^(el|la|los|las|un|una|unos|unas|lo)\s+/, with: "")
            .replacing(/\s+(de|del|a|al|en|con|por|para|que)$/, with: "")
    }

    private func apply(_ out: [String: PruebaMark]) {
        let day = Deck.today(ctx)
        for item in items {
            guard let c = cards[item.id], c.modelContext != nil, let m = out[item.id] else { continue }
            let was = Scheduler.isGraduated(c)
            // A miss asked again straight away has already paid for it: missing it twice in a few minutes costs nothing more.
            if !(item.kind == .retry && !m.right) { Scheduler.tested(c, right: m.right, now: date) }
            if !was && Scheduler.isGraduated(c) { learned.append(c.es) }
            day.reviewed += 1
            if m.right { day.correct += 1 }
        }
        try? ctx.save()
        marks = out
        let sample = items.filter { $0.kind == .sample }
        PruebaLog.markAsked(items.map(\.id))
        PruebaLog.add(PruebaRecord(date: date, total: items.count, right: out.values.count(where: \.right), learned: learned.count,
                                   sampleTotal: sample.count, sampleRight: sample.count { out[$0.id]?.right == true }, cost: cost))
        state = .marked
    }

    var score: Int { marks.values.count(where: \.right) }

    /// The ids missed, in the sheet's order, for a new sheet that asks them again.
    var missed: [String] {
        (section(.write) + section(.match) + section(.cloze)).filter { marks[$0.id]?.right == false }.map(\.id)
    }

    /// What was answered, as the learner put it: typed, the meaning matched, or the word picked.
    func answer(_ item: PruebaItem) -> String {
        switch item.format {
        case .write: typed[item.id] ?? ""
        case .match: items.first { $0.id == matched[item.id] }?.english ?? ""
        case .cloze: chosen[item.id] ?? ""
        }
    }

    /// Claude's tip for each miss: why the answer is what it is, set against what was answered, and a way to remember it.
    /// Without Claude, a miss is still explained by its card: its sentence, its note and its mnemonic.
    func explain() async {
        let wrong = items.filter { marks[$0.id]?.right == false }
        guard !wrong.isEmpty, tips.isEmpty, !explaining else { return }
        explaining = true
        defer { explaining = false }
        let input = wrong.map {
            Tutor.ExplainInput(spanish: $0.spanish, english: $0.english, answered: answer($0),
                               sentence: $0.format == .cloze ? $0.sentence : $0.example,
                               question: $0.format == .write ? "write" : $0.format == .match ? "match" : "gap")
        }
        guard let (got, spent) = try? await Tutor.explain(input), got.count == wrong.count else { return }
        cost += spent
        PruebaLog.addCost(spent, at: date)
        for (item, tip) in zip(wrong, got) where !tip.isEmpty { tips[item.id] = tip }
    }

    /// Keeps Claude's tip as the word's mnemonic, so practice shows it too. Only for a word that has none.
    func keepTip(_ id: String) {
        guard let tip = tips[id], let c = cards[id], c.modelContext != nil, c.mnemonic.isEmpty,
              let i = items.firstIndex(where: { $0.id == id }) else { return }
        c.mnemonic = tip
        items[i].mnemonic = tip
        try? ctx.save()
    }
}

/// Every prueba handed in on this device. Kept here, like `PageScores`, so the CloudKit schema needn't change.
enum PruebaLog {
    static let key = "pruebas"
    private static let keep = 1000
    /// How far back the estimate looks.
    static let window: TimeInterval = 30 * 86_400

    static func decode(_ data: Data) -> [PruebaRecord] {
        (try? JSONDecoder().decode([PruebaRecord].self, from: data)) ?? []
    }

    static var all: [PruebaRecord] { UserDefaults.standard.data(forKey: key).map(decode) ?? [] }

    static func add(_ r: PruebaRecord) {
        save(Array((all + [r]).suffix(keep)))
    }

    private static func save(_ records: [PruebaRecord]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(records), forKey: key)
    }

    /// The explanations come after the sheet is kept, so their cost is added to it then.
    static func addCost(_ dollars: Double, at date: Date) {
        var records = all
        guard let i = records.lastIndex(where: { $0.date == date }) else { return }
        records[i].cost = (records[i].cost ?? 0) + dollars
        save(records)
    }

    private static let askedKey = "pruebaAsked"

    /// Every word a sheet has asked on this device, for a new sheet to bring in the ones not asked yet.
    static var asked: Set<String> { Set(UserDefaults.standard.stringArray(forKey: askedKey) ?? []) }

    static func markAsked(_ ids: [String]) {
        UserDefaults.standard.set(Array(asked.union(ids)), forKey: askedKey)
    }

    /// The share of sampled words right over the last 30 days, and how many were asked. nil before any.
    static func held(_ records: [PruebaRecord], now: Date = .now) -> (share: Double, asked: Int)? {
        let recent = records.filter { now.timeIntervalSince($0.date) <= window }
        let asked = recent.reduce(0) { $0 + $1.sampleTotal }
        guard asked > 0 else { return nil }
        return (Double(recent.reduce(0) { $0 + $1.sampleRight }) / Double(asked), asked)
    }
}
