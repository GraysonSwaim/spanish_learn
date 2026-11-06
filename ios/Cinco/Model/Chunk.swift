import Foundation
import SwiftData

/// No longer used: a theme, from when the library was split into them. Kept in the schema so what's in iCloud stays
/// readable and the CloudKit schema only ever grows.
///
/// Same CloudKit rules as `Card`: every property has a default, nothing is `.unique`, no relationships.
@Model
final class Chunk {
    var id: String = ""
    var name: String = ""
    /// The chunk this one was merged into; "" for one on Home.
    var parentID: String = ""
    /// Which of the theme colours.
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
