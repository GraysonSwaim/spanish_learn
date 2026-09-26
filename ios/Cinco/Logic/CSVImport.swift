import Foundation

/// One row of a deck file.
nonisolated struct CardRecord: Equatable {
    var es = "", en = "", ex = "", notes = "", tags = "", frases = ""
    var tenses: [String: String] = [:]
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
            ? ["es": map["es"] ?? 0, "en": map["en"] ?? 1, "ex": map["ex"], "notes": map["notes"], "tags": map["tags"], "frases": map["frases"]]
            : ["es": 0, "en": 1, "ex": 2, "notes": 3, "tags": 4, "frases": nil]
        for (i, t) in Tense.all.enumerated() { idx[t.key] = hasHeader ? map[t.key] : 5 + i }

        return body.map { r in
            let g = { (k: String) -> String in
                guard let i = idx[k] ?? nil, i < r.count else { return "" }
                return r[i].trimmingCharacters(in: .whitespacesAndNewlines)
            }
            var rec = CardRecord(es: g("es"), en: g("en"), ex: g("ex"), notes: g("notes"), tags: g("tags"), frases: g("frases"))
            for t in Tense.all { let f = g(t.key); if !f.isEmpty { rec.tenses[t.key] = f } }
            return rec
        }
    }
}
