import Foundation
import XCTest
@testable import MenuBarBibleCore

enum TestSupport {
    /// The shipped database, located relative to this source file so tests do not need
    /// a 15.4 MB copy inside the test bundle.
    static var bibleURL: URL {
        URL(fileURLWithPath: #filePath)          // .../Tests/MenuBarBibleCoreTests/TestSupport.swift
            .deletingLastPathComponent()          // .../Tests/MenuBarBibleCoreTests
            .deletingLastPathComponent()          // .../Tests
            .deletingLastPathComponent()          // package root
            .appendingPathComponent("Resources/bible.sqlite")
    }

    static func makeBibleStore() throws -> BibleStore {
        try BibleStore(url: bibleURL)
    }

    /// A fresh user store in a unique temp directory, cleaned up by the caller.
    static func makeUserStore(file: StaticString = #filePath, line: UInt = #line) throws -> (UserStore, URL) {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("MenuBarBibleTests-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("user.sqlite")
        return (try UserStore(url: url), directory)
    }

    static func remove(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }

    static func date(_ iso: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = Calendar.current.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: "\(iso) 12:00")!
    }
}
