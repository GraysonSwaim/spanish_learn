import Foundation
import SwiftData

/// A theme: a chunk of words the learner put together. Each word is filed in one chunk (`Card.chunkID`). Chunks merge
/// into bigger ones by pointing at a parent, and the smaller ones stay inside, as deep as the learner likes. Home shows
/// the chunks with no parent.
///
/// Same CloudKit rules as `Card`: every property has a default, nothing is `.unique`, no relationships.
@Model
final class Chunk {
    var id: String = ""
    var name: String = ""
    /// The chunk this one was merged into; "" for one on Home.
    var parentID: String = ""
    /// Which of the theme colours (`Palette.chunk`).
    var color: Int = 0
    var order: Double = 0
    var created: Date = Date.now
    /// The reading it was made from, so more words marked there join it.
    var readingID: String = ""

    init(name: String, parentID: String = "", color: Int, order: Double) {
        self.id = UUID().uuidString
        self.name = name
        self.parentID = parentID
        self.color = color
        self.order = order
    }
}
