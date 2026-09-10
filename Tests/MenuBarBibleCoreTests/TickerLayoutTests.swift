import XCTest
@testable import MenuBarBibleCore

final class TickerLayoutTests: XCTestCase {

    // MARK: - Seamless looping

    func testLoopedTextIsExactlyTwoCopies() {
        // The animation translates by half the composed string and repeats, so the
        // halves must be identical or the loop visibly jumps.
        let looped = TickerLayout.looped("Jude 2")
        let half = looped.count / 2
        XCTAssertEqual(looped.count % 2, 0)
        XCTAssertEqual(String(looped.prefix(half)), String(looped.suffix(half)))
        XCTAssertEqual(String(looped.prefix(half)), "Jude 2" + TickerLayout.gap)
    }

    func testLoopFractionMatchesTheDoubling() {
        // If these two ever disagree the scroll drifts a little every cycle.
        XCTAssertEqual(TickerLayout.loopFraction, 0.5)
        let looped = TickerLayout.looped("Psalm 23:1 Yahweh is my shepherd")
        let unit = Int(Double(looped.count) * TickerLayout.loopFraction)
        XCTAssertEqual(String(looped.prefix(unit)), String(looped.suffix(unit)))
    }

    func testTheGapIsWhitespaceOnly() {
        // A middle dot lived here once and read as debris drifting through the verse.
        XCTAssertFalse(TickerLayout.gap.isEmpty)
        XCTAssertTrue(TickerLayout.gap.allSatisfy(\.isWhitespace))
        XCTAssertFalse(TickerLayout.looped("Jude 2").contains("\u{00B7}"))
    }

    func testTheGapStaysWellInsideTheVisibleWidth() {
        // A gap as wide as the item would blank the menu bar once per loop.
        XCTAssertLessThan(TickerLayout.gap.count, TickerLayout.visibleCharacters / 2)
    }

    // MARK: - Normalising

    func testWhitespaceIsCollapsed() {
        XCTAssertEqual(TickerLayout.normalize("a  b\n\nc\t d"), "a b c d")
        XCTAssertEqual(TickerLayout.normalize("  leading and trailing  "), "leading and trailing")
        XCTAssertEqual(TickerLayout.normalize(""), "")
    }

    func testLoopedTextCarriesNoLineBreaks() throws {
        // Real verse text contains newlines in places; a line break inside a single-line
        // text layer renders as a hole.
        let bible = try TestSupport.makeBibleStore()
        let curated = try XCTUnwrap(try bible.curatedVerses().first { $0.verseEnd > $0.verseStart })
        for translation in ["WEB", "KJV", "ASV"] {
            let text = try bible.text(for: curated, translation: translation)

            // The verse itself must come out as one clean line.
            let normalized = TickerLayout.normalize(text)
            XCTAssertFalse(normalized.contains("\n"))
            XCTAssertFalse(normalized.contains("  "), "double space survived normalisation")

            // The composed loop carries the gap, so it does contain runs of spaces —
            // but still no line breaks, which is what would punch a hole in the layer.
            let looped = TickerLayout.looped(text)
            XCTAssertFalse(looped.contains("\n"))
            XCTAssertTrue(looped.hasPrefix(normalized))
        }
    }

    func testEmptyTextProducesJustTheGaps() {
        XCTAssertEqual(TickerLayout.looped(""), TickerLayout.gap + TickerLayout.gap)
    }

    // MARK: - Width cap

    func testTheThirtyCharacterCapIsStillThirty() {
        // §7.1's cap, now expressed as the item's width rather than a string length.
        XCTAssertEqual(TickerLayout.visibleCharacters, 30)
    }
}
