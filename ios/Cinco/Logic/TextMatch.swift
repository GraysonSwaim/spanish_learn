import Foundation

/// How a typed answer compares with the card. Accents and a missing article are near misses, not failures.
nonisolated enum Verdict: String {
    case skip, exact, accent, article, wrong

    var isNear: Bool { self == .accent || self == .article }
}

/// Text rules shared with the web app. `strip` and `hash` must match it exactly: card ids and
/// recording file names are `hash(strip(text))`, so backups and audio/es-MX line up across both apps.
nonisolated enum TextMatch {
    private static let punctuation = Set("¿?¡!.,;:\"“”…")

    static func norm(_ s: String) -> String {
        let kept = s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines).filter { !punctuation.contains($0) }
        return kept.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// norm, then drop accents, keeping ñ.
    static func strip(_ s: String) -> String {
        let guarded = norm(s).replacingOccurrences(of: "ñ", with: "\u{1}")
        let scalars = guarded.decomposedStringWithCanonicalMapping.unicodeScalars.filter { !(0x300...0x36F).contains($0.value) }
        return String(String.UnicodeScalarView(scalars)).replacingOccurrences(of: "\u{1}", with: "ñ")
    }

    static func noArticle(_ s: String) -> String {
        strip(s).replacing(/^(el|la|los|las|un|una|unos|unas|lo)\s+/, with: "")
    }

    /// "el coche / el carro" and "hablar (con)" both accept each part on its own.
    static func alternatives(_ es: String) -> [String] {
        es.split(separator: /\s*[\/;]\s*|\s*\(.*?\)\s*/)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    static func check(_ input: String, against es: String) -> Verdict {
        if norm(input).isEmpty { return .skip }
        let alts = alternatives(es)
        if alts.contains(where: { norm($0) == norm(input) }) { return .exact }
        if alts.contains(where: { strip($0) == strip(input) }) { return .accent }
        if alts.contains(where: { noArticle($0) == noArticle(input) }) { return .article }
        return .wrong
    }

    /// In a conjugation table the pronoun (and the subjunctive's "que") is optional: "que nosotros tengamos" counts.
    static func dropPronoun(_ typed: String, person p: Int) -> String {
        var x = typed.trimmingCharacters(in: .whitespaces)
        if x.lowercased().wholeMatch(of: /que\s.*/.dotMatchesNewlines()) != nil { x = dropFirstWord(x) }
        let words = norm(x).split(separator: " ").map(String.init)
        if words.count > 1, Person.pronouns[p].contains(words[0]) { x = dropFirstWord(x) }
        return x
    }

    private static func dropFirstWord(_ s: String) -> String {
        s.replacing(/^\S+\s+/, with: "")
    }

    /// djb2 over UTF-16 code units in 32-bit arithmetic, printed in base 36, exactly like the web app's hash().
    static func hash(_ s: String) -> String {
        var h: Int32 = 5381
        for unit in s.utf16 { h = (h &<< 5) &+ h &+ Int32(unit) }
        return String(UInt32(bitPattern: h), radix: 36)
    }

    /// The id a word card gets from its Spanish.
    static func cardID(_ es: String) -> String { hash(strip(es)) }

    /// What gets spoken: the first alternative, without an ellipsis.
    static func spokenText(_ text: String) -> String {
        text.replacing(/\s*[\/;].*$/, with: "").replacingOccurrences(of: "…", with: "").trimmingCharacters(in: .whitespaces)
    }

    static func splitForms(_ x: String?) -> [String] {
        (x ?? "").split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
    }
}
