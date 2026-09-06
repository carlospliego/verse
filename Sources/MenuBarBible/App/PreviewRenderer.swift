#if DEBUG
import SwiftUI
import AppKit
import MenuBarBibleCore

/// Renders the popover screens to PNGs and exits.
///
/// Debug-only. Lets the UI be checked without a running menu bar session — useful in
/// CI and when screen capture is not available.
///
///     MenuBarBible.app/Contents/MacOS/MenuBarBible --render-previews <directory>
@MainActor
enum PreviewRenderer {

    static func runIfRequested() {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--render-previews"),
              arguments.indices.contains(flag + 1) else { return }
        let directory = URL(fileURLWithPath: arguments[flag + 1])
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // Time the cold path: opening the stores, picking the day's verse, and
        // producing the verse screen. This is what stands between a click on the status
        // item and something readable.
        let startedAt = Date()
        let state = AppState()
        let stateReady = Date().timeIntervalSince(startedAt)

        let renderStarted = Date()
        render(VerseView().environmentObject(state), to: directory, named: "verse")
        let verseRendered = Date().timeIntervalSince(renderStarted)

        print(String(format: "startup: stores + day's verse %.0f ms, verse view render %.0f ms",
                     stateReady * 1000, verseRendered * 1000))

        state.screen = .chapter
        render(ChapterView().environmentObject(state), to: directory, named: "chapter")
        // The rows on their own: ScrollView content does not come through ImageRenderer,
        // so this is what actually shows whether highlighting and layout are right.
        render(ChapterVerseList(verses: state.chapterVerses, curated: state.today?.curated),
               to: directory, named: "chapter-rows")

        state.screen = .settings
        render(SettingsView().environmentObject(state), to: directory, named: "settings")

        if let today = state.today {
            print("verse: \(today.referenceText) [\(today.translationCode)]")
            print("tags: \(today.tags.map(\.displayName).joined(separator: ", "))")
            print("text: \(today.text)")
            print("chapter rows: \(state.chapterVerses.count)")
        }
        if let failure = state.loadFailure {
            print("load failure: \(failure)")
        }

        checkTranslationSwitching(state)
        checkTickerToggle(state)
        exit(0)
    }

    /// Exercises the path the settings picker uses: changing the translation must
    /// re-render the *same* curated reference in new text, never pick a new verse.
    private static func checkTranslationSwitching(_ state: AppState) {
        print("\n--- translation switching ---")
        guard let startingId = state.today?.curated.id else {
            print("no verse to check"); return
        }
        var references = Set<String>()
        var texts = Set<String>()
        var ids = Set<Int>()

        for translation in state.availableTranslations.map(\.code) {
            state.translationCode = translation
            guard let today = state.today else { print("\(translation): nothing"); continue }
            references.insert(today.referenceText)
            texts.insert(today.text)
            ids.insert(today.curated.id)
            print("\(translation)  \(today.referenceText)  rows=\(state.chapterVerses.count)")
            print("     \(today.text.prefix(72))…")
        }

        print("same reference across all three: \(references.count == 1) \(references)")
        print("same curated id across all three: \(ids == [startingId])")
        print("text actually differs: \(texts.count == state.availableTranslations.count)")
    }

    /// The toggle must take effect immediately, with no restart. Driven through the
    /// same property the settings switch is bound to.
    private static func checkTickerToggle(_ state: AppState) {
        print("\n--- ticker toggle ---")
        state.tickerEnabled = false
        print("off -> title '\(StatusItemTitle.shared.value)' (empty means icon only)")

        state.tickerEnabled = true
        let on = StatusItemTitle.shared.value
        print("on  -> title '\(on)' (\(on.count) chars)")

        state.tickerEnabled = false
        print("off -> title '\(StatusItemTitle.shared.value)'")

        print("took effect without restart: \(!on.isEmpty)")
        print("within the 30-character cap: \(on.count <= TickerWindow.maxLength)")
    }

    private static func render<V: View>(_ view: V, to directory: URL, named name: String) {
        let renderer = ImageRenderer(content:
            view.frame(width: 380).background(Color(nsColor: .windowBackgroundColor))
        )
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else {
            print("could not render \(name)")
            return
        }
        let url = directory.appendingPathComponent("\(name).png")
        try? png.write(to: url)
        print("rendered \(url.path) (\(Int(image.size.width))x\(Int(image.size.height)))")
    }
}
#endif
