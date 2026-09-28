import Foundation

/// One row of a deck file.
nonisolated struct CardRecord: Equatable, Hashable, Identifiable {
    var es = "", en = "", ex = "", notes = "", tags = "", frases = ""
    var tenses: [String: String] = [:]
    /// A phrase card (Frases tab) rather than a word: a "type" column saying "phrase" or "frase".
    var phrase = false
    /// From a mnemonic column or JSON key, or Editar tarjeta. An import only fills it on a card that has none.
    var mnemonic = ""
    var id: String { es }
}

/// Reads the CSV decks the web app reads: comma, semicolon or tab separated, quoted fields, "#" comments,
/// with or without a header (Anki exports have none).
nonisolated enum CSVImport {
    static func parse(_ text: String) -> [CardRecord] { records(rows(text)) }

    static func rows(_ raw: String) -> [[String]] {
        let text = raw.hasPrefix("\u{FEFF}") ? String(raw.dropFirst()) : raw
        let first = text.split(separator: "\n", omittingEmptySubsequences: false)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty && !$0.hasPrefix("#") } ?? ""
        let delim: Character = first.contains("\t") ? "\t"
            : first.split(separator: ";", omittingEmptySubsequences: false).count > first.split(separator: ",", omittingEmptySubsequences: false).count ? ";" : ","

        var rows: [[String]] = [], row: [String] = [], field = "", quoted = false
        var chars = Array(text.unicodeScalars).makeIterator()
        var pending: Unicode.Scalar? = nil
        func nextChar() -> Unicode.Scalar? {
            if let p = pending { pending = nil; return p }
            return chars.next()
        }
        while let ch = nextChar() {
            if quoted {
                if ch == "\"" {
                    let after = nextChar()
                    if after == "\"" { field.unicodeScalars.append("\"") } else { quoted = false; pending = after }
                } else { field.unicodeScalars.append(ch) }
            } else if ch == "\"" { quoted = true }
            else if Character(ch) == delim { row.append(field); field = "" }
            else if ch == "\n" { row.append(field); rows.append(row); row = []; field = "" }
            else if ch == "\r" {}
            else { field.unicodeScalars.append(ch) }
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows.filter { r in r.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty } && !(r.first ?? "").hasPrefix("#") }
    }

    /// Header names each column may go by. Tenses not listed answer to their key and their full name.
    static let aliases: [String: [String]] = {
        var a: [String: [String]] = [
            "es": ["spanish", "es", "español", "espanol", "front", "word", "term", "palabra"],
            "en": ["english", "en", "back", "meaning", "definition", "translation", "inglés", "ingles"],
            "ex": ["example", "ex", "sentence", "ejemplo", "context"],
            "notes": ["notes", "note", "hint", "notas"],
            "tags": ["tags", "tag", "category", "topic"],
            "frases": ["frases", "oraciones", "sentences"],
            "type": ["type", "kind", "tipo"],
            "mnemonic": ["mnemonic", "mnemonics", "mnemotecnia", "mnemotecnica", "mnemonico", "memory trick", "truco"],
            "presente": ["presente", "present", "conjugation", "conjugación", "conjugacion", "conj", "forms", "formas"],
            "preterito": ["preterito", "pretérito", "preterite"],
            "imperfecto": ["imperfecto", "imperfect"],
            "futuro": ["futuro", "future"],
            "condicional": ["condicional", "conditional"],
            "subjuntivo": ["subjuntivo", "subjunctive", "presente de subjuntivo"],
        ]
        for t in Tense.all where a[t.key] == nil { a[t.key] = [t.key, TextMatch.norm(t.name)] }
        return a
    }()

    static func records(_ rows: [[String]]) -> [CardRecord] {
        guard let head = rows.first?.map(TextMatch.norm) else { return [] }
        var map: [String: Int] = [:]
        for (k, names) in aliases {
            if let i = head.firstIndex(where: { names.contains($0) }) { map[k] = i }
        }
        let hasHeader = !map.isEmpty
        let body = hasHeader ? Array(rows.dropFirst()) : rows
        // Headerless files: spanish, english, example, notes, tags, then the tenses in order.
        var idx: [String: Int?] = hasHeader
            ? ["es": map["es"] ?? 0, "en": map["en"] ?? 1, "ex": map["ex"], "notes": map["notes"], "tags": map["tags"], "frases": map["frases"],
               "type": map["type"], "mnemonic": map["mnemonic"]]
            : ["es": 0, "en": 1, "ex": 2, "notes": 3, "tags": 4, "frases": nil, "type": nil, "mnemonic": nil]
        for (i, t) in Tense.all.enumerated() { idx[t.key] = hasHeader ? map[t.key] : 5 + i }

        return body.map { r in
            let g = { (k: String) -> String in
                guard let i = idx[k] ?? nil, i < r.count else { return "" }
                return r[i].trimmingCharacters(in: .whitespacesAndNewlines)
            }
            var rec = CardRecord(es: g("es"), en: g("en"), ex: g("ex"), notes: g("notes"), tags: g("tags"), frases: g("frases"))
            for t in Tense.all { let f = g(t.key); if !f.isEmpty { rec.tenses[t.key] = f } }
            rec.phrase = ["phrase", "frase", "expresion", "expression"].contains(TextMatch.strip(g("type")))
            rec.mnemonic = g("mnemonic")
            return rec
        }
    }
}

/// Cards as JSON, which models write more reliably than CSV once a verb brings fifteen tables: one object,
/// an array of them, or {"cards": [...]}. Keys answer to the same names as CSV headers; "tenses" (or
/// "conjugations") maps a tense key or name to its six forms, as a list or "a|b|c|d|e|f"; "frases" is a list.
nonisolated enum CardJSON {
    static func parse(_ text: String) -> [CardRecord]? {
        guard let start = text.firstIndex(where: { $0 == "{" || $0 == "[" }),
              let data = String(text[start...]).data(using: .utf8),
              let any = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return nil }
        let objects: [[String: Any]]
        if let list = any as? [[String: Any]] { objects = list }
        else if let one = any as? [String: Any] { objects = (one["cards"] as? [[String: Any]]) ?? [one] }
        else { return nil }
        return objects.map(record)
    }

    private static func key(_ raw: String) -> String? {
        let n = TextMatch.norm(raw.replacingOccurrences(of: "_", with: " "))
        return CSVImport.aliases.first { _, names in names.contains(n) || names.contains(TextMatch.norm(raw)) }?.key
    }

    private static func text(_ v: Any?) -> String {
        switch v {
        case let s as String: s.trimmingCharacters(in: .whitespacesAndNewlines)
        case let list as [Any]: list.map { text($0) }.filter { !$0.isEmpty }.joined(separator: "|")
        case let n as NSNumber: n.stringValue
        default: ""
        }
    }

    private static func record(_ o: [String: Any]) -> CardRecord {
        var r = CardRecord()
        for (k, v) in o {
            let n = TextMatch.norm(k)
            if ["tenses", "conjugations", "conjugaciones", "tiempos"].contains(n), let t = v as? [String: Any] {
                for (tk, forms) in t {
                    // Six forms: a list keeps empty slots (imperativo has no yo); a string is already "a|b|…".
                    let f = (forms as? [Any]).map { $0.map { ($0 as? String ?? "").trimmingCharacters(in: .whitespaces) }.joined(separator: "|") } ?? text(forms)
                    if let tense = key(tk), Tense.named(tense) != nil, f.contains(where: { $0 != "|" }) { r.tenses[tense] = f }
                }
                continue
            }
            switch key(k) {
            case "es": r.es = text(v)
            case "en": r.en = text(v)
            case "ex": r.ex = text(v)
            case "notes": r.notes = text(v)
            // Tags are space-separated; models also write "slang, surprise" or a list.
            case "tags": r.tags = ((v as? [Any]).map { $0.map { text($0) }.joined(separator: " ") } ?? text(v))
                .split { $0 == "," || $0 == ";" || $0.isWhitespace }.joined(separator: " ")
            case "frases": r.frases = text(v)
            case "mnemonic": r.mnemonic = text(v)
            case "type": r.phrase = ["phrase", "frase", "expresion", "expression"].contains(TextMatch.strip(text(v)))
            case let t? where Tense.named(t) != nil: let f = text(v); if !f.isEmpty { r.tenses[t] = f }
            default: break
            }
        }
        return r
    }
}
