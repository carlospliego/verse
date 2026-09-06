import Foundation

/// A curated entry paired with its book, so it can render a human reference
/// without another database round trip.
public struct VerseReference: Hashable, Sendable {
    public let curated: CuratedVerse
    public let book: Book

    public init(curated: CuratedVerse, book: Book) {
        self.curated = curated
        self.book = book
    }

    /// "Philippians 4:6–7" — en-dash for ranges, per the spec's own example.
    public var display: String {
        formatted(bookName: book.name)
    }

    /// "Phil 4:6–7" — for tight spaces such as the menu bar ticker.
    public var displayAbbreviated: String {
        formatted(bookName: book.abbreviation)
    }

    private func formatted(bookName: String) -> String {
        let c = curated
        if c.isRange {
            return "\(bookName) \(c.chapter):\(c.verseStart)\u{2013}\(c.verseEnd)"
        }
        return "\(bookName) \(c.chapter):\(c.verseStart)"
    }
}
