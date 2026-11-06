import Foundation
// A session isn't marked Sendable, though it's only ever used by one task at a time here.
@preconcurrency import Translation

/// A second opinion on a card's meaning, from Apple's tools on the phone. Claude writes the meanings because it's far
/// more accurate: tested 2026-11-06 on 52 tricky words in their sentences, Claude got all of them, Apple Translate 65–73%
/// and the on-device model 67%. But they fail differently from Claude, which is what a check needs. These rules doubted
/// 52 of 52 meanings taken from another sentence and 23 of 24 taken from another word of the same sentence, and also 6 of
/// the 52 right meanings, mostly rare words or senses that Apple gets wrong.
///
/// So a doubt is only ever a doubt, and it's the learner who changes a card. The comparison comes first because it's
/// deterministic; the on-device model only settles what it can't, since by itself it rejected 12 of the 52 right meanings
/// and accepted a third of the same-sentence mix-ups.
nonisolated enum MeaningCheck {
    enum Verdict: Equatable {
        /// Apple Translate says the same.
        case agrees
        /// Apple Translate says something else, but the on-device model accepts the meaning.
        case modelAccepts
        /// Neither supports it, or the only opinion there is doesn't.
        case doubtful
        /// Nothing on this phone could give an opinion.
        case noOpinion
    }

    /// What Apple Translate alone settles, or nil when it takes the on-device model. `word` is its translations of the
    /// card's word, `sentence` of its sentence ("" if none). Only a match on the word counts: the sentence's translation
    /// holds every word around it too, so "paper" would pass for oler in "El papel huele a tabaco". And when the sentence
    /// has Apple's word for it, that's the sense in use, so a card saying something else is doubtful.
    static func settled(meaning: String, word: [String], sentence: String) -> Verdict? {
        if agrees(meaning: meaning, with: word) { return .agrees }
        return agrees(meaning: word.joined(separator: " "), with: [sentence]) ? .doubtful : nil
    }

    /// The verdict when `settled` couldn't give one: `modelAccepts` is nil when the model couldn't answer. Without it, the
    /// sentence is the only evidence left for a sense that a word by itself doesn't show.
    static func unsettled(meaning: String, word: [String], sentence: String, modelAccepts: Bool?) -> Verdict {
        switch modelAccepts {
        case true?: return .modelAccepts
        case false?: return .doubtful
        case nil:
            if word.isEmpty && sentence.isEmpty { return .noOpinion }
            return agrees(meaning: meaning, with: [sentence]) ? .agrees : .doubtful
        }
    }

    /// Whether a meaning shares a real word with any of the translations: "to smell (of)" and "It smelled of coffee" do,
    /// "paper" and "to smell" don't.
    static func agrees(meaning: String, with translations: [String]) -> Bool {
        let wanted = words(meaning)
        return translations.contains { !wanted.isDisjoint(with: words($0)) }
    }

    /// The English words that carry meaning, as `stem`s. What's in brackets only explains ("to miss (someone)").
    static func words(_ english: String) -> Set<String> {
        let text = english.lowercased().replacing(/\([^)]*\)/, with: " ")
        let all = text.split { !$0.isLetter }.map(String.init).filter { $0.count > 1 && !filler.contains($0) }
        return Set(all.map(stem))
    }

    /// The same for "smell", "smells" and "smelled", "carry" and "carried", by rule rather than with `NLTagger`, whose
    /// English data isn't on every device: an answer here shouldn't depend on the phone.
    static func stem(_ word: String) -> String {
        var w = Substring(word)
        if w.count > 4, w.hasSuffix("ies") { w = w.dropLast(3) + "y" }
        else if w.count > 5, w.hasSuffix("ing") { w = w.dropLast(3) }
        else if w.count > 4, w.hasSuffix("ed") { w = w.dropLast(2) }
        else if w.count > 3, w.hasSuffix("s"), !w.hasSuffix("ss") { w = w.dropLast(w.hasSuffix("es") ? 2 : 1) }
        if w.count > 2, let last = w.last, last == w.dropLast().last, !"aeiou".contains(last) { w = w.dropLast() }
        if w.last == "e" { w = w.dropLast() }
        if w.last == "y" { w = w.dropLast() + "i" }
        return String(w)
    }

    /// Apple Translate's English for each text.
    static func translate(_ texts: [String], with session: TranslationSession) async throws -> [String: String] {
        let requests = texts.indices.map { TranslationSession.Request(sourceText: texts[$0], clientIdentifier: String($0)) }
        var out: [String: String] = [:]
        for r in try await session.translations(from: requests) {
            if let i = r.clientIdentifier.flatMap({ Int($0) }) { out[texts[i]] = r.targetText }
        }
        return out
    }

    /// Apple Translate's word as a card would put it: "the paper" is "paper". Empty when it only gave the word back.
    static func candidate(_ translation: String, of spanish: String) -> String {
        let t = translation.trimmingCharacters(in: .whitespacesAndNewlines).replacing(/^(?i)(the|a|an)\s+/, with: "")
        return TextMatch.strip(t) == TextMatch.noArticle(spanish) ? "" : t
    }

    private static let filler: Set<String> = [
        "to", "the", "a", "an", "of", "one", "someone", "something", "sb", "sth", "in", "on", "at", "for", "with", "up",
        "out", "off", "from", "by", "be", "is", "are", "was", "were", "have", "has", "had", "do", "does", "did", "get",
        "go", "make", "and", "or", "it", "he", "she", "they", "we", "you", "his", "her", "their", "that", "this", "as",
        "not", "no", "into", "over", "here", "very", "so", "who", "what", "there", "would", "could", "will", "use", "used",
    ]
}
