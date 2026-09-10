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

        // Again with the ticker on, which is when the speed picker appears.
        let tickerWas = state.tickerEnabled
        state.tickerEnabled = true
        render(SettingsView().environmentObject(state), to: directory, named: "settings-ticker-on")
        state.tickerEnabled = tickerWas

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
        checkTicker(state, to: directory)
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

    /// The toggle must take effect immediately, with no restart.
    private static func checkTickerToggle(_ state: AppState) {
        print("\n--- ticker toggle ---")
        let was = state.tickerEnabled
        state.tickerEnabled = false
        print("off -> tickerEnabled=\(state.tickerEnabled)")
        state.tickerEnabled = true
        print("on  -> tickerEnabled=\(state.tickerEnabled)")
        state.tickerEnabled = was
        print("restored -> tickerEnabled=\(state.tickerEnabled)")
    }

    /// Renders the real `TickerView` and reports what it produced.
    ///
    /// This is the first version of the ticker whose *appearance* can be checked without
    /// looking at the menu bar: the view draws into a bitmap, so a PNG of the actual
    /// scrolling text can be written out and inspected.
    private static func checkTicker(_ state: AppState, to directory: URL) {
        guard let today = state.today else { return }
        print("\n--- ticker ---")
        print("reference present: \(today.tickerText.contains(today.referenceText))")
        print("text: \(today.tickerText.prefix(60))…")
        print("item width: \(Int(TickerView.preferredWidth))pt for "
              + "\(TickerLayout.visibleCharacters) chars of \(TickerView.font.displayName ?? "?")")

        let looped = TickerLayout.looped(today.tickerText)
        print("looped text doubles cleanly: \(looped.count == (TickerLayout.normalize(today.tickerText).count + TickerLayout.gap.count) * 2)")
        print("no stray glyph at the seam: \(!looped.contains("\u{00B7}"))")

        let height = NSStatusBar.system.thickness

        // Checked in both appearances, each against a contrasting ground.
        //
        // The first attempt at this rendered white-on-white and reported "ink=0.0%",
        // which reads as a broken ticker; the ticker was fine and the check was wrong.
        // A menu bar item has no fixed colour — `labelColor` resolves to near-white in
        // dark mode and near-black in light — so a single background can only ever
        // verify one of the two.
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let ground: NSColor = name == "light" ? .white : .black
            for speed in TickerSpeed.allCases {
                let view = TickerView(frame: NSRect(x: 0, y: 0, width: TickerView.preferredWidth, height: height))
                view.appearance = NSAppearance(named: appearance)
                view.configure(text: today.tickerText, speed: speed)
                view.layoutSubtreeIfNeeded()

                var ink = 0.0
                if let image = view.snapshot(background: ground),
                   let data = image.tiffRepresentation,
                   let rep = NSBitmapImageRep(data: data) {
                    ink = Self.inkedFraction(of: rep, against: ground)
                    if let png = rep.representation(using: .png, properties: [:]) {
                        try? png.write(to: directory.appendingPathComponent("ticker-\(name)-\(speed.rawValue).png"))
                    }
                }

                print("\(name)/\(speed.displayName): \(Int(speed.pointsPerSecond))pt/s"
                      + "  animating=\(view.isAnimating)"
                      + String(format: "  ink=%.1f%%", ink * 100))
                if ink == 0 { print(view.diagnosticDescription) }
            }
        }

        // The resting state is the point of the feature: still until hovered.
        do {
            let view = TickerView(frame: NSRect(x: 0, y: 0, width: TickerView.preferredWidth, height: height))
            view.configure(text: today.tickerText, speed: .steady)
            print("at rest:      animating=\(view.isAnimating) offset=\(Int(view.diagnosticScrollOffset))pt")

            view.diagnosticSetHovering(true)
            print("hovering:     animating=\(view.isAnimating)")
            Thread.sleep(forTimeInterval: 1.0)
            let moved = view.diagnosticScrollOffset
            print("after 1s:     offset=\(Int(moved))pt (expect about \(Int(TickerSpeed.steady.pointsPerSecond)))")

            view.diagnosticSetHovering(false)
            print("left:         animating=\(view.isAnimating) offset=\(Int(view.diagnosticScrollOffset))pt")
        }

        // Pausing must actually stop the layer, or a sleeping display keeps compositing.
        let view = TickerView(frame: NSRect(x: 0, y: 0, width: TickerView.preferredWidth, height: height))
        view.configure(text: today.tickerText, speed: .steady)
        view.pauseAnimation()
        print("paused, still installed: \(view.isAnimating)")
        view.resumeAnimation()
        print("resumed: \(view.isAnimating)")
    }

    /// Fraction of pixels that differ from the background — i.e. whether text drew.
    ///
    /// Compared against the ground it was rendered on rather than against "dark",
    /// because menu bar text is light in dark mode and dark in light mode.
    private static func inkedFraction(of rep: NSBitmapImageRep, against ground: NSColor) -> Double {
        let groundBrightness = ground.usingColorSpace(.deviceRGB)?.brightnessComponent ?? 0
        var inked = 0
        var total = 0
        for y in stride(from: 0, to: rep.pixelsHigh, by: 2) {
            for x in stride(from: 0, to: rep.pixelsWide, by: 2) {
                total += 1
                if let colour = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                   abs(colour.brightnessComponent - groundBrightness) > 0.25 {
                    inked += 1
                }
            }
        }
        return total == 0 ? 0 : Double(inked) / Double(total)
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
