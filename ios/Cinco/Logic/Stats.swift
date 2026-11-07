import Foundation

/// What Home's progress shows, worked out from the cards. Words only: tables are studied on their own.
enum Stats {
    /// How far a word has come. Dominada is split in two, as reaching it takes one sitting and proves little: a word is in
    /// long-term memory once it's been right through the 24, 48 and 96 hours (or tested right after saying "Ya la sé").
    enum Standing: CaseIterable {
        case longTerm, reviewing, learning, fresh

        var name: String {
            switch self {
            case .longTerm: "A largo plazo"
            case .reviewing: "En repaso"
            case .learning: "Aprendiendo"
            case .fresh: "Sin empezar"
            }
        }
    }

    static func standing(_ c: Card) -> Standing {
        switch c.stage {
        case 0: .fresh
        case 5: inLongTerm(interval: c.interval, tested: c.reps > 0) ? .longTerm : .reviewing
        default: .learning
        }
    }

    private static func inLongTerm(interval: Int, tested: Bool) -> Bool {
        interval >= Scheduler.knownInterval && tested
    }

    /// One level's words by standing, or those not given a level yet.
    struct Level {
        let name: String
        let counts: [Standing: Int]
        var total: Int { counts.values.reduce(0, +) }
        func count(_ s: Standing) -> Int { counts[s, default: 0] }
    }

    /// The levels that have words, and "Sin nivel" while some words wait for theirs.
    static func levels(_ words: [Card]) -> [Level] {
        let tally = { (group: [Card]) in group.reduce(into: [Standing: Int]()) { $0[standing($1), default: 0] += 1 } }
        let levels = (1...3).map { l in Level(name: Library.levelNames[l] ?? "", counts: tally(words.filter { $0.level == l })) }
        return (levels + [Level(name: "Sin nivel", counts: tally(words.filter { $0.level == nil }))]).filter { $0.total > 0 }
    }

    /// How many words stand on each rung on the way to long-term memory, leaving out the empty ones.
    static func rungs(_ words: [Card]) -> [(name: String, count: Int)] {
        let on = words.filter { standing($0) == .reviewing }
        return [("24 h", on.count { $0.interval <= 1 }),
                ("48 h", on.count { (2...3).contains($0.interval) }),
                ("96 h", on.count { (4...6).contains($0.interval) }),
                ("sin comprobar", on.count { $0.interval >= Scheduler.knownInterval })]
            .filter { $0.1 > 0 }
    }

    /// The words that are giving the most trouble now: missed at least twice, and not yet held in long-term memory.
    static func struggling(_ words: [Card], limit: Int = 3) -> [Card] {
        let hard = words.filter { $0.lapses >= 2 && $0.stage > 0 && standing($0) != .longTerm }
            .sorted { ($0.lapses, $1.order) > ($1.lapses, $0.order) }
        return Array(hard.prefix(limit))
    }
}
