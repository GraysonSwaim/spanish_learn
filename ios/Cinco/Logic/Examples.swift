import Foundation
import SwiftData

/// Every word card gets an example sentence, shown on the card while it's studied: Claude writes one for a card that
/// has none, and the English for one that has a sentence but not its translation. Runs in the background whenever the
/// deck changes, a batch at a time, the cards being studied first (Ajustes › Frases de ejemplo).
@MainActor
enum Examples {
    private static var running = false
    /// Cards already asked about while the app has been open, so one Claude can't help with isn't asked again and again.
    private static var asked = Set<String>()
    private static let batch = 20

    /// On unless switched off in Ajustes; until then, on only for someone who has already agreed to send text to Claude.
    static var enabled: Bool {
        let d = UserDefaults.standard
        return d.object(forKey: PrefKey.examples) == nil ? Tutor.consented : d.bool(forKey: PrefKey.examples)
    }

    /// Word cards missing a sentence or its English: stages 1–4 first, then the new cards in the order they'll come,
    /// then Dominada.
    static func needing(_ cards: [Card]) -> [Card] {
        let rank = { (c: Card) -> Int in c.stage == 0 ? 1 : c.stage == 5 ? 2 : 0 }
        return cards.filter { !$0.isConj && !$0.isDropped && ($0.ex.trimmed.isEmpty || $0.exEn.trimmed.isEmpty) }
            .sorted { (rank($0), $0.order) < (rank($1), $1.order) }
    }

    static func fill(_ ctx: ModelContext) async {
        guard enabled, Tutor.available, !running else { return }
        running = true
        defer { running = false }
        while true {
            let todo = Array(needing(Deck.allCards(ctx)).filter { !asked.contains($0.id) }.prefix(batch))
            guard !todo.isEmpty else { return }
            asked.formUnion(todo.map(\.id))
            let input = todo.map { Tutor.ExampleInput(spanish: $0.es, english: $0.en, sentence: $0.ex.trimmed) }
            guard let reply = try? await Tutor.examples(input) else { return }
            for (i, e) in reply.prefix(todo.count).enumerated() where todo[i].modelContext != nil {
                apply(e, to: todo[i], asked: input[i].sentence)
            }
            try? ctx.save()
        }
    }

    /// Fills only what's still empty, and only for the sentence that was sent: it may have been edited meanwhile.
    static func apply(_ e: Tutor.Example, to c: Card, asked sentence: String) {
        guard c.ex.trimmed == sentence else { return }
        if sentence.isEmpty {
            guard !e.sentence.trimmed.isEmpty else { return }
            c.ex = e.sentence.trimmed
        }
        if c.exEn.trimmed.isEmpty { c.exEn = e.english.trimmed }
        if c.exWord.trimmed.isEmpty { c.exWord = e.word.trimmed }
    }

    // MARK: picking the card out of its sentence

    /// Where the card's words are in its example: `exWord` when it's there, else the Spanish itself (without its article,
    /// any of its "/" alternatives), as whole words, ignoring case and accents.
    static func range(in c: Card) -> Range<String.Index>? {
        let candidates = [c.exWord] + c.es.split(separator: "/").map { bare(String($0)) }
        for w in candidates.map(\.trimmed) where !w.isEmpty {
            if let r = wholeWord(w, in: c.ex) { return r }
        }
        return nil
    }

    /// The card's Spanish as it might appear mid-sentence: no article, no ¿?¡!… around it.
    private static func bare(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "¿?¡!.…")))
        for a in ["el ", "la ", "los ", "las ", "un ", "una "] where t.lowercased().hasPrefix(a) {
            t = String(t.dropFirst(a.count))
            break
        }
        return t
    }

    private static func wholeWord(_ w: String, in s: String) -> Range<String.Index>? {
        var from = s.startIndex
        while let r = s.range(of: w, options: [.caseInsensitive, .diacriticInsensitive], range: from..<s.endIndex) {
            let before = r.lowerBound > s.startIndex ? s[s.index(before: r.lowerBound)] : " "
            let after = r.upperBound < s.endIndex ? s[r.upperBound] : " "
            if !before.isLetter && !after.isLetter { return r }
            from = s.index(after: r.lowerBound)
        }
        return nil
    }

    /// The sentence with the card's words styled by `style`, or blanked out when the Spanish is what's being asked.
    static func marked(_ c: Card, blank: Bool, style: (inout AttributedString) -> Void = { _ in }) -> AttributedString {
        guard let r = range(in: c) else { return AttributedString(c.ex) }
        var mid = AttributedString(blank ? "＿＿＿" : String(c.ex[r]))
        style(&mid)
        return AttributedString(String(c.ex[..<r.lowerBound])) + mid + AttributedString(String(c.ex[r.upperBound...]))
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
