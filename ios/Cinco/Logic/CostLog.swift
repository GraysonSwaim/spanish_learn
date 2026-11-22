import Foundation

/// What each call to Claude cost, as the proxy reports it, by day and by what it was for. Kept on this phone from
/// 2026-11-22 on: earlier calls weren't counted, and another device keeps its own.
nonisolated struct CostEntry: Codable, Equatable {
    var calls = 0
    var input = 0
    var output = 0
    var dollars = 0.0

    mutating func add(_ o: CostEntry) {
        calls += o.calls
        input += o.input
        output += o.output
        dollars += o.dollars
    }
}

/// The proxy's account of one call.
nonisolated struct CallUsage: Decodable, Equatable {
    var model: String
    var input: Int
    var output: Int
    var cost: Double

    /// Any reply from the proxy: the usage rides alongside the answer, or the error.
    struct Envelope: Decodable { let usage: CallUsage? }
}

enum CostLog {
    static let key = "claudeCost"

    /// Day ("2026-11-22") → the proxy route → what it cost.
    typealias Days = [String: [String: CostEntry]]

    static func decode(_ data: Data) -> Days {
        (try? JSONDecoder().decode(Days.self, from: data)) ?? [:]
    }

    static var all: Days { UserDefaults.standard.data(forKey: key).map(decode) ?? [:] }

    static func record(_ u: CallUsage, route: String, now: Date = .now) {
        var days = all
        days[DayLog.key(for: now), default: [:]][route, default: CostEntry()]
            .add(CostEntry(calls: 1, input: u.input, output: u.output, dollars: u.cost))
        UserDefaults.standard.set(try? JSONEncoder().encode(days), forKey: key)
    }

    static func total(_ days: Days, on day: String? = nil) -> CostEntry {
        var out = CostEntry()
        for (d, routes) in days where day == nil || d == day {
            for e in routes.values { out.add(e) }
        }
        return out
    }

    /// Each route's total, today's or every day's, dearest first.
    static func byRoute(_ days: Days, on day: String? = nil) -> [(route: String, entry: CostEntry)] {
        var out: [String: CostEntry] = [:]
        for (d, routes) in days where day == nil || d == day {
            for (r, e) in routes { out[r, default: CostEntry()].add(e) }
        }
        return out.map { ($0.key, $0.value) }.sorted { $0.entry.dollars > $1.entry.dollars }
    }

    /// The first day counted.
    static func since(_ days: Days) -> String? { days.keys.min() }

    static func name(_ route: String) -> String {
        switch route {
        case "words": "Escanear páginas"
        case "gloss": "Palabras tocadas"
        case "examples": "Frases de ejemplo"
        case "levels": "Niveles"
        case "check": "Revisar con Claude"
        case "quiz": "Prueba: opciones"
        case "grade": "Prueba: corrección"
        default: route
        }
    }

    /// Dollars, with enough places that a fraction of a cent still shows: $0.0032, $0.042, $1.24.
    static func format(_ dollars: Double) -> String {
        switch dollars {
        case 0: "$0"
        case ..<0.01: String(format: "$%.4f", dollars)
        case ..<1: String(format: "$%.3f", dollars)
        default: String(format: "$%.2f", dollars)
        }
    }
}
