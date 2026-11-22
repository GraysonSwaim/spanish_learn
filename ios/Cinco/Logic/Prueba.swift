import Foundation
import SwiftData

/// One question on a prueba's sheet.
nonisolated struct PruebaItem: Identifiable, Equatable {
    /// Why the word is on the sheet. A proof or graduation question, passed, graduates the word; the sample is random,
    /// and says how much of the library is holding.
    enum Kind: String, Codable { case proof, graduation, sample }
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

    private init(items: [PruebaItem], cards: [String: Card], ctx: ModelContext, now: Date) {
        self.items = items
        self.cards = cards
        self.ctx = ctx
        self.date = now
        meanings = items.filter { $0.format == .match }.shuffled()
    }

    /// A sheet for now, or nil when too little has been mastered to make one.
    static func make(_ ctx: ModelContext, now: Date = .now) -> Prueba? {
        var rng = SystemRandomNumberGenerator()
        let picked = pick(Deck.allCards(ctx).filter { $0.kind == .word }, now: now, using: &rng)
        guard picked.count >= least else { return nil }
        return Prueba(items: layout(picked, using: &rng), cards: Dictionary(picked.map { ($0.card.id, $0.card) }) { a, _ in a },
                      ctx: ctx, now: now)
    }

    // MARK: choosing the words

    /// The owed words first, latest first, then a random sample of every other mastered word, graduated ones included.
    /// A "Ya la sé" isn't sampled before its week is up: right after saying it, a right answer proves nothing.
    static func pick(_ words: [Card], size: Int = size, now: Date = .now,
                     using rng: inout some RandomNumberGenerator) -> [(card: Card, kind: PruebaItem.Kind)] {
        let owed = words.filter { Scheduler.owedToTest($0, now: now) }.sorted { $0.due < $1.due }.prefix(min(maxOwed, size))
        let taken = Set(owed.map(\.id))
        let rest = words.filter { c in
            !c.isDropped && c.stage == 5 && !taken.contains(c.id) && !Scheduler.isClaimed(c)
        }.shuffled(using: &rng).prefix(size - owed.count)
        return owed.map { ($0, Scheduler.isClaimed($0) ? .proof : .graduation) } + rest.map { ($0, .sample) }
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
                                  spanish: c.es, english: c.en)
            if hasGap(c) { (item.sentence, item.form) = (c.ex, c.exWord) }
            return item
        }
        if out.count { $0.format == .match } < 3 {
            for i in out.indices where out[i].format == .match { out[i].format = .write }
        }
        // Rare words with a sentence first: a gap is kinder to them than writing.
        let gaps = out.indices.filter { out[$0].kind == .sample && !out[$0].sentence.isEmpty }
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
              let got = try? await Tutor.quiz(want.map { Tutor.QuizInput(spanish: $0.spanish, english: $0.english, sentence: $0.sentence, form: $0.form) }),
              got.count == want.count
        else { return }
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
           let again = try? await Tutor.grade(doubtful.map { Tutor.GradeInput(english: $0.english, spanish: $0.spanish, typed: typed[$0.id] ?? "") }),
           again.count == doubtful.count {
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
    }

    /// What the phone can mark alone. A written answer is right with a slip when only an accent or the article is off.
    static func markHere(_ item: PruebaItem, typed: String?, matched: String?, chosen: String?) -> PruebaMark {
        switch item.format {
        case .write:
            switch TextMatch.check(typed ?? "", against: item.spanish) {
            case .exact: return PruebaMark(right: true)
            case .accent: return PruebaMark(right: true, near: true, note: "Ojo con el acento.")
            case .article: return PruebaMark(right: true, near: true, note: "Ojo con el artículo.")
            case .skip, .wrong: return PruebaMark(right: false)
            }
        case .match: return PruebaMark(right: matched == item.id)
        case .cloze: return PruebaMark(right: chosen == item.form)
        }
    }

    private func apply(_ out: [String: PruebaMark]) {
        let day = Deck.today(ctx)
        for item in items {
            guard let c = cards[item.id], c.modelContext != nil, let m = out[item.id] else { continue }
            let was = Scheduler.isGraduated(c)
            Scheduler.tested(c, right: m.right, now: date)
            if !was && Scheduler.isGraduated(c) { learned.append(c.es) }
            day.reviewed += 1
            if m.right { day.correct += 1 }
        }
        try? ctx.save()
        marks = out
        let sample = items.filter { $0.kind == .sample }
        PruebaLog.add(PruebaRecord(date: date, total: items.count, right: out.values.count(where: \.right), learned: learned.count,
                                   sampleTotal: sample.count, sampleRight: sample.count { out[$0.id]?.right == true }))
        state = .marked
    }

    var score: Int { marks.values.count(where: \.right) }
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
        UserDefaults.standard.set(try? JSONEncoder().encode(Array((all + [r]).suffix(keep))), forKey: key)
    }

    /// The share of sampled words right over the last 30 days, and how many were asked. nil before any.
    static func held(_ records: [PruebaRecord], now: Date = .now) -> (share: Double, asked: Int)? {
        let recent = records.filter { now.timeIntervalSince($0.date) <= window }
        let asked = recent.reduce(0) { $0 + $1.sampleTotal }
        guard asked > 0 else { return nil }
        return (Double(recent.reduce(0) { $0 + $1.sampleRight }) / Double(asked), asked)
    }
}
