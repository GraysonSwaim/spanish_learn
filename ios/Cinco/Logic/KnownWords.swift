import Foundation
import NaturalLanguage

/// Finds the library's words in a text, however they're written there, for a reading to highlight them.
///
/// Apple's lemmas do most of the finding: the library has oler, the page says "huele". Tested 2026-11-06 on a page against
/// Claude's own word list, spelling alone found 67% of the words and the lemmas took that to 99%, with 2% wrong; rules for
/// plurals and gender added almost nothing but mistakes. A scanned page has that word list, which knows the sense in use,
/// so there it comes first. All of this is on the phone, and a word it misses or wrongly finds only changes a highlight.
nonisolated struct KnownWords: Equatable, Sendable {
    private var words = Set<String>()
    /// Words of more than one word ("echar de menos"), by their first word.
    private var phrases: [String: [[String]]] = [:]

    /// `es` is a card's word; `form` how it was written where it was met, if known ("huele").
    init(_ cards: [(es: String, form: String)]) {
        for c in cards {
            for key in Library.keys(c.es) {
                add(key)
                // sentirse is also there in "se siente", whose lemma is sentir.
                if ["arse", "erse", "irse"].contains(where: key.hasSuffix) { add(String(key.dropLast(2))) }
            }
            add(TextMatch.strip(c.form))
        }
        for k in phrases.keys { phrases[k]?.sort { $0.count > $1.count } }
    }

    private mutating func add(_ text: String) {
        let parts = text.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        guard let first = parts.first else { return }
        if parts.count == 1 {
            words.insert(first)
        } else if phrases[first]?.contains(parts) != true {
            phrases[first, default: []].append(parts)
        }
    }

    /// Pronouns whose lemmas are some other word: "se" and "le" would be usted, and "lo" el.
    private static let spellingOnly: Set<String> = ["lo", "le", "les", "se", "me", "te", "nos", "os"]

    /// Where known words are in a line, as word places (those of `Lectura.words`). `page` is the scanned page's word list.
    /// `lemmas` stands in for Apple's, one per word, for testing.
    func spans(in line: String, page: [PageWord] = [], lemmas given: [String?]? = nil) -> [ClosedRange<Int>] {
        guard !words.isEmpty || !phrases.isEmpty else { return [] }
        let places = Lectura.words(line)
        let text = places.map { TextMatch.strip(String(line[$0])) }
        let lemmas = given ?? Self.lemmas(line, places)
        let listed = Self.listed(page)

        func phrase(at i: Int) -> Int? {
            let starts = [text[i], lemmas[i]].compactMap { $0 }
            let candidates = starts.flatMap { phrases[$0] ?? [] }.sorted { $0.count > $1.count }
            return candidates.first { p in
                guard i + p.count <= text.count else { return false }
                return p.indices.allSatisfy { k in
                    let at = i + k
                    if k > 0, !Lectura.joins(line[places[at - 1].upperBound..<places[at].lowerBound]) { return false }
                    return p[k] == text[at] || p[k] == lemmas[at]
                }
            }?.count
        }

        func known(_ i: Int) -> Bool {
            if let dictionary = listed[text[i]] { return !words.isDisjoint(with: dictionary) }
            if words.contains(text[i]) { return true }
            return !Self.spellingOnly.contains(text[i]) && lemmas[i].map(words.contains) == true
        }

        var out: [ClosedRange<Int>] = []
        var i = 0
        while i < text.count {
            let n = phrase(at: i) ?? (known(i) ? 1 : 0)
            if n > 0 { out.append(i...(i + n - 1)) }
            i += max(n, 1)
        }
        return out
    }

    /// The same for each line of a reading.
    func spans(lines: [String], page: [PageWord] = []) -> [[ClosedRange<Int>]] {
        lines.map { spans(in: $0, page: page) }
    }

    /// The known words of a paragraph on an article's page, as UTF-16 [start, end] pairs.
    func stretches(in text: String, page: [PageWord] = []) -> [[Int]] {
        let ranges = Lectura.words(text).map { NSRange($0, in: text) }
        return spans(in: text, page: page).map { [ranges[$0.lowerBound].location, NSMaxRange(ranges[$0.upperBound])] }
    }

    /// Each form on a page's list, with the dictionary words it's a form of.
    private static func listed(_ page: [PageWord]) -> [String: Set<String>] {
        var out: [String: Set<String>] = [:]
        for w in page {
            let keys = Library.keys(w.spanish)
            for form in w.forms {
                let f = TextMatch.strip(form)
                if !f.contains(" ") { out[f, default: []].formUnion(keys) }
            }
        }
        return out
    }

    private static func lemmas(_ line: String, _ places: [Range<String.Index>]) -> [String?] {
        guard !places.isEmpty else { return [] }
        let tagger = NLTagger(tagSchemes: [.lemma])
        tagger.string = line
        tagger.setLanguage(.spanish, range: line.startIndex..<line.endIndex)
        return places.map { tagger.tag(at: $0.lowerBound, unit: .word, scheme: .lemma).0.map { TextMatch.strip($0.rawValue) } }
    }

    /// Asks the phone for Apple's Spanish lemmas, if they aren't on it yet. Without them only words spelled as in the
    /// library are found.
    static func fetchLemmas() {
        Task.detached(priority: .utility) { _ = try? await NLTagger.requestAssets(for: .spanish, tagScheme: .lemma) }
    }
}

@MainActor
extension Library {
    /// What a reading highlights: the words that have been studied, or said to be known. A word only just added, or set
    /// aside, is in the library but isn't known.
    static func known(_ cards: [Card]) -> KnownWords {
        KnownWords(cards.filter { !$0.isConj && !$0.isDropped && $0.stage > 0 }.map { ($0.es, $0.exWord) })
    }
}
