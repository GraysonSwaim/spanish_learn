import Foundation
import SwiftData

/// A pasted Spanish text, read and translated line by line (Lecturas). Words marked while reading become cards.
/// Same CloudKit rules as `Card`: every property has a default, no relationships. Readings not opened for a while are
/// deleted (`Lectura.recycle`).
@Model
final class Reading {
    var id: String = ""
    var title: String = ""
    var created: Date = Date.now
    var opened: Date = Date.now
    /// The Spanish, one sentence per entry.
    var lines: [String] = []
    /// The learner's English for each line, "" until written.
    var english: [String] = []
    /// Al revés: their Spanish for each line, written from the English.
    var back: [String] = []
    /// Words marked as unknown, as "line.word" (the word's place among its line's words).
    var marks: [String] = []
    /// Phrases already made into cards (or brought forward), by `Run.key`.
    var carded: [String] = []
    /// The last check each way and the cards Claude drafted, as JSON (`Tutor.Check`, `[String: Tutor.Gloss]`).
    var checkData: Data?
    var backCheckData: Data?
    var glossData: Data?

    init(title: String, lines: [String]) {
        self.id = UUID().uuidString
        self.title = title
        self.lines = lines
        self.english = Array(repeating: "", count: lines.count)
        self.back = Array(repeating: "", count: lines.count)
    }

    var check: Tutor.Check? {
        get { checkData.flatMap { try? JSONDecoder().decode(Tutor.Check.self, from: $0) } }
        set { checkData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    var backCheck: Tutor.Check? {
        get { backCheckData.flatMap { try? JSONDecoder().decode(Tutor.Check.self, from: $0) } }
        set { backCheckData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    var glosses: [String: Tutor.Gloss] {
        get { glossData.flatMap { try? JSONDecoder().decode([String: Tutor.Gloss].self, from: $0) } ?? [:] }
        set { glossData = try? JSONEncoder().encode(newValue) }
    }

    /// The English Al revés starts from: Claude's natural translation once a check has given one, else the learner's own.
    func source(_ i: Int) -> String {
        let better = check?.lines[safe: i]?.better ?? ""
        return better.isEmpty ? english[safe: i] ?? "" : better
    }
}
