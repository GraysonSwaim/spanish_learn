import Foundation
import SwiftData

/// Themes: filing words into chunks and merging chunks into bigger ones. The reads are pure functions over the chunks
/// and cards, so they're testable; the changes save the context.
@MainActor
enum Chunks {
    static func all(_ ctx: ModelContext) -> [Chunk] {
        (try? ctx.fetch(FetchDescriptor<Chunk>(sortBy: [SortDescriptor(\.order)]))) ?? []
    }

    // MARK: reading the tree

    /// The chunks on Home: no parent, or one that's gone (deleted on another device).
    nonisolated static func top(_ chunks: [Chunk]) -> [Chunk] {
        let ids = Set(chunks.map(\.id))
        return chunks.filter { $0.parentID.isEmpty || !ids.contains($0.parentID) }.sorted { $0.order < $1.order }
    }

    nonisolated static func children(of id: String, in chunks: [Chunk]) -> [Chunk] {
        chunks.filter { $0.parentID == id }.sorted { $0.order < $1.order }
    }

    /// The chunk and every chunk merged into it, at any depth.
    nonisolated static func family(_ id: String, in chunks: [Chunk]) -> Set<String> {
        var out: Set<String> = [id]
        var queue = [id]
        while let p = queue.popLast() {
            for c in chunks where c.parentID == p && out.insert(c.id).inserted { queue.append(c.id) }
        }
        return out
    }

    /// The word cards filed anywhere in a chunk, its smaller chunks included. Dropped ones too: the scheduler skips them.
    nonisolated static func words(in id: String, cards: [Card], chunks: [Chunk]) -> [Card] {
        let ids = family(id, in: chunks)
        return cards.filter { !$0.isConj && ids.contains($0.chunkID) }
    }

    /// Words in no chunk yet (Sueltas), the newest first. A word whose chunk is gone is loose again.
    nonisolated static func loose(_ cards: [Card], chunks: [Chunk]) -> [Card] {
        let ids = Set(chunks.map(\.id))
        return cards.filter { !$0.isConj && !$0.isDropped && !ids.contains($0.chunkID) }.sorted { $0.added > $1.added }
    }

    /// "Viaje a Quito › Hotel": where a chunk sits, for picking one to file into.
    nonisolated static func path(_ c: Chunk, in chunks: [Chunk]) -> String {
        var names = [c.name]
        var seen: Set<String> = [c.id]
        var p = c.parentID
        while let up = chunks.first(where: { $0.id == p }), seen.insert(up.id).inserted {
            names.insert(up.name, at: 0)
            p = up.parentID
        }
        return names.joined(separator: " › ")
    }

    /// The colour used least so far, going round from the one after the newest chunk's, so neighbours differ.
    nonisolated static func nextColor(_ chunks: [Chunk]) -> Int {
        var used = Array(repeating: 0, count: Palette.chunkCount)
        for c in chunks { used[((c.color % used.count) + used.count) % used.count] += 1 }
        let start = (chunks.max { $0.created < $1.created }?.color ?? -1) + 1
        return (0..<used.count).map { (start + $0) % used.count }.min { used[$0] < used[$1] } ?? 0
    }

    // MARK: changing it

    /// A new chunk at the end of Home (or inside `parent`), in the next colour round.
    @discardableResult
    static func create(_ name: String, parent: String = "", ctx: ModelContext) -> Chunk {
        let all = all(ctx)
        let c = Chunk(name: name, parentID: parent, color: nextColor(all), order: (all.map(\.order).max() ?? 0) + 1)
        ctx.insert(c)
        try? ctx.save()
        return c
    }

    static func file(_ cards: [Card], in chunk: Chunk?, ctx: ModelContext) {
        for c in cards { c.chunkID = chunk?.id ?? "" }
        try? ctx.save()
    }

    /// Drops `a` on `b`: a new, bigger chunk takes `b`'s place and holds them both.
    @discardableResult
    static func merge(_ a: Chunk, _ b: Chunk, name: String, ctx: ModelContext) -> Chunk? {
        guard a !== b else { return nil }
        let all = all(ctx)
        // Merging a chunk with one inside it would leave the inner one holding its own parent.
        if family(a.id, in: all).contains(b.id) || family(b.id, in: all).contains(a.id) { return nil }
        let big = Chunk(name: name, parentID: b.parentID, color: nextColor(all), order: b.order)
        ctx.insert(big)
        a.parentID = big.id
        b.parentID = big.id
        a.order = b.order + 1
        try? ctx.save()
        return big
    }

    /// Puts `a` inside `b`, after what's already there.
    @discardableResult
    static func nest(_ a: Chunk, in b: Chunk, ctx: ModelContext) -> Bool {
        let all = all(ctx)
        guard a !== b, !family(a.id, in: all).contains(b.id) else { return false }
        a.parentID = b.id
        a.order = (children(of: b.id, in: all).map(\.order).max() ?? b.order) + 1
        try? ctx.save()
        return true
    }

    /// Takes a chunk out of the one it's in, up one level.
    static func lift(_ c: Chunk, ctx: ModelContext) {
        let all = all(ctx)
        c.parentID = all.first { $0.id == c.parentID }?.parentID ?? ""
        try? ctx.save()
    }

    /// Undoes a chunk: what was inside moves up to where it was, and its words go with them (to Sueltas at the top).
    static func dissolve(_ c: Chunk, ctx: ModelContext) {
        let all = all(ctx)
        for (i, k) in children(of: c.id, in: all).enumerated() {
            k.parentID = c.parentID
            k.order = c.order + Double(i) / 100
        }
        for w in Deck.allCards(ctx) where w.chunkID == c.id { w.chunkID = c.parentID }
        ctx.delete(c)
        try? ctx.save()
    }

    /// The chunk a reading's words go into, named after it: made the first time.
    static func forReading(_ r: Reading, ctx: ModelContext) -> Chunk {
        if let c = all(ctx).first(where: { $0.readingID == r.id }) { return c }
        let c = create(r.title.isEmpty ? "Lectura" : r.title, ctx: ctx)
        c.readingID = r.id
        try? ctx.save()
        return c
    }
}
