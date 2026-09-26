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
                c.en = rec.en
                if !rec.ex.isEmpty { c.ex = rec.ex }
                if !rec.notes.isEmpty { c.notes = rec.notes }
                if !rec.tags.isEmpty { c.tags = rec.tags }
                if !rec.frases.isEmpty { c.frases = rec.frases }
                r.updated += 1
            } else {
                card = Card(id: id, es: rec.es, en: rec.en, order: nextOrder)
                card.ex = rec.ex; card.notes = rec.notes; card.tags = rec.tags; card.frases = rec.frases
                nextOrder += 1
                ctx.insert(card)
                byID[id] = card
                r.added += 1
            }
            if !rec.tenses.isEmpty {
                card.tenses.merge(rec.tenses) { _, new in new }
                syncConj(card, byID: &byID, ctx: ctx)
                r.verbs += 1
            }
        }
        try? ctx.save()
        return r
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
        card.es = rec.es; card.en = rec.en; card.ex = rec.ex; card.notes = rec.notes
        card.tags = rec.tags; card.frases = rec.frases; card.tenses = rec.tenses
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
                ctx.delete(l)
            }
            changed = true
        }
        if changed { try? ctx.save() }
    }

    /// The 62 high-frequency words the web app ships with.
    static func loadStarter(_ ctx: ModelContext) -> ImportResult? {
        guard let url = Bundle.main.url(forResource: "starter", withExtension: "csv"),
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
