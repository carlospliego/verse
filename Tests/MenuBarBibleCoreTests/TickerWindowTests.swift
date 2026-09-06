import XCTest
@testable import MenuBarBibleCore

final class TickerWindowTests: XCTestCase {

    /// The acceptance criterion, exhaustively: the title never exceeds 30 characters,
    /// for every curated verse, in every translation, at every scroll position.
    func testTitleNeverExceedsThirtyCharactersForAnyCuratedVerse() throws {
        let bible = try TestSupport.makeBibleStore()

        for curated in try bible.curatedVerses() {
            guard let reference = bible.reference(for: curated) else {
                return XCTFail("curated \(curated.id) has no book")
            }
            for translation in ["WEB", "KJV", "ASV"] {
                let text = try bible.text(for: curated, translation: translation)
                var window = TickerWindow(text: "\(reference.display) — \(text)")

                for _ in 0..<window.length {
                    XCTAssertLessThanOrEqual(window.title.count, TickerWindow.maxLength,
                                             "\(reference.display) [\(translation)] overflowed")
                    window.advance()
                }
            }
        }
    }

    func testShortTextNeedsNoScrolling() {
        // No scrolling means no timer, which is what keeps idle CPU at zero.
        let short = TickerWindow(text: "Jude 2", separator: "")
        XCTAssertTrue(short.fitsWithoutScrolling)
        XCTAssertEqual(short.title, "Jude 2")

        let long = TickerWindow(text: String(repeating: "a", count: 200))
        XCTAssertFalse(long.fitsWithoutScrolling)
    }

    func testAdvancingWrapsAroundAndReturnsToTheStart() {
        var window = TickerWindow(text: "Psalm 23:1 — Yahweh is my shepherd: I shall lack nothing.")
        let first = window.title
        for _ in 0..<window.length { window.advance() }
        XCTAssertEqual(window.title, first, "a full cycle should return to where it started")
        XCTAssertEqual(window.offset, 0)
    }

    func testEveryPositionAdvancesByExactlyOneCharacter() {
        var window = TickerWindow(text: "Philippians 4:6-7 — In nothing be anxious, but in everything")
        var previous = window.title
        for _ in 0..<50 {
            window.advance()
            let current = window.title
            XCTAssertNotEqual(current, previous, "the window stopped moving")
            // The new window's leading 29 characters are the old one's trailing 29.
            XCTAssertEqual(String(current.dropLast()), String(previous.dropFirst()))
            previous = current
        }
    }

    func testWhitespaceIsCollapsed() {
        XCTAssertEqual(TickerWindow.normalize("a  b\n\nc\t d"), "a b c d")
        XCTAssertEqual(TickerWindow.normalize("  leading and trailing  "), "leading and trailing")
        let window = TickerWindow(text: "one\n\ntwo", separator: "")
        XCTAssertEqual(window.title, "one two")
    }

    func testEmptyTextIsHarmless() {
        var window = TickerWindow(text: "", separator: "")
        XCTAssertTrue(window.isEmpty)
        XCTAssertEqual(window.title, "")
        window.advance()
        XCTAssertEqual(window.title, "")
    }
}
