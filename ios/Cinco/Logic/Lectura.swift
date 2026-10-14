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

    /// One line per line of the text, as it was written: a paragraph of an article, or a line of a poem or a song.
    static func lines(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
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

    /// A mark is a span, "line.first-last": a word tapped (first == last) or a phrase picked by sliding across it. Marks
    /// from before spans were one word each, "line.word", and neighbours among them still join into one run.
    static func markKey(line: Int, first: Int, last: Int) -> String { "\(line).\(first)-\(last)" }

    /// The line and word places a mark covers.
    static func span(_ mark: String) -> (line: Int, words: ClosedRange<Int>)? {
        let parts = mark.split(separator: ".", maxSplits: 1)
        guard parts.count == 2, let line = Int(parts[0]) else { return nil }
        let ends = parts[1].split(separator: "-").compactMap { Int($0) }
        switch ends.count {
        case 1: return (line, ends[0]...ends[0])
        case 2 where ends[0] <= ends[1]: return (line, ends[0]...ends[1])
        default: return nil
        }
    }

    /// The marked word places in one line.
    static func marked(_ marks: [String], line: Int) -> Set<Int> {
        var out = Set<Int>()
        for m in marks { if let s = span(m), s.line == line { out.formUnion(s.words) } }
        return out
    }

    /// Marks words `first...last` of a line as one span, replacing any mark they overlap.
    static func mark(_ marks: inout [String], line: Int, first: Int, last: Int) {
        marks.removeAll { m in span(m).map { $0.line == line && $0.words.overlaps(first...last) } ?? false }
        marks.append(markKey(line: line, first: first, last: last))
    }

    /// Removes whatever mark covers a word: the whole phrase it belongs to.
    static func unmark(_ marks: inout [String], line: Int, text: String, word: Int) {
        guard let run = spans(marks, line: line, text: text).first(where: { $0.contains(word) }) else { return }
        marks.removeAll { m in span(m).map { $0.line == line && run.contains($0.words.lowerBound) } ?? false }
    }

    /// Every run of marked words, in reading order.
    static func runs(lines: [String], marks: [String]) -> [Run] {
        lines.enumerated().flatMap { l, line in
            let ws = words(line)
            return spans(marks, line: l, text: line).compactMap { r -> Run? in
                guard r.upperBound < ws.count else { return nil }
                let text = String(line[ws[r.lowerBound].lowerBound..<ws[r.upperBound].upperBound])
                return Run(line: l, first: r.lowerBound, last: r.upperBound, text: text)
            }
        }
    }

    /// One line's runs as word places, in order: each span as it is, and old one-word marks joined with their neighbours.
    static func spans(_ marks: [String], line: Int, text: String) -> [ClosedRange<Int>] {
        var out: [ClosedRange<Int>] = []
        var single = Set<Int>()
        for m in marks {
            guard let s = span(m), s.line == line else { continue }
            if m.contains("-") { out.append(s.words) } else { single.insert(s.words.lowerBound) }
        }
        if !single.isEmpty {
            let ws = words(text)
            var w = 0
            while w < ws.count {
                guard single.contains(w) else { w += 1; continue }
                var end = w
                while end + 1 < ws.count, single.contains(end + 1), joins(text[ws[end].upperBound..<ws[end + 1].lowerBound]) { end += 1 }
                out.append(w...end)
                w = end + 1
            }
        }
        return out.sorted { $0.lowerBound < $1.lowerBound }
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
