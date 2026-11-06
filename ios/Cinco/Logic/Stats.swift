import Foundation

/// What Home's progress shows, worked out from the cards and the daily logs. Words only: tables are studied on their own.
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

    /// One day ahead: the tests that fall on it, and how many of those would bring a word to long-term memory.
    struct DayAhead: Equatable {
        let date: Date
        var tests = 0
        var arrivals = 0
    }

    /// The tests of the coming days if every answer is right, so a word on 24 hours shows up again 2 and 6 days on. Anything
    /// overdue is today's. Words still in stages 1–4 aren't in it, as they've no date until they reach Dominada.
    static func ahead(_ words: [Card], days: Int = 14, now: Date = .now) -> [DayAhead] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        var out = (0..<days).compactMap { cal.date(byAdding: .day, value: $0, to: today).map { DayAhead(date: $0) } }
        for c in words where c.stage == 5 && !c.isDropped {
            var at = max(0, cal.dateComponents([.day], from: today, to: cal.startOfDay(for: c.due)).day ?? 0)
            var interval = c.interval
            var tested = c.reps > 0
            // The first test may not move it on: brought back sooner than its wait, it keeps that wait.
            var moves = Scheduler.waitedOut(c, now: max(c.due, now))
            while at < days {
                let next = moves ? Scheduler.nextInterval(interval) : interval
                out[at].tests += 1
                if !inLongTerm(interval: interval, tested: tested), inLongTerm(interval: next, tested: true) { out[at].arrivals += 1 }
                (interval, tested, moves) = (next, true, true)
                at += interval
            }
        }
        return out
    }

    /// One day behind: every answer given, tables too, as the daily log doesn't tell them apart.
    struct DayBehind: Equatable {
        let date: Date
        var right = 0
        var wrong = 0
    }

    /// The last `days` days, oldest first, ending today.
    static func behind(_ logs: [DayLog], days: Int = 14, now: Date = .now) -> [DayBehind] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let byKey = Dictionary(logs.map { ($0.key, $0) }, uniquingKeysWith: { a, b in a.reviewed >= b.reviewed ? a : b })
        return (0..<days).reversed().compactMap { back in
            guard let date = cal.date(byAdding: .day, value: -back, to: today) else { return nil }
            let log = byKey[DayLog.key(for: date)]
            let right = log?.correct ?? 0
            return DayBehind(date: date, right: right, wrong: max(0, (log?.reviewed ?? 0) - right))
        }
    }

    /// The words that are giving the most trouble now: missed at least twice, and not yet held in long-term memory.
    static func struggling(_ words: [Card], limit: Int = 3) -> [Card] {
        let hard = words.filter { $0.lapses >= 2 && $0.stage > 0 && standing($0) != .longTerm }
            .sorted { ($0.lapses, $1.order) > ($1.lapses, $0.order) }
        return Array(hard.prefix(limit))
    }
}

/// How words do when they come back after their wait, by day: the truest measure of what's staying, as a miss while first
/// learning a word is expected. It's kept on this device, since a new `DayLog` field would need the CloudKit schema deployed.
enum RecallLog {
    /// Two windows' worth, to compare one with the one before.
    private static let keptDays = 28

    private static func all(_ d: UserDefaults) -> [String: [Int]] {
        d.dictionary(forKey: PrefKey.recall) as? [String: [Int]] ?? [:]
    }

    /// One test's result; `by: -1` takes one back (Deshacer).
    static func add(right: Bool, by delta: Int = 1, on date: Date = .now, in d: UserDefaults = .standard) {
        var log = all(d)
        let key = DayLog.key(for: date)
        var day = log[key] ?? [0, 0]
        day[0] = max(0, day[0] + (right ? delta : 0))
        day[1] = max(0, day[1] + delta)
        log[key] = day
        if let oldest = Calendar.current.date(byAdding: .day, value: -keptDays, to: date) {
            let limit = DayLog.key(for: oldest)
            log = log.filter { $0.key > limit }
        }
        d.set(log, forKey: PrefKey.recall)
    }

    /// Right answers and all answers over `days` days, ending `back` days ago.
    static func tally(days: Int = 14, back: Int = 0, now: Date = .now, in d: UserDefaults = .standard) -> (right: Int, total: Int) {
        let log = all(d)
        let cal = Calendar.current
        var out = (right: 0, total: 0)
        for i in back..<(back + days) {
            guard let date = cal.date(byAdding: .day, value: -i, to: now), let day = log[DayLog.key(for: date)], day.count == 2 else { continue }
            out.right += day[0]
            out.total += day[1]
        }
        return out
    }

    static func clear(in d: UserDefaults = .standard) {
        d.removeObject(forKey: PrefKey.recall)
    }
}
