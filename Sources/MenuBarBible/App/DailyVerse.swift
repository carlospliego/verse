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

    /// What scrolls in the menu bar: the verse text alone.
    ///
    /// No reference. The menu bar is a peripheral-vision surface and the passage is what
    /// belongs there; the reference is one click away in the popover, and prefixing it
    /// meant every cycle spent seconds scrolling a citation past instead of scripture.
    var tickerText: String {
        text
    }
}
