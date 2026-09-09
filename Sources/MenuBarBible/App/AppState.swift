import Foundation
import SwiftUI
import Combine
import MenuBarBibleCore

/// What the popover is currently showing.
enum PopoverScreen: Equatable {
    case verse
    case chapter
    case settings
}

/// Everything the UI observes.
///
/// Both stores are opened once at launch and held for the process lifetime: the day's
/// verse must be on screen in well under 200ms, and reopening SQLite on each popover
/// would be the obvious way to lose that.
@MainActor
final class AppState: ObservableObject {

    // MARK: - Published state

    @Published private(set) var today: DailyVerse?
    @Published private(set) var loadFailure: String?
    @Published var screen: PopoverScreen = .verse

    /// The chapter containing today's verse, kept in step with the verse and the
    /// selected translation. Held here rather than loaded by the chapter view on
    /// appear: the view then always has its rows on the first frame, with no empty
    /// flash and no second source of truth.
    @Published private(set) var chapterVerses: [Verse] = []

    @Published var translationCode: String {
        didSet {
            guard translationCode != oldValue else { return }
            UserDefaults.standard.set(translationCode, forKey: PreferenceKey.translation)
            // Re-render only. The curated reference is deliberately untouched:
            // changing translation must not change which verse is shown.
            rerenderCurrentVerse()
        }
    }

    @Published var tickerEnabled: Bool {
        didSet {
            guard tickerEnabled != oldValue else { return }
            UserDefaults.standard.set(tickerEnabled, forKey: PreferenceKey.tickerEnabled)
            updateTicker()
        }
    }

    @Published var tickerSpeed: TickerSpeed {
        didSet {
            guard tickerSpeed != oldValue else { return }
            UserDefaults.standard.set(tickerSpeed.rawValue, forKey: PreferenceKey.tickerSpeed)
            // Applied on the next tick. The text does not restart and the timer is not
            // rescheduled, so changing speed mid-verse is seamless.
            ticker.speed = tickerSpeed
        }
    }

    // MARK: - Collaborators

    private(set) var bible: BibleStore?
    private var user: UserStore?
    private var picker: VersePicker?
    private var dayChangeObserver: NSObjectProtocol?

    /// Owned here, but its output goes to `StatusItemTitle`, not to a published
    /// property on this object — publishing the title here would invalidate the whole
    /// scene on every ticker tick.
    private let ticker = Ticker()

    private(set) var availableTranslations: [BibleTranslation] = []

    // MARK: - Lifecycle

    init() {
        let defaults = UserDefaults.standard
        self.translationCode = defaults.string(forKey: PreferenceKey.translation) ?? BibleTranslation.defaultCode
        self.tickerEnabled = defaults.bool(forKey: PreferenceKey.tickerEnabled)
        self.tickerSpeed = defaults.string(forKey: PreferenceKey.tickerSpeed)
            .flatMap(TickerSpeed.init(rawValue:)) ?? .default

        do {
            try openStores()
        } catch {
            loadFailure = String(describing: error)
        }

        ticker.onTitleChange = { title in
            StatusItemTitle.shared.set(title)
        }

        // Rolling over midnight while the app is running must produce a new verse.
        dayChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSCalendarDayChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshForToday() }
        }

        refreshForToday()
    }

    deinit {
        if let dayChangeObserver {
            NotificationCenter.default.removeObserver(dayChangeObserver)
        }
    }

    private func openStores() throws {
        guard let bundled = Bundle.main.url(forResource: "bible", withExtension: "sqlite") else {
            throw AppError.missingBundledDatabase
        }
        let bible = try BibleStore(url: bundled)
        let identifier = Bundle.main.bundleIdentifier ?? "com.menubarbible.MenuBarBible"
        let user = try UserStore(url: try UserStore.defaultURL(bundleIdentifier: identifier))

        self.bible = bible
        self.user = user
        self.picker = VersePicker(bible: bible, user: user)
        self.availableTranslations = try bible.translations()

        // A preference pointing at a translation that is no longer bundled would render
        // an empty verse. Fall back rather than show nothing.
        if !availableTranslations.contains(where: { $0.code == translationCode }) {
            translationCode = BibleTranslation.defaultCode
        }
    }

    // MARK: - Today's verse

    /// Selects (or recalls) the verse for the current local day and renders it.
    func refreshForToday() {
        guard let picker, let bible else { return }
        do {
            guard let curated = try picker.curatedVerse() else {
                loadFailure = "The curated pool is empty."
                return
            }
            today = try render(curated, using: bible)
            chapterVerses = loadChapter(for: curated, using: bible)
            loadFailure = nil
            updateTicker()
        } catch {
            loadFailure = String(describing: error)
        }
    }

    /// Re-renders the *same* curated reference in the current translation.
    private func rerenderCurrentVerse() {
        guard let bible, let curated = today?.curated else { return }
        do {
            today = try render(curated, using: bible)
            chapterVerses = loadChapter(for: curated, using: bible)
            updateTicker()
        } catch {
            loadFailure = String(describing: error)
        }
    }

    private func render(_ curated: CuratedVerse, using bible: BibleStore) throws -> DailyVerse {
        DailyVerse(
            curated: curated,
            reference: bible.reference(for: curated),
            verses: try bible.verses(for: curated, translation: translationCode),
            tags: try bible.tags(forCuratedVerseId: curated.id),
            translationCode: translationCode
        )
    }

    // MARK: - Chapter context

    /// The full chapter in the selected translation.
    ///
    /// Whatever comes back is what exists — a chapter may legitimately be shorter in
    /// one translation than another, and an empty result is a display case, not an
    /// error.
    private func loadChapter(for curated: CuratedVerse, using bible: BibleStore) -> [Verse] {
        (try? bible.chapter(bookId: curated.bookId,
                            chapter: curated.chapter,
                            translation: translationCode)) ?? []
    }

    // MARK: - Ticker

    /// Starts or stops the ticker to match the preference. Takes effect immediately,
    /// with no restart.
    private func updateTicker() {
        guard tickerEnabled, let today else {
            ticker.stop()
            return
        }
        ticker.start(text: today.tickerText, speed: tickerSpeed)
    }
}

enum AppError: Error, CustomStringConvertible {
    case missingBundledDatabase

    var description: String {
        switch self {
        case .missingBundledDatabase:
            return "bible.sqlite is missing from the app bundle."
        }
    }
}
