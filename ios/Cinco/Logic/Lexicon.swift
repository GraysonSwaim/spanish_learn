import Foundation
import SQLite3

/// One word from the bundled dictionary. `id` is its frequency rank: 1 is the most common word.
nonisolated struct LexEntry: Identifiable, Hashable {
    struct Sense: Hashable, Decodable {
        let pos: String
        /// The English gloss, as Wiktionary words it.
        let g: String
        /// Labels worth showing: region (Mexico, Spain…) and register (colloquial, slang…).
        let t: [String]
        let gender: String
        let ex: [Example]
    }

    struct Example: Hashable, Decodable {
        let es: String
        let en: String
    }

    let id: Int
    let word: String
    let pos: [String]
    let gender: String
    let plural: String
    let fem: String
    let ipa: String
    let senses: [Sense]
    /// Tense key -> "yo|tú|él|nosotros|vosotros|ellos", confirmed by at least two sources.
    let tenses: [String: String]
    /// Where the word comes from (Wiktionary's etymology, in English), or "".
    let origin: String
    /// Everyday sentences using the word, with translations (Tatoeba).
    let sentences: [Example]

    /// Wiktionary's examples first (they illustrate a meaning), then Tatoeba's.
    var examples: [Example] {
        var seen = Set<String>()
        return (senses.flatMap(\.ex) + sentences).filter { seen.insert(TextMatch.strip($0.es)).inserted }
    }

    var isVerb: Bool { !tenses.isEmpty }

    /// Nouns carry their article, the way the decks write them: "la mano", "el agua".
    func spanish(for sense: Sense?) -> String {
        guard let sense, sense.pos == "noun" else { return word }
        switch sense.gender {
        case "m": return "el " + word
        // Feminine nouns starting with a stressed a take "el": el agua, el águila.
        case "f": return (ipa.hasPrefix("/ˈa") ? "el " : "la ") + word
        default: return word
        }
    }

    /// A gloss short enough for a card: no parentheses, at most two of its "; " parts.
    static func short(_ gloss: String) -> String {
        let bare = gloss.replacing(/\s*\([^)]*\)/, with: "")
        return bare.split(separator: ";").prefix(2).map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "; ")
    }
}

/// The dictionary shipped in the app (Resources/dictionary.sqlite), built by scripts/build_dictionary.py
/// from Wiktionary, Fred Jehle's verb database and verbecc. Read-only, never synced.
final class Lexicon {
    static let shared = Lexicon()

    private var db: OpaquePointer?
    private let decoder = JSONDecoder()
    private static let columns = "e.id, e.word, e.pos, e.gender, e.plural, e.fem, e.ipa, e.senses, e.tenses, e.origin, e.sentences"

    private init() {
        guard let url = Bundle.main.url(forResource: "dictionary", withExtension: "sqlite") else { return }
        if sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) != SQLITE_OK { db = nil }
    }

    var isAvailable: Bool { db != nil }

    /// Spanish words, inflected forms (pidió finds pedir) and English meanings, best matches first.
    func search(_ text: String, limit: Int = 40) -> [LexEntry] {
        let q = TextMatch.strip(text)
        guard !q.isEmpty else { return [] }
        let like = q.replacingOccurrences(of: "%", with: "").replacingOccurrences(of: "_", with: "")
        let sql = """
            SELECT \(Self.columns), 0 AS pri FROM entry e WHERE e.fold = ?1
            UNION ALL SELECT \(Self.columns), 1 FROM form f JOIN entry e ON e.id = f.entry WHERE f.fold = ?1
            UNION ALL SELECT \(Self.columns), 2 FROM entry e WHERE e.fold LIKE ?2
            UNION ALL SELECT \(Self.columns), 3 FROM entry e WHERE length(?1) >= 3 AND (' ' || e.en_fold) LIKE ?3
            ORDER BY pri, e.id LIMIT 200
            """
        var seen = Set<Int>()
        return query(sql, [q, like + "%", "% " + like + "%"]).filter { seen.insert($0.id).inserted }.prefix(limit).map { $0 }
    }

    /// The most common words, most common first.
    func top(_ n: Int, pos: String? = nil) -> [LexEntry] {
        if let pos {
            return query("SELECT \(Self.columns) FROM entry e WHERE ',' || e.pos || ',' LIKE ?1 ORDER BY e.id LIMIT \(n)", ["%,\(pos),%"])
        }
        return query("SELECT \(Self.columns) FROM entry e ORDER BY e.id LIMIT \(n)", [])
    }

    func entry(_ word: String) -> LexEntry? {
        query("SELECT \(Self.columns) FROM entry e WHERE e.fold = ?1 ORDER BY e.id LIMIT 1", [TextMatch.strip(word)]).first
    }

    /// The dictionary word a card is about: its Spanish without the article, first alternative only.
    func entry(for card: Card) -> LexEntry? {
        let es = TextMatch.alternatives(card.es).first ?? card.es
        return entry(es) ?? entry(TextMatch.noArticle(es))
    }

    var credits: String { meta("credits") }

    /// Ranks up to this are the most common words; above it are the extra words (dictionary_extra.csv).
    lazy var common: Int = Int(meta("common")) ?? .max

    private func meta(_ key: String) -> String {
        var s: OpaquePointer?
        defer { sqlite3_finalize(s) }
        guard let db, sqlite3_prepare_v2(db, "SELECT value FROM meta WHERE key = ?1", -1, &s, nil) == SQLITE_OK else { return "" }
        sqlite3_bind_text(s, 1, key, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        guard sqlite3_step(s) == SQLITE_ROW else { return "" }
        return String(cString: sqlite3_column_text(s, 0))
    }

    private func query(_ sql: String, _ args: [String]) -> [LexEntry] {
        guard let db else { return [] }
        var s: OpaquePointer?
        defer { sqlite3_finalize(s) }
        guard sqlite3_prepare_v2(db, sql, -1, &s, nil) == SQLITE_OK else { return [] }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (i, a) in args.enumerated() { sqlite3_bind_text(s, Int32(i + 1), a, -1, transient) }
        var out: [LexEntry] = []
        while sqlite3_step(s) == SQLITE_ROW {
            func text(_ i: Int32) -> String { sqlite3_column_text(s, i).map { String(cString: $0) } ?? "" }
            let senses = (try? decoder.decode([LexEntry.Sense].self, from: Data(text(7).utf8))) ?? []
            let tenses = (try? decoder.decode([String: String].self, from: Data(text(8).utf8))) ?? [:]
            let sentences = (try? decoder.decode([LexEntry.Example].self, from: Data(text(10).utf8))) ?? []
            out.append(LexEntry(id: Int(sqlite3_column_int(s, 0)), word: text(1), pos: text(2).split(separator: ",").map(String.init),
                                gender: text(3), plural: text(4), fem: text(5), ipa: text(6), senses: senses, tenses: tenses,
                                origin: text(9), sentences: sentences))
        }
        return out
    }
}

extension LexEntry {
    /// The tenses a new verb card gets unless the learner picks others: the six every deck fills.
    static let coreTenses: Set<String> = ["presente", "preterito", "imperfecto", "futuro", "condicional", "subjuntivo"]

    /// The card this entry makes, from the meanings and tenses the learner kept.
    func record(senses chosen: [Sense], tenses keys: Set<String>, es: String? = nil, en: String? = nil) -> CardRecord {
        var r = CardRecord()
        let first = chosen.first ?? senses.first
        r.es = es ?? spanish(for: first)
        r.en = en ?? Self.english(chosen.isEmpty ? Array(senses.prefix(1)) : chosen)
        r.ex = chosen.lazy.flatMap(\.ex).first?.es ?? ""
        var notes: [String] = []
        if first?.pos == "noun" {
            if first?.gender == "mf" { notes.append("el / la \(word)") }
            if !plural.isEmpty && plural != word { notes.append("Plural: \(plural)") }
        }
        if first?.pos == "adj", !fem.isEmpty, fem != word { notes.append("Femenino: \(fem)") }
        let labels = Set(chosen.flatMap(\.t)).intersection(["Mexico", "Spain", "Latin-America", "colloquial", "slang", "vulgar"])
        if !labels.isEmpty { notes.append(labels.sorted().map(Self.labelName).joined(separator: ", ")) }
        if !isVerb { r.notes = notes.joined(separator: ". ") }
        r.tags = isVerb && !keys.isEmpty ? "diccionario verbs" : "diccionario"
        // Several words, or Wiktionary calls it a phrase: it goes to Frases.
        r.phrase = pos.first == "phrase" || word.contains(" ")
        if isVerb {
            r.tenses = tenses.filter { keys.contains($0.key) }
            // Sentences that contain one of the verb's forms, so the fill-in-the-blank mode can use them.
            let forms = Set(tenses.values.flatMap { $0.split(separator: "|").flatMap { $0.split(separator: " / ") } }
                .map { TextMatch.strip(String($0.split(separator: " ").last ?? "")) })
            let frases = senses.flatMap(\.ex).map(\.es).filter { s in
                TextMatch.strip(s).split(separator: " ").contains { forms.contains(String($0)) }
            }
            r.frases = Array(frases.prefix(3)).joined(separator: "|")
        }
        return r
    }

    static func english(_ senses: [Sense]) -> String {
        senses.map { short($0.g) }.joined(separator: " / ")
    }

    static func labelName(_ t: String) -> String {
        ["Mexico": "México", "Spain": "España", "Latin-America": "Latinoamérica", "Caribbean": "Caribe",
         "Central-America": "Centroamérica", "Rioplatense": "Río de la Plata", "colloquial": "coloquial",
         "slang": "jerga", "vulgar": "vulgar", "derogatory": "despectivo", "formal": "formal", "informal": "informal",
         "figuratively": "figurado", "literary": "literario", "rare": "poco común", "dated": "anticuado",
         "reflexive": "reflexivo", "pronominal": "pronominal"][t] ?? t
    }

    static func posName(_ p: String) -> String {
        ["noun": "sustantivo", "verb": "verbo", "adj": "adjetivo", "adv": "adverbio", "pron": "pronombre",
         "prep": "preposición", "conj": "conjunción", "intj": "interjección", "det": "determinante",
         "num": "número", "article": "artículo", "contraction": "contracción", "phrase": "expresión"][p] ?? p
    }
}

/// Which language a word handed to `Lexicon.find` is in.
enum WordLanguage { case auto, spanish, english }

extension Lexicon {
    /// The entry a Spanish or English word most likely means, with the meaning that matched.
    /// Auto tries a Spanish headword and an English meaning, taking the more common word when both match
    /// (house is the English, not the Spanish loanword; sin is the Spanish), then an inflected Spanish form
    /// (hablé → hablar).
    func find(_ text: String, in language: WordLanguage = .auto) -> (entry: LexEntry, sense: LexEntry.Sense?)? {
        let q = TextMatch.strip(text)
        guard !q.isEmpty else { return nil }
        let es = language == .english ? nil : entry(q) ?? entry(TextMatch.noArticle(q))
        let en = language == .spanish ? nil : english(q)
        switch (es, en) {
        case let (e?, hit?): return hit.entry.id < e.id ? (hit.entry, hit.sense) : (e, e.senses.first)
        case let (e?, nil): return (e, e.senses.first)
        case let (nil, hit?): return (hit.entry, hit.sense)
        case (nil, nil): break
        }
        if language != .english,
           let e = query("SELECT \(Self.columns) FROM form f JOIN entry e ON e.id = f.entry WHERE f.fold = ?1 ORDER BY e.id LIMIT 1", [q]).first {
            return (e, e.senses.first)
        }
        return nil
    }

    /// The Spanish for an English word: an entry with it as a whole meaning ("bank", or "to run" for "run"),
    /// preferring its first meaning, then earlier meanings, then words that aren't the feminine or plural of
    /// another entry (mala, as against maleta), then common words.
    private func english(_ q: String) -> (entry: LexEntry, sense: LexEntry.Sense)? {
        let bare = q.replacing(/^to\s+/, with: "")
        guard bare.count >= 2 else { return nil }
        let like = bare.replacingOccurrences(of: "%", with: "").replacingOccurrences(of: "_", with: "")
        let candidates = query("SELECT \(Self.columns) FROM entry e WHERE (' ' || e.en_fold) LIKE ?1 ORDER BY e.id LIMIT 300", ["% \(like)%"])
        let inflections = Set(query("""
            SELECT \(Self.columns) FROM entry e WHERE e.fold IN (SELECT o.fem FROM entry o UNION SELECT o.plural FROM entry o)
              AND (' ' || e.en_fold) LIKE ?1
            """, ["% \(like)%"]).map(\.id))
        var best: (score: (Int, Int, Int), entry: LexEntry, sense: LexEntry.Sense)?
        for e in candidates {
            for (i, s) in e.senses.enumerated() {
                let items = s.g.replacing(/\s*\([^)]*\)/, with: "").split(whereSeparator: { $0 == "," || $0 == ";" })
                    .map { TextMatch.strip(String($0)).replacing(/^to\s+/, with: "") }
                guard let j = items.firstIndex(of: bare) else { continue }
                let score = (i == 0 && j == 0 ? 0 : i == 0 ? 1 : 2, inflections.contains(e.id) ? 1 : 0, e.id)
                if best == nil || score < best!.score { best = (score, e, s) }
                break
            }
        }
        return best.map { ($0.entry, $0.sense) }
    }
}
