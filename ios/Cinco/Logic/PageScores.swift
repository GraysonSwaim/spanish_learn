import Foundation

/// How much of a new page the learner already had, taken when its words first come in and before any of them is
/// studied: proof of learning that comes from the book itself. Counted over the running text, so "de" on a page forty
/// times weighs forty times, as it does when reading.
nonisolated struct PageScore: Codable, Equatable {
    var id: String
    var title: String
    var date: Date
    /// Running words whose card is Dominada and has been tested: the only kind that counts as proof.
    var known: Int
    /// Running words said to be known ("Ya la sé") and not yet tested.
    var claimed: Int
    /// Running words matched to the page's words. Names and numbers Claude leaves out aren't counted.
    var total: Int
    /// Different words on the page not in the library at all.
    var newWords: Int

    var share: Double { total == 0 ? 0 : Double(known) / Double(total) }
    var claimedShare: Double { total == 0 ? 0 : Double(claimed) / Double(total) }
}

/// Every page's score, kept on this device: a field on `Reading` would need the CloudKit schema deployed again, and
/// readings are recycled anyway.
enum PageScores {
    static let key = "pageScores"
    private static let keep = 500

    static func decode(_ data: Data) -> [PageScore] {
        (try? JSONDecoder().decode([PageScore].self, from: data)) ?? []
    }

    static var all: [PageScore] {
        UserDefaults.standard.data(forKey: key).map(decode) ?? []
    }

    /// Scores a reading whose words have just come in, once.
    static func record(_ reading: Reading, page: [PageWord], cards: [Card], now: Date = .now) {
        var list = all
        guard !list.contains(where: { $0.id == reading.id }),
              let s = score(id: reading.id, title: reading.title, lines: Tutor.firstPages(reading.lines), page: page,
                            index: Library.index(cards), now: now)
        else { return }
        list.append(s)
        UserDefaults.standard.set(try? JSONEncoder().encode(Array(list.suffix(keep))), forKey: key)
    }

    /// Each word of the text, matched to the page's word it's a form of, and that word to its card.
    static func score(id: String, title: String, lines: [String], page: [PageWord], index: [String: Card],
                      now: Date = .now) -> PageScore? {
        var word: [String: Int] = [:]
        for (i, w) in page.enumerated() {
            for f in [w.spanish] + w.forms { word[TextMatch.norm(f)] = word[TextMatch.norm(f)] ?? i }
        }
        let cards = page.map { Library.find($0.spanish, in: index) }
        var s = PageScore(id: id, title: title, date: now, known: 0, claimed: 0, total: 0,
                          newWords: cards.count { $0 == nil })
        for line in lines {
            for r in Lectura.words(line) {
                guard let i = word[TextMatch.norm(String(line[r]))] else { continue }
                s.total += 1
                guard let c = cards[i], !c.isDropped, c.stage == 5 else { continue }
                if c.reps > 0 { s.known += 1 } else { s.claimed += 1 }
            }
        }
        return s.total > 0 ? s : nil
    }

    /// The average share of the first and the last few pages, to show which way it's going. nil until there are two.
    static func trend(_ scores: [PageScore], span: Int = 3) -> (first: Double, last: Double)? {
        guard scores.count >= 2 else { return nil }
        let n = min(span, scores.count / 2)
        let avg = { (xs: ArraySlice<PageScore>) in xs.map(\.share).reduce(0, +) / Double(xs.count) }
        return (avg(scores.prefix(n)), avg(scores.suffix(n)))
    }
}
