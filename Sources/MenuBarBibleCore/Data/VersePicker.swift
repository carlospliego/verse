import Foundation

/// Chooses the verse for a given local calendar day.
///
/// Deterministic: the same day always yields the same verse, and relaunching the app
/// does not reshuffle. Once a day's pick is written to `pick_history` it is fixed — the
/// algorithm only runs for days that have never been picked.
public struct VersePicker {

    /// How far back to look when excluding recent picks. A verse should not come round
    /// again inside two months.
    public static let exclusionWindow = 60

    private let bible: BibleStore
    private let user: UserStore

    public init(bible: BibleStore, user: UserStore) {
        self.bible = bible
        self.user = user
    }

    /// Formats a date as the "YYYY-MM-DD" key used by `pick_history`.
    ///
    /// Gregorian and POSIX-locale on purpose: the key is a storage format, not something
    /// the user reads, so it must not shift with locale or calendar preferences. The
    /// *time zone* is the user's, because "today" is a local-calendar question.
    public static func dateKey(for date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// The curated verse for `date`, recording the choice if this is the first time.
    @discardableResult
    public func curatedVerse(for date: Date = Date(), calendar: Calendar = .current) throws -> CuratedVerse? {
        let id = try curatedVerseId(for: date, calendar: calendar)
        guard let id else { return nil }
        return try bible.curatedVerse(id: id)
    }

    /// The selection algorithm proper.
    public func curatedVerseId(for date: Date = Date(), calendar: Calendar = .current) throws -> Int? {
        let key = Self.dateKey(for: date, calendar: calendar)

        // 2. A day that has already been picked keeps its verse, full stop. Nothing
        //    below runs — not the exclusion window, not the hash.
        if let existing = try user.pick(for: key) {
            return existing
        }

        // 3–4. Everything not shown in the last 60 days.
        let all = try bible.curatedVerseIds()
        guard !all.isEmpty else { return nil }

        let recent = Set(try user.recentPickIds(limit: Self.exclusionWindow))
        var eligible = all.filter { !recent.contains($0) }

        // 5. A pool at or below the window size would eventually exclude everything.
        //    Fall back to the whole pool rather than returning nothing.
        if eligible.isEmpty { eligible = all }

        // 6–7. Stable seed, seeded draw.
        var generator = SeededGenerator(seed: StableHash.fnv1a64(key))
        let index = Int(generator.next() % UInt64(eligible.count))
        let chosen = eligible[index]

        // 8. Fix the choice so it survives relaunch.
        try user.recordPick(curatedVerseId: chosen, for: key, at: date)
        return chosen
    }

    /// The verse for a day *without* recording it or consulting history.
    ///
    /// For previewing a future day in tests; the app never calls this.
    public func unrecordedPick(for date: Date, from pool: [Int], calendar: Calendar = .current) -> Int? {
        guard !pool.isEmpty else { return nil }
        var generator = SeededGenerator(seed: StableHash.fnv1a64(Self.dateKey(for: date, calendar: calendar)))
        return pool[Int(generator.next() % UInt64(pool.count))]
    }
}
