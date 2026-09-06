import Foundation

/// Read-only access to the bundled `bible.sqlite`.
///
/// This database ships inside the app bundle, is replaced wholesale on every app
/// update, and is **never written to at runtime** — the handle is opened
/// `SQLITE_OPEN_READONLY` so that is enforced by SQLite, not by convention.
public final class BibleStore {
    private let db: SQLiteDatabase

    /// Books cached on open: 66 rows, read constantly, never change.
    public let books: [Book]
    private let booksById: [Int: Book]

    public init(url: URL) throws {
        self.db = try SQLiteDatabase(path: url.path, mode: .readOnly)
        self.books = try BibleStore.loadBooks(from: db)
        self.booksById = Dictionary(uniqueKeysWithValues: books.map { ($0.id, $0) })
    }

    public func book(id: Int) -> Book? { booksById[id] }

    // MARK: - Translations

    public func translations() throws -> [BibleTranslation] {
        // Explicit ordering, matching the order the spec lists them in and the order
        // the settings picker shows: WEB (the default) first, then the two historical
        // translations. Not by year — that would put ASV above KJV.
        try db.query("""
            SELECT code, name, year, license FROM translations
            ORDER BY CASE code WHEN 'WEB' THEN 0 WHEN 'KJV' THEN 1 WHEN 'ASV' THEN 2 ELSE 3 END,
                     code
            """) { row in
            BibleTranslation(code: row.string(0),
                        name: row.string(1),
                        year: row.optionalInt(2),
                        license: row.string(3))
        }
    }

    // MARK: - Verses

    private static func loadBooks(from db: SQLiteDatabase) throws -> [Book] {
        try db.query("""
            SELECT id, name, abbreviation, testament, chapter_count
            FROM books ORDER BY id
            """) { row in
            Book(id: row.int(0),
                 name: row.string(1),
                 abbreviation: row.string(2),
                 testament: Testament(rawValue: row.string(3)) ?? .old,
                 chapterCount: row.int(4))
        }
    }

    /// Every verse that exists in `chapter` for `translation`, in verse order.
    ///
    /// Note what this does *not* do: iterate `1...n`. Verse numbering differs between
    /// the three translations (31,102 KJV / 31,098 WEB / 31,086 ASV) because they
    /// disagree about where verse boundaries fall. Rendering a chapter means asking
    /// which rows exist, never assuming which ones should.
    public func chapter(bookId: Int, chapter: Int, translation: String) throws -> [Verse] {
        try db.query("""
            SELECT id, translation_code, book_id, chapter, verse, text
            FROM verses
            WHERE translation_code = ? AND book_id = ? AND chapter = ?
            ORDER BY verse
            """, [.text(translation), .integer(bookId), .integer(chapter)], row: Self.verse)
    }

    /// The verses making up a curated range, in order.
    ///
    /// Returns whatever exists — a caller must tolerate a short or empty result rather
    /// than assuming `verseEnd - verseStart + 1` rows came back.
    public func verses(for curated: CuratedVerse, translation: String) throws -> [Verse] {
        try db.query("""
            SELECT id, translation_code, book_id, chapter, verse, text
            FROM verses
            WHERE translation_code = ? AND book_id = ? AND chapter = ?
              AND verse BETWEEN ? AND ?
            ORDER BY verse
            """,
            [.text(translation), .integer(curated.bookId), .integer(curated.chapter),
             .integer(curated.verseStart), .integer(curated.verseEnd)],
            row: Self.verse)
    }

    /// A curated range rendered as one continuous passage.
    public func text(for curated: CuratedVerse, translation: String) throws -> String {
        try verses(for: curated, translation: translation)
            .map(\.text)
            .joined(separator: " ")
    }

    private static func verse(_ row: SQLiteDatabase.Row) -> Verse {
        Verse(id: row.int(0),
              translationCode: row.string(1),
              bookId: row.int(2),
              chapter: row.int(3),
              verse: row.int(4),
              text: row.string(5))
    }

    // MARK: - Curated pool

    public func curatedVerses() throws -> [CuratedVerse] {
        try db.query("""
            SELECT id, book_id, chapter, verse_start, verse_end
            FROM curated_verses ORDER BY id
            """, row: Self.curatedVerse)
    }

    public func curatedVerse(id: Int) throws -> CuratedVerse? {
        try db.query("""
            SELECT id, book_id, chapter, verse_start, verse_end
            FROM curated_verses WHERE id = ?
            """, [.integer(id)], row: Self.curatedVerse).first
    }

    /// Just the ids — the picker works on ids and does not need the rows.
    public func curatedVerseIds() throws -> [Int] {
        try db.query("SELECT id FROM curated_verses ORDER BY id") { $0.int(0) }
    }

    private static func curatedVerse(_ row: SQLiteDatabase.Row) -> CuratedVerse {
        CuratedVerse(id: row.int(0),
                     bookId: row.int(1),
                     chapter: row.int(2),
                     verseStart: row.int(3),
                     verseEnd: row.int(4))
    }

    // MARK: - Tags

    public func tags() throws -> [Tag] {
        try db.query("""
            SELECT id, slug, display_name, sort_order FROM tags ORDER BY sort_order
            """, row: Self.tag)
    }

    public func tags(forCuratedVerseId id: Int) throws -> [Tag] {
        try db.query("""
            SELECT t.id, t.slug, t.display_name, t.sort_order
            FROM tags t
            JOIN curated_verse_tags cvt ON cvt.tag_id = t.id
            WHERE cvt.curated_verse_id = ?
            ORDER BY t.sort_order
            """, [.integer(id)], row: Self.tag)
    }

    private static func tag(_ row: SQLiteDatabase.Row) -> Tag {
        Tag(id: row.int(0), slug: row.string(1), displayName: row.string(2), sortOrder: row.int(3))
    }

    // MARK: - Composition

    /// A curated entry with its book attached, ready to render a reference.
    public func reference(for curated: CuratedVerse) -> VerseReference? {
        guard let book = book(id: curated.bookId) else { return nil }
        return VerseReference(curated: curated, book: book)
    }
}
