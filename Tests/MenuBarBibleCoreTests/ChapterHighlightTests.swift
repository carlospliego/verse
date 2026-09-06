import XCTest
@testable import MenuBarBibleCore

final class ChapterHighlightTests: XCTestCase {
    private var bible: BibleStore!

    override func setUpWithError() throws {
        bible = try TestSupport.makeBibleStore()
    }

    // MARK: - Highlighting

    func testHighlightsExactlyTheCuratedRange() throws {
        let matthew5 = try bible.chapter(bookId: 40, chapter: 5, translation: "WEB")
        let curated = CuratedVerse(id: 1, bookId: 40, chapter: 5, verseStart: 14, verseEnd: 16)

        let highlighted = ChapterHighlight.highlighted(in: matthew5, for: curated)
        XCTAssertEqual(highlighted.map(\.verse), [14, 15, 16])
        XCTAssertEqual(ChapterHighlight.scrollAnchor(in: matthew5, for: curated), 14)
    }

    func testSingleVerseHighlightsOneRow() throws {
        let psalm23 = try bible.chapter(bookId: 19, chapter: 23, translation: "WEB")
        let curated = CuratedVerse(id: 1, bookId: 19, chapter: 23, verseStart: 1, verseEnd: 1)
        XCTAssertEqual(ChapterHighlight.highlighted(in: psalm23, for: curated).map(\.verse), [1])
    }

    // MARK: - Every curated verse, every translation

    func testEveryCuratedVerseHighlightsAndAnchorsInAllThreeTranslations() throws {
        // The acceptance criterion for the whole chapter view, over the real pool.
        for curated in try bible.curatedVerses() {
            for translation in ["WEB", "KJV", "ASV"] {
                let chapter = try bible.chapter(bookId: curated.bookId,
                                                chapter: curated.chapter,
                                                translation: translation)
                XCTAssertFalse(chapter.isEmpty,
                               "curated \(curated.id): chapter empty in \(translation)")

                let highlighted = ChapterHighlight.highlighted(in: chapter, for: curated)
                XCTAssertFalse(highlighted.isEmpty,
                               "curated \(curated.id): nothing highlighted in \(translation)")

                let anchor = ChapterHighlight.scrollAnchor(in: chapter, for: curated)
                XCTAssertNotNil(anchor, "curated \(curated.id): no anchor in \(translation)")
                XCTAssertTrue(chapter.contains { $0.verse == anchor },
                              "curated \(curated.id): anchor \(anchor!) is not a row in \(translation)")
            }
        }
    }

    // MARK: - Chapter boundaries

    func testSingleChapterBooks() throws {
        // Obadiah, Philemon, 2 John, 3 John, Jude.
        for (bookId, name) in [(31, "Obadiah"), (57, "Philemon"), (63, "2 John"),
                               (64, "3 John"), (65, "Jude")] {
            for translation in ["WEB", "KJV", "ASV"] {
                let chapter = try bible.chapter(bookId: bookId, chapter: 1, translation: translation)
                XCTAssertFalse(chapter.isEmpty, "\(name) empty in \(translation)")

                let last = try XCTUnwrap(chapter.last).verse
                let curated = CuratedVerse(id: 1, bookId: bookId, chapter: 1,
                                           verseStart: last, verseEnd: last)
                XCTAssertEqual(ChapterHighlight.scrollAnchor(in: chapter, for: curated), last,
                               "\(name): last verse should anchor on itself in \(translation)")
            }
        }
    }

    func testPsalm119() throws {
        // The long chapter, and the one where a bad anchor is most obvious.
        for translation in ["WEB", "KJV", "ASV"] {
            let chapter = try bible.chapter(bookId: 19, chapter: 119, translation: translation)
            XCTAssertEqual(chapter.count, 176, "Psalm 119 in \(translation)")

            let curated = CuratedVerse(id: 1, bookId: 19, chapter: 119, verseStart: 105, verseEnd: 105)
            XCTAssertEqual(ChapterHighlight.scrollAnchor(in: chapter, for: curated), 105)

            let atEnd = CuratedVerse(id: 2, bookId: 19, chapter: 119, verseStart: 176, verseEnd: 176)
            XCTAssertEqual(ChapterHighlight.scrollAnchor(in: chapter, for: atEnd), 176)
        }
    }

    func testFirstAndLastChapterOfTheCanon() throws {
        let genesis1 = try bible.chapter(bookId: 1, chapter: 1, translation: "WEB")
        XCTAssertEqual(genesis1.first?.verse, 1)
        XCTAssertEqual(genesis1.count, 31)

        let revelation22 = try bible.chapter(bookId: 66, chapter: 22, translation: "WEB")
        XCTAssertFalse(revelation22.isEmpty)
        XCTAssertEqual(revelation22.last?.verse, 21)
    }

    func testChapterBeyondTheBookIsEmptyNotACrash() throws {
        XCTAssertTrue(try bible.chapter(bookId: 65, chapter: 2, translation: "WEB").isEmpty)
        XCTAssertTrue(try bible.chapter(bookId: 19, chapter: 151, translation: "WEB").isEmpty)
        XCTAssertTrue(try bible.chapter(bookId: 1, chapter: 0, translation: "WEB").isEmpty)
    }

    // MARK: - Translation gaps

    func testAMissingVerseNumberIsToleratedNotCrashed() throws {
        // Synthesise the exact hazard DATA.md warns about: a chapter whose translation
        // omits the verse the curation names.
        let chapter = [
            Verse(id: 1, translationCode: "WEB", bookId: 41, chapter: 9, verse: 42, text: "…"),
            Verse(id: 2, translationCode: "WEB", bookId: 41, chapter: 9, verse: 43, text: "…"),
            // 44 omitted, as WEB and ASV do.
            Verse(id: 3, translationCode: "WEB", bookId: 41, chapter: 9, verse: 45, text: "…"),
        ]
        let missing = CuratedVerse(id: 1, bookId: 41, chapter: 9, verseStart: 44, verseEnd: 44)

        XCTAssertTrue(ChapterHighlight.highlighted(in: chapter, for: missing).isEmpty)
        // Lands on the next verse that does exist rather than giving up.
        XCTAssertEqual(ChapterHighlight.scrollAnchor(in: chapter, for: missing), 45)
    }

    func testARangeThatOnlyPartlyExistsHighlightsWhatIsThere() throws {
        let chapter = [
            Verse(id: 1, translationCode: "WEB", bookId: 41, chapter: 9, verse: 43, text: "…"),
            Verse(id: 2, translationCode: "WEB", bookId: 41, chapter: 9, verse: 45, text: "…"),
        ]
        let range = CuratedVerse(id: 1, bookId: 41, chapter: 9, verseStart: 43, verseEnd: 45)
        XCTAssertEqual(ChapterHighlight.highlighted(in: chapter, for: range).map(\.verse), [43, 45])
        XCTAssertEqual(ChapterHighlight.scrollAnchor(in: chapter, for: range), 43)
    }

    func testARangePastTheEndAnchorsOnTheLastVerse() {
        let chapter = [
            Verse(id: 1, translationCode: "WEB", bookId: 1, chapter: 1, verse: 1, text: "…"),
            Verse(id: 2, translationCode: "WEB", bookId: 1, chapter: 1, verse: 2, text: "…"),
        ]
        let past = CuratedVerse(id: 1, bookId: 1, chapter: 1, verseStart: 90, verseEnd: 91)
        XCTAssertTrue(ChapterHighlight.highlighted(in: chapter, for: past).isEmpty)
        XCTAssertEqual(ChapterHighlight.scrollAnchor(in: chapter, for: past), 2)
    }

    func testAnEmptyChapterHasNoAnchor() {
        let curated = CuratedVerse(id: 1, bookId: 1, chapter: 1, verseStart: 1, verseEnd: 1)
        XCTAssertNil(ChapterHighlight.scrollAnchor(in: [], for: curated))
        XCTAssertTrue(ChapterHighlight.highlighted(in: [], for: curated).isEmpty)
    }
}
