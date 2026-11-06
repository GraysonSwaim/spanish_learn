import Foundation
import SwiftData

/// A Spanish text being read (Lecturas): an article, or a scanned page of a book. Words tapped while reading are recorded
/// in the library.
/// Same CloudKit rules as `Card`: every property has a default, no relationships. Readings not opened for a while are
/// deleted (`Lectura.recycle`).
@Model
final class Reading {
    var id: String = ""
    var title: String = ""
    var created: Date = Date.now
    var opened: Date = Date.now
    /// The Spanish, one sentence per entry. A paragraph marked on the article's own page is added when it isn't one.
    var lines: [String] = []
    /// The article's page, for a reading made from a link: it can be read there, as it was published. For a scanned
    /// page of a book, "libro:" and the book's name (`book`): a new property would need the CloudKit schema deployed
    /// again before TestFlight builds could sync it.
    var url: String = ""
    /// No longer written: the learner's translations each way, from when Lecturas had them. Kept so the CloudKit
    /// schema only ever grows.
    var english: [String] = []
    var back: [String] = []
    /// Words marked as unknown, as "line.word" (the word's place among its line's words).
    var marks: [String] = []
    /// Words tapped that are settled: found in the library, or added to it. By `Run.id`.
    var carded: [String] = []
    /// A scanned page's words, as JSON (`pageWords`). Once held Claude's checks of translations, which nothing reads now;
    /// reused rather than adding a field, for the same reason as `url`.
    var checkData: Data?
    /// No longer written, like `english`.
    var backCheckData: Data?
    /// What each tapped word turned out to be, as JSON (`[String: Tutor.Gloss]`).
    var glossData: Data?

    init(title: String, lines: [String]) {
        self.id = UUID().uuidString
        self.title = title
        self.lines = lines
    }

    private static let bookPrefix = "libro:"

    /// The book this page was scanned from, for a reading that is one.
    var book: String? {
        get { url.hasPrefix(Self.bookPrefix) ? String(url.dropFirst(Self.bookPrefix.count)) : nil }
        set { url = newValue.map { Self.bookPrefix + $0 } ?? "" }
    }

    /// Every word on a scanned page, once its text has been through Claude.
    var pageWords: [PageWord]? {
        get { checkData.flatMap { try? JSONDecoder().decode([PageWord].self, from: $0) } }
        set { checkData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    /// The colour of each tapped word, by `Run.id`.
    var markColors: [String: MarkColor] {
        let g = glosses
        var out: [String: MarkColor] = [:]
        for run in Lectura.runs(lines: lines, marks: marks) {
            out[run.id] = !carded.contains(run.id) ? .pending : g[run.id]?.isNew == true ? .new : .seen
        }
        return out
    }

    var glosses: [String: Tutor.Gloss] {
        get { glossData.flatMap { try? JSONDecoder().decode([String: Tutor.Gloss].self, from: $0) } ?? [:] }
        set { glossData = try? JSONEncoder().encode(newValue) }
    }
}
