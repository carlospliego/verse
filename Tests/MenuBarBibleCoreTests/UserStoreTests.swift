import XCTest
@testable import MenuBarBibleCore

final class UserStoreTests: XCTestCase {
    private var directory: URL!
    private var store: UserStore!

    override func setUpWithError() throws {
        (store, directory) = try TestSupport.makeUserStore()
    }

    override func tearDown() {
        store = nil
        TestSupport.remove(directory)
    }

    func testCreatesFileAndSchemaOnFirstOpen() throws {
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.url.path))
        XCTAssertEqual(try store.pickHistoryCount(), 0)
        XCTAssertNil(try store.pick(for: "2026-01-01"))
        XCTAssertFalse(try store.isFavorite(curatedVerseId: 1))
    }

    func testDefaultURLLandsInApplicationSupport() throws {
        let url = try UserStore.defaultURL(bundleIdentifier: "com.example.MenuBarBibleTest")
        XCTAssertTrue(url.path.contains("Application Support/com.example.MenuBarBibleTest"))
        XCTAssertEqual(url.lastPathComponent, "user.sqlite")
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    func testPicksRoundTripAndSurviveReopening() throws {
        try store.recordPick(curatedVerseId: 42, for: "2026-08-31")
        XCTAssertEqual(try store.pick(for: "2026-08-31"), 42)

        // Reopening is what happens on every app launch — and on every app update,
        // since user.sqlite is not replaced with the bundle.
        store = nil
        let reopened = try UserStore(url: directory.appendingPathComponent("user.sqlite"))
        XCTAssertEqual(try reopened.pick(for: "2026-08-31"), 42)
        store = reopened
    }

    func testRecordingTheSameDayTwiceKeepsTheFirstVerse() throws {
        // A day the user has already been shown must not change underneath them.
        try store.recordPick(curatedVerseId: 42, for: "2026-08-31")
        try store.recordPick(curatedVerseId: 99, for: "2026-08-31")
        XCTAssertEqual(try store.pick(for: "2026-08-31"), 42)
        XCTAssertEqual(try store.pickHistoryCount(), 1)
    }

    func testRecentPicksComeBackNewestFirst() throws {
        for day in 1...10 {
            try store.recordPick(curatedVerseId: day * 10, for: String(format: "2026-01-%02d", day))
        }
        XCTAssertEqual(try store.recentPickIds(limit: 3), [100, 90, 80])
        XCTAssertEqual(try store.recentPickIds(limit: 60).count, 10)
    }

    func testDeletingTheStoreProducesACleanFirstRunNotACrash() throws {
        try store.recordPick(curatedVerseId: 7, for: "2026-08-31")
        let url = store.url
        store = nil
        try FileManager.default.removeItem(at: url)

        let fresh = try UserStore(url: url)
        XCTAssertEqual(try fresh.pickHistoryCount(), 0)
        XCTAssertNil(try fresh.pick(for: "2026-08-31"))
        store = fresh
    }

    func testFavoritesTableExistsButIsNotUsedByV1() throws {
        // Reserved shape. Exercised here only so a later version needs no migration.
        try store.addFavorite(curatedVerseId: 5)
        XCTAssertTrue(try store.isFavorite(curatedVerseId: 5))
        try store.addFavorite(curatedVerseId: 5)
        try store.removeFavorite(curatedVerseId: 5)
        XCTAssertFalse(try store.isFavorite(curatedVerseId: 5))
    }
}
