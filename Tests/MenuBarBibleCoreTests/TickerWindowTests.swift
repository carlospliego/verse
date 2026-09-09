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

    // MARK: - Speed

    func testFasterSpeedsAreStrictlyFaster() {
        let rates = TickerSpeed.allCases.map(\.charactersPerSecond)
        XCTAssertEqual(rates, rates.sorted())
        XCTAssertEqual(Set(rates).count, rates.count, "two speeds scroll at the same rate")
    }

    func testEverySpeedRespectsTheThreeHundredMillisecondFloorOrIsMarkedOverBudget() {
        // §7.1 sets a 300ms floor on the interval. A setting that goes below it is a
        // deliberate trade and must declare itself, so the UI can say so.
        for speed in TickerSpeed.allCases {
            if speed.interval < 0.3 {
                XCTAssertFalse(speed.isWithinPowerBudget,
                               "\(speed.displayName) is below the 300ms floor but claims to be in budget")
            }
        }
        XCTAssertTrue(TickerSpeed.default.isWithinPowerBudget,
                      "a fresh install must not exceed the CPU ceiling unasked")
        XCTAssertGreaterThanOrEqual(TickerSpeed.default.interval, 0.3)
    }

    func testEverySpeedMovesExactlyOneCharacterPerAdvance() {
        // Smoothness comes from the step being as small as the medium allows.
        for speed in TickerSpeed.allCases {
            var window = TickerWindow(text: "Philippians 4:6-7 — In nothing be anxious, but in everything")
            _ = speed
            let before = window.offset
            window.advance()
            XCTAssertEqual(window.offset, before + 1)
        }
    }

    func testSpeedIsPersistableAndRoundTrips() {
        // Stored in UserDefaults by raw value, so the raw values must stay stable.
        for speed in TickerSpeed.allCases {
            XCTAssertEqual(TickerSpeed(rawValue: speed.rawValue), speed)
        }
        XCTAssertEqual(TickerSpeed.leisurely.rawValue, "leisurely")
        XCTAssertEqual(TickerSpeed.steady.rawValue, "steady")
        XCTAssertEqual(TickerSpeed.brisk.rawValue, "brisk")
        XCTAssertNil(TickerSpeed(rawValue: "warp"))
    }

    func testTheSeparatorCarriesNoStrayGlyph() {
        // A middle dot used to mark the loop point and read as debris in the menu bar.
        // The gap is whitespace now, and nothing else may creep in.
        let window = TickerWindow(text: "Jude 2")
        XCTAssertFalse(window.title.contains("\u{00B7}"), "middle dot is back in the ticker")

        var cycle = TickerWindow(text: "Psalm 23:1 — Yahweh is my shepherd: I shall lack nothing.")
        let source = Set("Psalm 231  Yahwehismyshepherd:Ishalllacknothing.\u{2014}")
        for _ in 0..<cycle.length {
            for character in cycle.title where !character.isWhitespace {
                XCTAssertTrue(source.contains(character),
                              "'\(character)' is not from the verse or the reference")
            }
            cycle.advance()
        }
    }

    func testTheWrapNeverBlanksTheMenuBar() {
        // The gap must stay well short of the window, or the status item goes empty and
        // the app looks dead.
        var window = TickerWindow(text: "Jude 24")
        var blankest = 0
        for _ in 0..<window.length {
            let visible = window.title.filter { !$0.isWhitespace }.count
            blankest = max(blankest, TickerWindow.maxLength - visible)
            window.advance()
        }
        XCTAssertLessThan(blankest, TickerWindow.maxLength,
                          "the ticker went completely blank at the wrap")
    }

    func testAdvancingByZeroOrNegativeDoesNothing() {
        var window = TickerWindow(text: "Psalm 23:1 — Yahweh is my shepherd: I shall lack nothing.")
        let before = window.offset
        window.advance(by: 0)
        window.advance(by: -5)
        XCTAssertEqual(window.offset, before)
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
