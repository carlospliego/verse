import Foundation

/// A single verse row for one translation.
public struct Verse: Identifiable, Hashable, Sendable {
    public let id: Int
    public let translationCode: String
    public let bookId: Int
    public let chapter: Int
    public let verse: Int
    public let text: String

    public init(id: Int, translationCode: String, bookId: Int, chapter: Int, verse: Int, text: String) {
        self.id = id
        self.translationCode = translationCode
        self.bookId = bookId
        self.chapter = chapter
        self.verse = verse
        self.text = text
    }
}
