import Foundation
import MenuBarBibleCore

/// Today's verse, fully resolved for display in the current translation.
struct DailyVerse: Equatable {
    let curated: CuratedVerse
    let reference: VerseReference?
    let verses: [Verse]
    let tags: [Tag]
    let translationCode: String

    /// "Philippians 4:6–7"
    var referenceText: String {
        reference?.display ?? "\(curated.chapter):\(curated.verseStart)"
    }

    /// The passage as one continuous body of text.
    var text: String {
        verses.map(\.text).joined(separator: " ")
    }

    /// What scrolls in the menu bar: reference then text, so a glance at any moment
    /// still says which passage this is.
    var tickerText: String {
        "\(referenceText) — \(text)"
    }
}
