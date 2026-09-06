import Foundation

/// A book of the canon. `id` is canonical order, 1...66.
public struct Book: Identifiable, Hashable, Sendable {
    public let id: Int
    public let name: String
    public let abbreviation: String
    public let testament: Testament
    public let chapterCount: Int

    public init(id: Int, name: String, abbreviation: String, testament: Testament, chapterCount: Int) {
        self.id = id
        self.name = name
        self.abbreviation = abbreviation
        self.testament = testament
        self.chapterCount = chapterCount
    }
}

public enum Testament: String, Hashable, Sendable {
    case old = "OT"
    case new = "NT"
}
