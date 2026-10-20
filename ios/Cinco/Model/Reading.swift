import Foundation
import SwiftData

/// A pasted Spanish text, read line by line (Lecturas). Words marked while reading become cards.
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
    /// No longer written: the learner's translations each way, from when Lecturas had them. Kept so the CloudKit
    /// schema only ever grows.
    var english: [String] = []
    var back: [String] = []
    /// Words marked as unknown, as "line.word" (the word's place among its line's words).
    var marks: [String] = []
    /// Phrases already made into cards (or brought forward), by `Run.key`.
    var carded: [String] = []
    /// No longer written, like `english`: Claude's checks of those translations.
    var checkData: Data?
    var backCheckData: Data?
    /// The cards Claude drafted, as JSON (`[String: Tutor.Gloss]`).
    var glossData: Data?

    init(title: String, lines: [String]) {
        self.id = UUID().uuidString
        self.title = title
        self.lines = lines
    }

    var glosses: [String: Tutor.Gloss] {
        get { glossData.flatMap { try? JSONDecoder().decode([String: Tutor.Gloss].self, from: $0) } ?? [:] }
        set { glossData = try? JSONEncoder().encode(newValue) }
    }
}
