import Foundation

/// Where the chapter view should highlight, and where it should scroll.
///
/// This exists as its own type because of the one real hazard in the dataset: the three
/// translations carry 31,102 / 31,098 / 31,086 verses, and they disagree about where
/// verse boundaries fall. A number the curation names may simply not exist in the
/// translation being rendered. That has to be tolerated, not crashed on, and it is
/// easier to prove here than through a view.
public enum ChapterHighlight {

    /// The verses in `chapter` that fall inside the curated range.
    ///
    /// May be shorter than the range, or empty, if the translation lacks those numbers.
    public static func highlighted(in chapter: [Verse], for curated: CuratedVerse) -> [Verse] {
        chapter.filter { curated.contains(verse: $0.verse) }
    }

    /// The verse to scroll to so the highlighted range is visible on open.
    ///
    /// Prefers the first verse of the range that actually exists. If none of them do —
    /// a translation that drops the whole passage — it falls back to the first verse
    /// after the range's start, so the reader lands in the right neighbourhood rather
    /// than stranded at the top of Psalm 119. Returns nil only for an empty chapter.
    public static func scrollAnchor(in chapter: [Verse], for curated: CuratedVerse) -> Int? {
        if let inRange = chapter.first(where: { curated.contains(verse: $0.verse) }) {
            return inRange.verse
        }
        if let after = chapter.first(where: { $0.verse >= curated.verseStart }) {
            return after.verse
        }
        return chapter.last?.verse
    }
}
