import Foundation

/// Read-write access to `user.sqlite`.
///
/// Lives at `~/Library/Application Support/<bundle-id>/user.sqlite`, is created on
/// first launch, and survives app updates. Kept strictly separate from the bundled
/// `bible.sqlite`, which is replaced wholesale on every update.
///
/// Simple preferences (translation, ticker, launch at login) live in `UserDefaults`,
/// not here.
public final class UserStore {
    private let db: SQLiteDatabase
    public let url: URL

    /// The standard on-disk location for a given bundle identifier.
    public static func defaultURL(bundleIdentifier: String) throws -> URL {
        let support = try FileManager.default.url(for: .applicationSupportDirectory,
                                                  in: .userDomainMask,
                                                  appropriateFor: nil,
                                                  create: true)
        let directory = support.appendingPathComponent(bundleIdentifier, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("user.sqlite")
    }

    /// Opens the store, creating the file and schema if they are not there.
    ///
    /// Deleting `user.sqlite` must produce a clean first-run state, not a crash — which
    /// is why creation and migration both live here and both are idempotent.
    public init(url: URL) throws {
        self.url = url
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        self.db = try SQLiteDatabase(path: url.path, mode: .readWriteCreate)
        try db.executeScript("""
            PRAGMA journal_mode = WAL;
            PRAGMA foreign_keys = ON;

            CREATE TABLE IF NOT EXISTS pick_history (
                pick_date         TEXT PRIMARY KEY,
                curated_verse_id  INTEGER NOT NULL,
                created_at        INTEGER NOT NULL
            );

            CREATE TABLE IF NOT EXISTS favorites (
                curated_verse_id  INTEGER PRIMARY KEY,
                created_at        INTEGER NOT NULL
            );
            """)
    }

    // MARK: - Pick history

    /// The curated verse recorded for `dateKey` ("YYYY-MM-DD"), if any.
    public func pick(for dateKey: String) throws -> Int? {
        try db.query("SELECT curated_verse_id FROM pick_history WHERE pick_date = ?",
                     [.text(dateKey)]) { $0.int(0) }.first
    }

    /// The most recent `limit` picks, newest first. Used to build the exclusion window.
    public func recentPickIds(limit: Int) throws -> [Int] {
        try db.query("""
            SELECT curated_verse_id FROM pick_history
            ORDER BY pick_date DESC LIMIT ?
            """, [.integer(limit)]) { $0.int(0) }
    }

    /// Records the day's pick. Idempotent — re-recording the same day is a no-op, so a
    /// racing second call cannot change a verse the user has already been shown.
    public func recordPick(curatedVerseId: Int, for dateKey: String, at date: Date = Date()) throws {
        try db.execute("""
            INSERT OR IGNORE INTO pick_history (pick_date, curated_verse_id, created_at)
            VALUES (?, ?, ?)
            """, [.text(dateKey), .integer(curatedVerseId), .integer(Int(date.timeIntervalSince1970))])
    }

    public func pickHistoryCount() throws -> Int {
        try db.query("SELECT COUNT(*) FROM pick_history") { $0.int(0) }.first ?? 0
    }

    // MARK: - Favorites
    //
    // Unused by the v1 UI. The table exists anyway: it costs nothing and reserves the
    // shape, so a later version needs no migration.

    public func isFavorite(curatedVerseId: Int) throws -> Bool {
        try db.query("SELECT 1 FROM favorites WHERE curated_verse_id = ?",
                     [.integer(curatedVerseId)]) { _ in true }.first ?? false
    }

    public func addFavorite(curatedVerseId: Int, at date: Date = Date()) throws {
        try db.execute("""
            INSERT OR IGNORE INTO favorites (curated_verse_id, created_at) VALUES (?, ?)
            """, [.integer(curatedVerseId), .integer(Int(date.timeIntervalSince1970))])
    }

    public func removeFavorite(curatedVerseId: Int) throws {
        try db.execute("DELETE FROM favorites WHERE curated_verse_id = ?", [.integer(curatedVerseId)])
    }
}
