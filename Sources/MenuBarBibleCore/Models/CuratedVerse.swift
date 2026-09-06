import Foundation

/// An entry in the hand-curated pool.
///
/// Stores a *reference*, never text — the text is rendered from whichever translation
/// the user has selected, so the curation is authored once and works across all three.
public struct CuratedVerse: Identifiable, Hashable, Sendable {
    public let id: Int
    public let bookId: Int
    public let chapter: Int
    public let verseStart: Int
    /// Equals `verseStart` for single-verse entries.
    public let verseEnd: Int

    public init(id: Int, bookId: Int, chapter: Int, verseStart: Int, verseEnd: Int) {
        self.id = id
        self.bookId = bookId
        self.chapter = chapter
        self.verseStart = verseStart
        self.verseEnd = verseEnd
    }

    public var isRange: Bool { verseEnd > verseStart }

    public func contains(verse: Int) -> Bool {
        verse >= verseStart && verse <= verseEnd
    }
}
