import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public enum SQLiteError: Error, CustomStringConvertible {
    case open(path: String, message: String)
    case prepare(sql: String, message: String)
    case step(sql: String, message: String)

    public var description: String {
        switch self {
        case .open(let path, let message):      return "Could not open \(path): \(message)"
        case .prepare(let sql, let message):    return "Could not prepare [\(sql)]: \(message)"
        case .step(let sql, let message):       return "Could not execute [\(sql)]: \(message)"
        }
    }
}

/// A deliberately small wrapper over the SQLite3 C API.
///
/// The app has two stores with different needs — a read-only bundled database and a
/// read-write user database — so this exposes both modes and nothing more.
public final class SQLiteDatabase {
    public enum Mode {
        case readOnly
        case readWriteCreate
    }

    private var handle: OpaquePointer?
    public let path: String

    public init(path: String, mode: Mode) throws {
        self.path = path
        let flags: Int32
        switch mode {
        case .readOnly:        flags = SQLITE_OPEN_READONLY
        case .readWriteCreate: flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
        }
        var db: OpaquePointer?
        let rc = sqlite3_open_v2(path, &db, flags | SQLITE_OPEN_FULLMUTEX, nil)
        guard rc == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "code \(rc)"
            if db != nil { sqlite3_close_v2(db) }
            throw SQLiteError.open(path: path, message: message)
        }
        self.handle = db
    }

    deinit {
        if let handle { sqlite3_close_v2(handle) }
    }

    private var errorMessage: String {
        guard let handle else { return "database is closed" }
        return String(cString: sqlite3_errmsg(handle))
    }

    // MARK: - Query

    /// Runs `sql` and maps each result row. Parameters bind positionally, 1-based.
    public func query<T>(_ sql: String,
                         _ parameters: [SQLiteValue] = [],
                         row: (Row) throws -> T) throws -> [T] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteError.prepare(sql: sql, message: errorMessage)
        }
        defer { sqlite3_finalize(statement) }
        try bind(parameters, to: statement, sql: sql)

        var results: [T] = []
        while true {
            let rc = sqlite3_step(statement)
            if rc == SQLITE_ROW {
                results.append(try row(Row(statement: statement)))
            } else if rc == SQLITE_DONE {
                break
            } else {
                throw SQLiteError.step(sql: sql, message: errorMessage)
            }
        }
        return results
    }

    /// Runs a statement that returns no rows.
    public func execute(_ sql: String, _ parameters: [SQLiteValue] = []) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteError.prepare(sql: sql, message: errorMessage)
        }
        defer { sqlite3_finalize(statement) }
        try bind(parameters, to: statement, sql: sql)

        let rc = sqlite3_step(statement)
        guard rc == SQLITE_DONE || rc == SQLITE_ROW else {
            throw SQLiteError.step(sql: sql, message: errorMessage)
        }
    }

    /// Runs one or more statements with no parameters (schema creation, pragmas).
    public func executeScript(_ sql: String) throws {
        var errorPointer: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(handle, sql, nil, nil, &errorPointer) == SQLITE_OK else {
            let message = errorPointer.map { String(cString: $0) } ?? errorMessage
            sqlite3_free(errorPointer)
            throw SQLiteError.step(sql: sql, message: message)
        }
    }

    private func bind(_ parameters: [SQLiteValue], to statement: OpaquePointer, sql: String) throws {
        for (offset, value) in parameters.enumerated() {
            let index = Int32(offset + 1)
            let rc: Int32
            switch value {
            case .integer(let i): rc = sqlite3_bind_int64(statement, index, Int64(i))
            case .text(let s):    rc = sqlite3_bind_text(statement, index, s, -1, SQLITE_TRANSIENT)
            case .null:           rc = sqlite3_bind_null(statement, index)
            }
            guard rc == SQLITE_OK else {
                throw SQLiteError.prepare(sql: sql, message: errorMessage)
            }
        }
    }

    // MARK: - Row access

    public struct Row {
        let statement: OpaquePointer

        public func int(_ column: Int32) -> Int {
            Int(sqlite3_column_int64(statement, column))
        }

        public func optionalInt(_ column: Int32) -> Int? {
            sqlite3_column_type(statement, column) == SQLITE_NULL ? nil : int(column)
        }

        public func string(_ column: Int32) -> String {
            guard let cString = sqlite3_column_text(statement, column) else { return "" }
            return String(cString: cString)
        }
    }
}

public enum SQLiteValue {
    case integer(Int)
    case text(String)
    case null
}

extension SQLiteValue: ExpressibleByIntegerLiteral, ExpressibleByStringLiteral {
    public init(integerLiteral value: Int) { self = .integer(value) }
    public init(stringLiteral value: String) { self = .text(value) }
}
