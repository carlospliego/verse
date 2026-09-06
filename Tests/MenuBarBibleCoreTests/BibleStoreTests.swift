import XCTest
@testable import MenuBarBibleCore

final class BibleStoreTests: XCTestCase {
    private var store: BibleStore!

    override func setUpWithError() throws {
        store = try TestSupport.makeBibleStore()
    }

    // MARK: - Shape of the shipped database

    func testHasSixtySixBooksInCanonicalOrder() {
        XCTAssertEqual(store.books.count, 66)
        XCTAssertEqual(store.books.map(\.id), Array(1...66))
        XCTAssertEqual(store.books.first?.name, "Genesis")
        XCTAssertEqual(store.books.last?.name, "Revelation")
        XCTAssertEqual(store.books.filter { $0.testament == .old }.count, 39)
        XCTAssertEqual(store.books.filter { $0.testament == .new }.count, 27)
    }

    func testHasThreePublicDomainTranslationsWithWEBFirst() throws {
        let translations = try store.translations()
        XCTAssertEqual(translations.map(\.code), ["WEB", "KJV", "ASV"])
        XCTAssertTrue(translations.allSatisfy { $0.license == "public-domain" })
        XCTAssertEqual(BibleTranslation.defaultCode, translations.first?.code)
    }

    func testChapterCountsMatchTheVersesPresent() throws {
        // books.chapter_count is what the chapter picker will trust, so it had better
        // agree with the rows that actually exist.
        for book in store.books {
            let last = try store.chapter(bookId: book.id,
                                         chapter: book.chapterCount,
                                         translation: "WEB")
            XCTAssertFalse(last.isEmpty,
                           "\(book.name) claims \(book.chapterCount) chapters but the last one is empty")
            let beyond = try store.chapter(bookId: book.id,
                                           chapter: book.chapterCount + 1,
                                           translation: "WEB")
            XCTAssertTrue(beyond.isEmpty, "\(book.name) has verses past its chapter_count")
        }
    }

    func testNoEmptyOrMarkedUpVerseText() throws {
        // Spot-check the shape of the text the user will actually read.
        for translation in ["WEB", "KJV", "ASV"] {
            let psalm23 = try store.chapter(bookId: 19, chapter: 23, translation: translation)
            XCTAssertEqual(psalm23.count, 6)
            for verse in psalm23 {
                XCTAssertFalse(verse.text.trimmingCharacters(in: .whitespaces).isEmpty)
                XCTAssertFalse(verse.text.contains("<"))
                XCTAssertFalse(verse.text.contains(">"))
                XCTAssertFalse(verse.text.contains("\\"))
            }
        }
    }

    // MARK: - Chapter boundaries

    func testSingleChapterBooksRender() throws {
        // Obadiah, Philemon, 2 John, 3 John, Jude — the books where an off-by-one in
        // chapter handling shows up immediately.
        let singles = [(31, "Obadiah"), (57, "Philemon"), (63, "2 John"), (64, "3 John"), (65, "Jude")]
        for (id, name) in singles {
            let book = store.book(id: id)
            XCTAssertEqual(book?.chapterCount, 1, "\(name) should have one chapter")
            let verses = try store.chapter(bookId: id, chapter: 1, translation: "WEB")
            XCTAssertGreaterThan(verses.count, 10, "\(name) chapter 1 came back nearly empty")
        }
    }

    func testPsalm119IsTheLongestChapter() throws {
        let verses = try store.chapter(bookId: 19, chapter: 119, translation: "WEB")
        XCTAssertEqual(verses.count, 176)
        XCTAssertEqual(verses.map(\.verse), Array(1...176))
    }

    func testChapterReturnsOnlyVersesThatExistForTheTranslation() throws {
        // The translations disagree on verse counts. Whatever comes back must be
        // strictly ascending and self-consistent, never a padded 1...n range.
        for translation in ["WEB", "KJV", "ASV"] {
            let mark9 = try store.chapter(bookId: 41, chapter: 9, translation: translation)
            XCTAssertFalse(mark9.isEmpty)
            let numbers = mark9.map(\.verse)
            XCTAssertEqual(numbers, numbers.sorted())
            XCTAssertEqual(Set(numbers).count, numbers.count, "duplicate verse numbers")
            XCTAssertTrue(mark9.allSatisfy { !$0.text.isEmpty })
        }
    }

    func testTranslationsDisagreeOnVerseCountAndThatIsFine() throws {
        // Documenting the hazard rather than asserting they match: Mark 9 is one of the
        // places where WEB/ASV drop verses KJV keeps.
        let counts = try ["WEB", "KJV", "ASV"].map {
            try store.chapter(bookId: 41, chapter: 9, translation: $0).count
        }
        XCTAssertFalse(Set(counts).count == 1 && counts[0] == 0)
    }

    // MARK: - Curated pool

    func testCuratedPoolIsIntactAndStoresReferencesOnly() throws {
        let curated = try store.curatedVerses()
        XCTAssertEqual(curated.count, 329)
        XCTAssertEqual(curated.filter(\.isRange).count, 76)
        XCTAssertTrue(curated.allSatisfy { $0.verseEnd >= $0.verseStart })
        XCTAssertTrue(curated.allSatisfy { (1...66).contains($0.bookId) })
    }

    func testEveryCuratedReferenceResolvesInAllThreeTranslations() throws {
        // The daily-verse path must never come up empty, in any translation.
        for curated in try store.curatedVerses() {
            for translation in ["WEB", "KJV", "ASV"] {
                let text = try store.text(for: curated, translation: translation)
                XCTAssertFalse(text.isEmpty,
                               "curated \(curated.id) is empty in \(translation)")
            }
        }
    }

    func testTwelveTagsAndEveryCuratedVerseIsTagged() throws {
        let tags = try store.tags()
        XCTAssertEqual(tags.count, 12)
        XCTAssertEqual(tags.map(\.sortOrder), Array(1...12))
        XCTAssertEqual(Set(tags.map(\.slug)),
                       ["comfort", "anxiety", "hope", "courage", "rest", "gratitude",
                        "forgiveness", "patience", "humility", "wisdom", "provision", "purpose"])

        for curated in try store.curatedVerses() {
            XCTAssertFalse(try store.tags(forCuratedVerseId: curated.id).isEmpty,
                           "curated \(curated.id) has no tags")
        }
    }

    // MARK: - Rendering

    func testMultiVersePassageJoinsIntoOneText() throws {
        // Philippians 4:6-7 — the spec's own example, and a passage where verse 6
        // alone lacks sense.
        let philippians = try XCTUnwrap(
            try store.curatedVerses().first { $0.bookId == 50 && $0.chapter == 4 && $0.verseStart == 6 }
        )
        XCTAssertEqual(philippians.verseEnd, 7)

        let web = try store.text(for: philippians, translation: "WEB")
        XCTAssertTrue(web.hasPrefix("In nothing be anxious"))
        XCTAssertTrue(web.contains("peace of God"))

        let kjv = try store.text(for: philippians, translation: "KJV")
        XCTAssertTrue(kjv.hasPrefix("Be careful for nothing"))
        XCTAssertNotEqual(web, kjv)
    }

    func testReferenceFormatting() throws {
        let philippians = CuratedVerse(id: 1, bookId: 50, chapter: 4, verseStart: 6, verseEnd: 7)
        let reference = try XCTUnwrap(store.reference(for: philippians))
        XCTAssertEqual(reference.display, "Philippians 4:6\u{2013}7")   // en-dash
        XCTAssertEqual(reference.displayAbbreviated, "Phil 4:6\u{2013}7")

        let single = CuratedVerse(id: 2, bookId: 19, chapter: 23, verseStart: 1, verseEnd: 1)
        XCTAssertEqual(try XCTUnwrap(store.reference(for: single)).display, "Psalms 23:1")
    }
}
