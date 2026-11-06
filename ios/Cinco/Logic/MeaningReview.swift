import Foundation

/// `MeaningCheck` for a card and, in Ajustes › Revisar mi biblioteca, for the whole library. What it finds is kept per card
/// with the meaning that was checked, so a review can stop and carry on, a word looked at and kept isn't doubted again, and
/// a meaning that changes is checked afresh. It stays on this device: a doubt is no part of the card.
@MainActor
enum MeaningReview {
    nonisolated struct Entry: Codable, Equatable {
        var en: String
        var doubtful: Bool
    }

    private static let key = "meaningReview"

    static var entries: [String: Entry] {
        get {
            UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode([String: Entry].self, from: $0) } ?? [:]
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: key) }
    }

    /// The word cards whose current meaning hasn't been checked.
    static func toCheck(_ cards: [Card], entries: [String: Entry]) -> [Card] {
        cards.filter { !$0.isConj && !$0.isDropped && entries[$0.id]?.en != $0.en }
    }

    /// The word cards whose current meaning is in doubt.
    static func doubtful(_ cards: [Card], entries: [String: Entry]) -> [Card] {
        cards.filter { c in
            guard !c.isConj, !c.isDropped, let e = entries[c.id] else { return false }
            return e.doubtful && e.en == c.en
        }
    }

    /// The learner has looked at this meaning, or chosen it: it isn't doubted again unless it changes.
    static func settle(_ c: Card) {
        entries[c.id] = Entry(en: c.en, doubtful: false)
    }

    // MARK: checking

    /// What Apple Translate is asked for a card: its word, the form it was met in, and that sentence.
    static func texts(of c: Card) -> [String] {
        var seen = Set<String>()
        return [c.es, c.exWord, c.ex]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert(TextMatch.strip($0)).inserted }
    }

    /// The verdict on a card from Apple Translate's answers (`english`), with the on-device model settling what they leave
    /// open.
    static func verdict(for c: Card, english: [String: String]) async -> MeaningCheck.Verdict {
        let example = c.ex.trimmingCharacters(in: .whitespacesAndNewlines)
        let word = texts(of: c).filter { $0 != example }.compactMap { english[$0] }
        let sentence = english[example] ?? ""
        if let settled = MeaningCheck.settled(meaning: c.en, word: word, sentence: sentence) { return settled }
        let accepts = await Tutor.onDeviceAccepts(spanish: c.es, sentence: c.ex, english: c.en)
        return MeaningCheck.unsettled(meaning: c.en, word: word, sentence: sentence, modelAccepts: accepts)
    }
}
