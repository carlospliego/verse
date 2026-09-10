import XCTest
@testable import MenuBarBibleCore

final class TickerSpeedTests: XCTestCase {

    func testFasterSpeedsAreStrictlyFaster() {
        let rates = TickerSpeed.allCases.map(\.pointsPerSecond)
        XCTAssertEqual(rates, rates.sorted())
        XCTAssertEqual(Set(rates).count, rates.count, "two settings scroll at the same rate")
        XCTAssertTrue(rates.allSatisfy { $0 > 0 }, "a speed of zero would not scroll at all")
    }

    func testSpeedsAreInAReadablePaceRange() {
        // Roughly 3–9 characters a second at the menu bar font. Fast enough to be
        // moving, slow enough to read; well clear of a blur.
        for speed in TickerSpeed.allCases {
            XCTAssertGreaterThanOrEqual(speed.pointsPerSecond, 15)
            XCTAssertLessThanOrEqual(speed.pointsPerSecond, 80)
        }
    }

    func testSpeedIsPersistableAndRoundTrips() {
        // Stored in UserDefaults by raw value, so the raw values are part of the format.
        for speed in TickerSpeed.allCases {
            XCTAssertEqual(TickerSpeed(rawValue: speed.rawValue), speed)
        }
        XCTAssertEqual(TickerSpeed.leisurely.rawValue, "leisurely")
        XCTAssertEqual(TickerSpeed.steady.rawValue, "steady")
        XCTAssertEqual(TickerSpeed.brisk.rawValue, "brisk")
        XCTAssertNil(TickerSpeed(rawValue: "warp"))
    }

    func testEverySpeedHasADistinctDisplayName() {
        let names = TickerSpeed.allCases.map(\.displayName)
        XCTAssertEqual(Set(names).count, names.count)
        XCTAssertTrue(names.allSatisfy { !$0.isEmpty })
    }

    func testDefaultIsAMiddleSetting() {
        // Not the slowest, so it reads as moving out of the box; not the fastest either.
        XCTAssertEqual(TickerSpeed.default, .steady)
        let rates = TickerSpeed.allCases.map(\.pointsPerSecond).sorted()
        XCTAssertGreaterThan(TickerSpeed.default.pointsPerSecond, rates.first!)
        XCTAssertLessThan(TickerSpeed.default.pointsPerSecond, rates.last!)
    }
}
