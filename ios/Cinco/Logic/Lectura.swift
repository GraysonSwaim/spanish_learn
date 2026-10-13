import Foundation
import NaturalLanguage
import SwiftData

/// A run of marked words next to each other in one line: one word, or a phrase like "echar de menos".
nonisolated struct Run: Hashable, Identifiable {
    let line: Int
    let first: Int
    let last: Int
    /// The words as they stand in the line, with what's between them.
    let text: String

    /// Also the key for its gloss and for `Reading.carded`.
    var id: String { "\(line).\(first)-\(last)" }
}

/// Text rules for Lecturas: splitting a pasted text into lines and words, and grouping marked words into runs.
nonisolated enum Lectura {
    /// Readings not opened for this long are deleted.
    static let keepDays = 30
    /// And never more than this many, the oldest going first.
    static let keepCount = 40

    /// One line per sentence, keeping the text's own line breaks (a poem or lyrics stay as written).
    static func lines(_ text: String) -> [String] {
        var out: [String] = []
        for para in text.split(whereSeparator: \.isNewline) {
            let p = String(para)
            let tok = NLTokenizer(unit: .sentence)
            tok.string = p
            tok.setLanguage(.spanish)
            tok.enumerateTokens(in: p.startIndex..<p.endIndex) { r, _ in
                let s = p[r].trimmingCharacters(in: .whitespacesAndNewlines)
                if !s.isEmpty { out.append(s) }
                return true
            }
        }
        return out
    }

    /// Where each word is in a line. Punctuation and spaces fall between words.
    static func words(_ line: String) -> [Range<String.Index>] {
        let tok = NLTokenizer(unit: .word)
        tok.string = line
        tok.setLanguage(.spanish)
        return tok.tokens(for: line.startIndex..<line.endIndex)
    }

    /// Two marked words join into one run only when nothing but spaces (or a hyphen or apostrophe) is between them.
    static func joins(_ gap: Substring) -> Bool {
        gap.allSatisfy { $0.isWhitespace || "-'’".contains($0) }
    }

    static func markKey(line: Int, word: Int) -> String { "\(line).\(word)" }

    /// The marked word places in one line.
    static func marked(_ marks: [String], line: Int) -> Set<Int> {
        let prefix = "\(line)."
        return Set(marks.compactMap { $0.hasPrefix(prefix) ? Int($0.dropFirst(prefix.count)) : nil })
    }

    /// Every run of marked words, in reading order.
    static func runs(lines: [String], marks: [String]) -> [Run] {
        var out: [Run] = []
        for (l, line) in lines.enumerated() {
            let ws = words(line)
            let on = marked(marks, line: l)
            var w = 0
            while w < ws.count {
                guard on.contains(w) else { w += 1; continue }
                var end = w
                while end + 1 < ws.count, on.contains(end + 1), joins(line[ws[end].upperBound..<ws[end + 1].lowerBound]) { end += 1 }
                out.append(Run(line: l, first: w, last: end, text: String(line[ws[w].lowerBound..<ws[end].upperBound])))
                w = end + 1
            }
        }
        return out
    }

    /// The word places in `line` that spell out `text` (case and accents aside), the first time they do.
    static func find(_ text: String, in line: String) -> [Int]? {
        let ws = words(line).map { TextMatch.strip(String(line[$0])) }
        let want = words(text).map { TextMatch.strip(String(text[$0])) }
        guard !want.isEmpty, want.count <= ws.count else { return nil }
        for start in 0...(ws.count - want.count) where Array(ws[start..<start + want.count]) == want {
            return Array(start..<start + want.count)
        }
        return nil
    }

    /// The deck's one-word fronts, stripped and without articles, to show which words of a reading are already cards.
    static func knownWords(_ cards: [Card]) -> Set<String> {
        var out = Set<String>()
        for c in cards where !c.isConj && !c.isDropped {
            for alt in TextMatch.alternatives(c.es) {
                let bare = TextMatch.noArticle(alt)
                if !bare.isEmpty && !bare.contains(" ") { out.insert(bare) }
            }
        }
        return out
    }

    /// A card for a run: Claude's draft when there is one, else the words as they stand, sorted the way an import sorts.
    static func record(_ run: Run, gloss: Tutor.Gloss?, sentence: String) -> CardRecord {
        var rec = CardRecord(es: gloss?.spanish ?? run.text, en: gloss?.english ?? "", ex: sentence,
                             notes: gloss?.note ?? "", tags: "lectura")
        if let gloss {
            rec.phrase = gloss.phrase
        } else {
            rec.sort(type: "")
        }
        return rec
    }
}

@MainActor
extension Lectura {
    /// Deletes readings not opened in `keepDays`, and the oldest past `keepCount`.
    static func recycle(_ ctx: ModelContext, now: Date = .now) {
        let all = (try? ctx.fetch(FetchDescriptor<Reading>(sortBy: [SortDescriptor(\.opened, order: .reverse)]))) ?? []
        let cutoff = now.addingTimeInterval(-Double(keepDays) * 86_400)
        var changed = false
        for (i, r) in all.enumerated() where i >= keepCount || r.opened < cutoff {
            ctx.delete(r)
            changed = true
        }
        if changed { try? ctx.save() }
    }
}
