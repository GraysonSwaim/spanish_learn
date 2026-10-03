import Foundation
import SwiftData

struct ImportResult {
    var added = 0, updated = 0, skipped = 0, verbs = 0

    var summary: String {
        "Añadidas: \(added). Actualizadas: \(updated)."
            + (verbs > 0 ? " Verbos con conjugación: \(verbs)." : "")
            + (skipped > 0 ? " Omitidas: \(skipped)." : "")
    }
}

/// Reads and writes the card store.
@MainActor
enum Deck {
    static func allCards(_ ctx: ModelContext) -> [Card] {
        (try? ctx.fetch(FetchDescriptor<Card>(sortBy: [SortDescriptor(\.order)]))) ?? []
    }

    static func cardsByID(_ ctx: ModelContext) -> [String: Card] {
        Dictionary(allCards(ctx).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// Today's log, created on first use.
    static func today(_ ctx: ModelContext, date: Date = .now) -> DayLog {
        let key = DayLog.key(for: date)
        if let log = try? ctx.fetch(FetchDescriptor<DayLog>(predicate: #Predicate { $0.key == key })).first { return log }
        let log = DayLog(key: key)
        ctx.insert(log)
        return log
    }

    static func logsByKey(_ ctx: ModelContext) -> [String: DayLog] {
        let logs = (try? ctx.fetch(FetchDescriptor<DayLog>())) ?? []
        return Dictionary(logs.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// Adds new cards and refreshes existing ones (matched by their Spanish) without touching their progress.
    @discardableResult
    static func importRecords(_ recs: [CardRecord], into ctx: ModelContext) -> ImportResult {
        var byID = cardsByID(ctx)
        var nextOrder = (byID.values.map(\.order).max() ?? 0) + 1
        var r = ImportResult()
        for rec in recs {
            guard !rec.es.isEmpty, !rec.en.isEmpty else { r.skipped += 1; continue }
            let id = TextMatch.cardID(rec.es)
            let card: Card
            if let c = byID[id] {
                card = c
                if rec.phrase && !rec.phraseGuessed && c.kind == .word { c.kind = .phrase }
                c.en = rec.en
                if !rec.ex.isEmpty { c.ex = rec.ex }
                if !rec.notes.isEmpty { c.notes = rec.notes }
                if !rec.tags.isEmpty { c.tags = rec.tags }
                if !rec.frases.isEmpty { c.frases = rec.frases }
                // Never over a trick the learner wrote.
                if c.mnemonic.isEmpty { c.mnemonic = rec.mnemonic }
                r.updated += 1
            } else {
                card = Card(id: id, kind: rec.phrase ? .phrase : .word, es: rec.es, en: rec.en, order: nextOrder)
                card.ex = rec.ex; card.notes = rec.notes; card.tags = rec.tags; card.frases = rec.frases
                card.mnemonic = rec.mnemonic
                nextOrder += 1
                ctx.insert(card)
                byID[id] = card
                r.added += 1
            }
            if !rec.tenses.isEmpty && !card.isPhrase {
                card.tenses.merge(rec.tenses) { _, new in new }
                syncConj(card, byID: &byID, ctx: ctx)
                r.verbs += 1
            }
        }
        try? ctx.save()
        return r
    }

    /// The word or phrase card a record is about: same id, or the same word once articles are set aside
    /// (a model's "maleta" is the deck's "la maleta").
    static func existing(_ rec: CardRecord, in cards: [Card]) -> Card? {
        let id = TextMatch.cardID(rec.es), bare = TextMatch.noArticle(TextMatch.strip(rec.es))
        return cards.first { !$0.isConj && $0.id == id }
            ?? cards.first { !$0.isConj && TextMatch.noArticle(TextMatch.strip($0.es)) == bare }
    }

    /// What importing a record would change on a card already in the deck, in words, for a confirmation.
    /// Mirrors importRecords: English and the other text fields are replaced when the record has them,
    /// a mnemonic only fills an empty one, tables are merged.
    static func changes(_ rec: CardRecord, to c: Card) -> [String] {
        var out: [String] = []
        func field(_ new: String, _ old: String, added: String, replaced: String) {
            guard !new.isEmpty, new != old else { return }
            out.append(old.isEmpty ? added : replaced)
        }
        if !rec.en.isEmpty && rec.en != c.en { out.append("inglés: «\(c.en)» → «\(rec.en)»") }
        field(rec.ex, c.ex, added: "ejemplo", replaced: "otro ejemplo")
        field(rec.notes, c.notes, added: "notas", replaced: "otras notas")
        field(rec.tags, c.tags, added: "etiquetas", replaced: "etiquetas: «\(c.tags)» → «\(rec.tags)»")
        field(rec.frases, c.frases, added: "frases", replaced: "otras frases")
        if c.mnemonic.isEmpty && !rec.mnemonic.isEmpty { out.append("mnemotecnia") }
        if rec.phrase && !rec.phraseGuessed && c.kind == .word { out.append("pasa a Frases") }
        if !c.isPhrase && !(rec.phrase && !rec.phraseGuessed) {
            let added = rec.tenses.keys.filter { (c.tenses[$0] ?? "").isEmpty }.count
            let fixed = rec.tenses.filter { k, v in !(c.tenses[k] ?? "").isEmpty && c.tenses[k] != v }.count
            if added > 0 { out.append("\(added) \(added == 1 ? "tiempo nuevo" : "tiempos nuevos") en Conjugación") }
            if fixed > 0 { out.append("\(fixed) \(fixed == 1 ? "tabla distinta" : "tablas distintas")") }
        }
        return out
    }

    /// Makes one conj card per tense the verb has, and removes those for tenses it no longer has.
    static func syncConj(_ v: Card, byID: inout [String: Card], ctx: ModelContext) {
        for (i, t) in Tense.all.enumerated() {
            let id = "\(v.id):\(t.key)"
            let hasTable = !(v.tenses[t.key] ?? "").isEmpty
            if let d = byID[id] {
                if hasTable {
                    d.es = v.es; d.en = t.name; d.tags = v.tags
                } else {
                    ctx.delete(d)
                    byID[id] = nil
                }
            } else if hasTable {
                // Tables sit right after their verb in deck order, present first.
                let d = Card(id: id, kind: .conj, es: v.es, en: t.name, order: v.order + Double(i + 1) / 100)
                d.verbID = v.id; d.tense = t.key; d.tags = v.tags
                ctx.insert(d)
                byID[id] = d
            }
        }
    }

    /// Saves an edited or hand-added word card. Changing the Spanish changes its id, so progress moves with it.
    static func save(_ rec: CardRecord, editing old: Card?, ctx: ModelContext) -> String? {
        var byID = cardsByID(ctx)
        let id = TextMatch.cardID(rec.es)
        if let clash = byID[id], clash !== old { return "«\(clash.es)» ya está en el mazo." }
        let card: Card
        if let old {
            card = old
            if old.id != id {
                // Re-point this verb's tables at the new id, keeping their progress.
                for t in Tense.all {
                    guard let d = byID.removeValue(forKey: "\(old.id):\(t.key)") else { continue }
                    d.id = "\(id):\(t.key)"
                    d.verbID = id
                    byID[d.id] = d
                }
                byID[old.id] = nil
                old.id = id
            }
        } else {
            card = Card(id: id, es: rec.es, en: rec.en, order: (byID.values.map(\.order).max() ?? 0) + 1)
            ctx.insert(card)
        }
        card.kind = rec.phrase ? .phrase : .word
        card.es = rec.es; card.en = rec.en; card.ex = rec.ex; card.notes = rec.notes
        card.tags = rec.tags; card.frases = rec.frases; card.tenses = rec.phrase ? [:] : rec.tenses
        if old != nil { card.mnemonic = rec.mnemonic }
        byID[id] = card
        syncConj(card, byID: &byID, ctx: ctx)
        try? ctx.save()
        return nil
    }

    /// CloudKit can't enforce unique ids, so the same card or day can arrive from two devices.
    /// Keeps the copy with the most practice (or the most activity, for days) and deletes the rest.
    static func dedupe(_ ctx: ModelContext) {
        var changed = false
        for (_, group) in Dictionary(grouping: allCards(ctx), by: \.id) where group.count > 1 {
            let keep = group.max { ($0.reps, -$0.added.timeIntervalSince1970) < ($1.reps, -$1.added.timeIntervalSince1970) }!
            for c in group where c !== keep {
                if c.dropped != nil && keep.dropped == nil && c.reps >= keep.reps { keep.dropped = c.dropped }
                if keep.mnemonic.isEmpty { keep.mnemonic = c.mnemonic }
                ctx.delete(c)
            }
            changed = true
        }
        let logs = (try? ctx.fetch(FetchDescriptor<DayLog>())) ?? []
        for (_, group) in Dictionary(grouping: logs, by: \.key) where group.count > 1 {
            let keep = group[0]
            for l in group.dropFirst() {
                keep.reviewed = max(keep.reviewed, l.reviewed); keep.correct = max(keep.correct, l.correct)
                keep.newVocab = max(keep.newVocab, l.newVocab); keep.newConj = max(keep.newConj, l.newConj)
                keep.newPhrase = max(keep.newPhrase, l.newPhrase)
                ctx.delete(l)
            }
            changed = true
        }
        if changed { try? ctx.save() }
    }

    /// The 62 high-frequency words the web app ships with.
    /// A deck bundled with the app: "starter" (words and verbs) or "frases-inicio" (phrases).
    static func loadStarter(_ ctx: ModelContext, deck: String = "starter") -> ImportResult? {
        guard let url = Bundle.main.url(forResource: deck, withExtension: "csv"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return importRecords(CSVImport.parse(text), into: ctx)
    }

    #if DEBUG
    /// Development: `-importCSV <path>` loads a deck from the Mac at launch (the simulator can read it).
    static func importFromLaunchArguments(_ ctx: ModelContext) {
        let args = ProcessInfo.processInfo.arguments
        for (i, a) in args.enumerated() where a == "-importCSV" && i + 1 < args.count {
            if let text = try? String(contentsOfFile: args[i + 1], encoding: .utf8) { importRecords(CSVImport.parse(text), into: ctx) }
        }
    }
    #endif
}
