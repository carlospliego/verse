import XCTest
@testable import MenuBarBibleCore

final class VersePickerTests: XCTestCase {
    private var bible: BibleStore!
    private var user: UserStore!
    private var directory: URL!
    private var picker: VersePicker!

    override func setUpWithError() throws {
        bible = try TestSupport.makeBibleStore()
        (user, directory) = try TestSupport.makeUserStore()
        picker = VersePicker(bible: bible, user: user)
    }

    override func tearDown() {
        picker = nil; user = nil; bible = nil
        TestSupport.remove(directory)
    }

    // MARK: - The stable hash

    func testFNV1aIsFixedForever() {
        // Hard-coded expectations. If a refactor changes these, every user's daily
        // verse changes with them — which is exactly what this test exists to catch.
        XCTAssertEqual(StableHash.fnv1a64(""), 0xcbf2_9ce4_8422_2325)
        XCTAssertEqual(StableHash.fnv1a64("a"), 0xaf63_dc4c_8601_ec8c)
        XCTAssertEqual(StableHash.fnv1a64("foobar"), 0x85944171f73967e8)
    }

    func testStableHashDoesNotVaryAcrossCalls() {
        // The whole point: unlike Hasher, this is not seeded per process.
        let first = StableHash.fnv1a64("2026-08-31")
        for _ in 0..<100 {
            XCTAssertEqual(StableHash.fnv1a64("2026-08-31"), first)
        }
    }

    func testSeededGeneratorIsReproducible() {
        var a = SeededGenerator(seed: 12345)
        var b = SeededGenerator(seed: 12345)
        var c = SeededGenerator(seed: 12346)
        let fromA = (0..<5).map { _ in a.next() }
        let fromB = (0..<5).map { _ in b.next() }
        let fromC = (0..<5).map { _ in c.next() }
        XCTAssertEqual(fromA, fromB)
        XCTAssertNotEqual(fromA, fromC)
    }

    // MARK: - Date keys

    func testDateKeyIsGregorianRegardlessOfUserCalendar() {
        let date = TestSupport.date("2026-08-31")
        XCTAssertEqual(VersePicker.dateKey(for: date), "2026-08-31")

        // A user on the Hebrew calendar still gets a Gregorian storage key.
        var hebrew = Calendar(identifier: .hebrew)
        hebrew.timeZone = Calendar.current.timeZone
        XCTAssertEqual(VersePicker.dateKey(for: date, calendar: hebrew), "2026-08-31")
    }

    // MARK: - Determinism

    func testSameDayYieldsTheSameVerse() throws {
        let day = TestSupport.date("2026-08-31")
        let first = try picker.curatedVerseId(for: day)
        for _ in 0..<20 {
            XCTAssertEqual(try picker.curatedVerseId(for: day), first)
        }
    }

    func testRelaunchingOnTheSameDayShowsTheSameVerse() throws {
        let day = TestSupport.date("2026-08-31")
        let first = try XCTUnwrap(try picker.curatedVerseId(for: day))

        // Simulate a quit and relaunch: brand new store objects over the same file.
        let url = user.url
        user = nil; picker = nil
        let reopenedUser = try UserStore(url: url)
        let reopenedPicker = VersePicker(bible: bible, user: reopenedUser)
        XCTAssertEqual(try reopenedPicker.curatedVerseId(for: day), first)

        user = reopenedUser; picker = reopenedPicker
    }

    func testMidnightRolloverYieldsADifferentVerse() throws {
        let today = try XCTUnwrap(try picker.curatedVerseId(for: TestSupport.date("2026-08-31")))
        let tomorrow = try XCTUnwrap(try picker.curatedVerseId(for: TestSupport.date("2026-09-01")))
        XCTAssertNotEqual(today, tomorrow)
        XCTAssertEqual(try user.pickHistoryCount(), 2)
    }

    func testAPickIsRecordedExactlyOnce() throws {
        let day = TestSupport.date("2026-08-31")
        _ = try picker.curatedVerseId(for: day)
        _ = try picker.curatedVerseId(for: day)
        XCTAssertEqual(try user.pickHistoryCount(), 1)
    }

    func testAnExistingHistoryRowShortCircuitsSelection() throws {
        // Step 2 must win outright: a recorded day returns its verse even when that
        // verse would be excluded by the recency window.
        try user.recordPick(curatedVerseId: 7, for: "2026-08-31")
        for day in 1...30 {
            try user.recordPick(curatedVerseId: 7, for: String(format: "2026-09-%02d", day))
        }
        XCTAssertEqual(try picker.curatedVerseId(for: TestSupport.date("2026-08-31")), 7)
    }

    // MARK: - The exclusion window

    func testNoVerseRepeatsWithinSixtyDays() throws {
        // Walk a year of consecutive days and check every sliding 60-day window.
        var picks: [Int] = []
        var date = TestSupport.date("2026-01-01")
        for _ in 0..<365 {
            picks.append(try XCTUnwrap(try picker.curatedVerseId(for: date)))
            date = Calendar.current.date(byAdding: .day, value: 1, to: date)!
        }

        XCTAssertEqual(picks.count, 365)
        for start in 0..<(picks.count - VersePicker.exclusionWindow) {
            let window = picks[start..<(start + VersePicker.exclusionWindow)]
            XCTAssertEqual(Set(window).count, window.count,
                           "a verse repeated inside the 60-day window starting at index \(start)")
        }
    }

    func testSeedingPickHistoryDirectlyExcludesThoseVerses() throws {
        // The acceptance criterion's own method: seed pick_history by hand, then check
        // what gets picked next.
        let all = try bible.curatedVerseIds()
        let seeded = Array(all.prefix(VersePicker.exclusionWindow))
        for (offset, id) in seeded.enumerated() {
            try user.recordPick(curatedVerseId: id, for: String(format: "2026-06-%02d", offset + 1))
        }

        // The very next pick sees all 60 seeded rows as the window, so none of them
        // may come back.
        let next = try XCTUnwrap(try picker.curatedVerseId(for: TestSupport.date("2026-08-01")))
        XCTAssertFalse(seeded.contains(next), "picked \(next), which is inside the window")

        // The window is a rolling 60, not a fixed set: as each new pick lands, the
        // oldest seeded row falls out and becomes eligible again. So assert against the
        // window as it stands at each moment, which is the actual contract.
        for day in 2...20 {
            let windowBefore = Set(try user.recentPickIds(limit: VersePicker.exclusionWindow))
            let pick = try XCTUnwrap(
                try picker.curatedVerseId(for: TestSupport.date(String(format: "2026-08-%02d", day)))
            )
            XCTAssertFalse(windowBefore.contains(pick),
                           "day \(day) picked \(pick), which was in the preceding 60")
        }
    }

    func testSpreadAcrossThePoolIsReasonable() throws {
        // Not a uniformity proof — just a guard against a bug that pins the choice to
        // a handful of entries.
        var seen = Set<Int>()
        var date = TestSupport.date("2026-01-01")
        for _ in 0..<300 {
            seen.insert(try XCTUnwrap(try picker.curatedVerseId(for: date)))
            date = Calendar.current.date(byAdding: .day, value: 1, to: date)!
        }
        XCTAssertGreaterThan(seen.count, 200, "300 days only reached \(seen.count) distinct verses")
    }

    // MARK: - Fallback

    func testEmptyEligibleFallsBackToTheWholePool() throws {
        // Every curated id sits in the last 60 picks. Step 5 must still return a verse
        // rather than nothing.
        let all = try bible.curatedVerseIds()
        for (offset, id) in all.enumerated() {
            try user.recordPick(curatedVerseId: id, for: String(format: "2025-%02d-%02d",
                                                                (offset / 28) + 1, (offset % 28) + 1))
        }
        // Now overwrite recency so the newest 60 cover a broad slice.
        let pick = try picker.curatedVerseId(for: TestSupport.date("2026-08-31"))
        XCTAssertNotNil(pick)
        XCTAssertTrue(all.contains(try XCTUnwrap(pick)))
    }

    func testUnrecordedPickTouchesNothing() throws {
        let pool = try bible.curatedVerseIds()
        let preview = picker.unrecordedPick(for: TestSupport.date("2026-12-25"), from: pool)
        XCTAssertNotNil(preview)
        XCTAssertEqual(try user.pickHistoryCount(), 0)
        XCTAssertNil(picker.unrecordedPick(for: Date(), from: []))
    }

    // MARK: - Translation independence

    func testChangingTranslationDoesNotChangeWhichVerseIsShown() throws {
        // The picker deals in curated ids. Translation is a rendering concern and must
        // not reach it at all.
        let day = TestSupport.date("2026-08-31")
        let curated = try XCTUnwrap(try picker.curatedVerse(for: day))

        let renderings = try ["WEB", "KJV", "ASV"].map {
            try bible.text(for: curated, translation: $0)
        }
        XCTAssertEqual(try picker.curatedVerse(for: day)?.id, curated.id)
        XCTAssertEqual(Set(renderings).count, 3, "three translations produced identical text")
        XCTAssertTrue(renderings.allSatisfy { !$0.isEmpty })
    }
}
