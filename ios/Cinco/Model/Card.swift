import Foundation
import SwiftData

/// One flashcard. A word card holds a Spanish term and its meaning; a verb is a word card that also
/// carries conjugation tables (`tenses`). Each tense a verb has becomes a conj card of its own
/// (id "<verb id>:<tense>"), studied in the Conjugación tab with its own stages.
///
/// CloudKit rules shape this model: every property has a default, nothing is `.unique`, and there are
/// no relationships (conj cards point at their verb by `verbID`). Because CloudKit can't enforce unique
/// ids, two devices can create the same card; `Deck.dedupe` merges them.
@Model
final class Card {
    /// Same id scheme as the web app, so its backups map card for card.
    var id: String = ""
    var kindRaw: String = Kind.word.rawValue
    var es: String = ""
    var en: String = ""
    var ex: String = ""
    var notes: String = ""
    var tags: String = ""
    /// Extra sentences using a verb, separated by "|".
    var frases: String = ""
    /// Tense key -> "yo|tú|él|nosotros|vosotros|ellos".
    var tenses: [String: String] = [:]

    /// Conj cards: the verb card they drill and which of its tenses.
    var verbID: String = ""
    var tense: String = ""

    /// 0 is new; 1…5 are the stages.
    var stage: Int = 0
    var due: Date = Date.distantPast
    /// Days until the next review once this stage is passed.
    var interval: Int = 0
    var reps: Int = 0
    var lapses: Int = 0
    var added: Date = Date.now
    var seen: Date?
    var lastReviewed: Date?
    var dropped: Date?
    /// Deck order: new cards are introduced in this order.
    var order: Double = 0

    enum Kind: String { case word, conj }

    var kind: Kind {
        get { Kind(rawValue: kindRaw) ?? .word }
        set { kindRaw = newValue.rawValue }
    }

    var isConj: Bool { kind == .conj }
    var isDropped: Bool { dropped != nil }
    /// A word card with at least one conjugation table.
    var isVerb: Bool { kind == .word && tenses.values.contains { !$0.isEmpty } }

    /// The tenses this verb has, in the standard order.
    var tenseList: [Tense] { Tense.all.filter { !(tenses[$0.key] ?? "").isEmpty } }

    func forms(_ tense: String) -> [String] { TextMatch.splitForms(tenses[tense]) }

    init(id: String, kind: Kind = .word, es: String, en: String, order: Double) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.es = es
        self.en = en
        self.order = order
    }
}

/// What happened on one calendar day, for the daily new-card allowance and the streak.
@Model
final class DayLog {
    /// "2026-09-26" in the device's time zone.
    var key: String = ""
    var reviewed: Int = 0
    var correct: Int = 0
    /// New cards introduced, counted per tab: each has its own daily allowance.
    var newVocab: Int = 0
    var newConj: Int = 0

    init(key: String) { self.key = key }

    static func key(for date: Date = .now) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
