import AppKit
import SwiftUI
import Combine
import MenuBarBibleCore

/// Owns the status item and the popover.
///
/// `MenuBarExtra` was the starting point and is the right default — but it renders its
/// label through SwiftUI, and the ticker rewrites that label continuously. Measured on
/// this machine, that cost about 3% CPU sustained, against a hard requirement of under
/// 1%. Each tick walked a SwiftUI update, an `NSHostingView` re-measure, and a menu bar
/// re-layout, and none of that gets cheaper by being asked more politely.
///
/// So the status item drops to AppKit, where a tick is one `NSStatusBarButton` title
/// assignment. The popover content stays SwiftUI — `PopoverRootView` and everything
/// under it is unchanged.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let state: AppState
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var cancellables = Set<AnyCancellable>()

    /// Tracks the icon-only / ticker transition so per-tick work stays to the title.
    private var wasTicking = false

    /// Set once and reused: rebuilding the symbol image on every tick would give back
    /// the cost this class exists to avoid.
    private let icon: NSImage? = {
        let image = NSImage(systemSymbolName: "book.closed",
                            accessibilityDescription: "Menu Bar Bible")
        image?.isTemplate = true    // follows light/dark mode and menu bar tinting
        return image
    }()

    init(state: AppState) {
        self.state = state
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        configureButton()
        configurePopover()
        observeTitle()
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.image = icon
        button.imagePosition = .imageOnly
        button.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        button.target = self
        button.action = #selector(handleClick)
        // The default is left-mouse-up only; the context menu needs the right button too.
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func configurePopover() {
        popover.behavior = .transient      // closes when the user clicks away
        popover.animates = false           // opening should feel instant
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: PopoverRootView().environmentObject(state)
        )
    }

    /// The whole per-tick path: a title arrives, a button gets a string.
    private func observeTitle() {
        StatusItemTitle.shared.$value
            .removeDuplicates()
            .sink { [weak self] title in
                self?.apply(title: title)
            }
            .store(in: &cancellables)
    }

    /// Assigns the title, and does everything it can to keep that from cascading.
    ///
    /// A status item set to `variableLength` re-measures itself whenever its title
    /// changes, and a status item that changes width makes the menu bar re-lay out every
    /// item in it — on every tick, forever. So while the ticker runs the width is pinned
    /// to what a full window needs and the item stops resizing at all.
    private func apply(title: String) {
        guard let button = statusItem.button else { return }
        let isTicking = !title.isEmpty

        // Only on the transition. Assigning these per tick would invalidate layout when
        // nothing about them had changed.
        if isTicking != wasTicking {
            // The icon comes off while the ticker runs, and this is the single largest
            // saving in here. `book.closed` is an SF Symbol — a vector image resolved
            // per redraw — and setting the title redraws the button. Profiling showed
            // the tick dominated by `_resolvedImage` →
            // `_imageWithFallbackSymbolConfiguration:` → `bestRepresentationForHints:`:
            // the symbol was being re-resolved on every tick to draw an icon that
            // never changed. Scrolling text does not need a book beside it saying it is
            // a book.
            button.image = isTicking ? nil : icon
            button.imagePosition = isTicking ? .noImage : .imageOnly
            statusItem.length = isTicking ? tickerWidth(for: button) : NSStatusItem.variableLength
            wasTicking = isTicking
        }
        button.title = title
    }

    /// Width for a full ticker window, measured once from the button's own font.
    ///
    /// Measured at the cap rather than per-tick, so a narrow line of text does not
    /// shrink the item and set the menu bar re-laying out again.
    private func tickerWidth(for button: NSStatusBarButton) -> CGFloat {
        let font = button.font ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let sample = String(repeating: "M", count: TickerWindow.maxLength)
        let textWidth = (sample as NSString).size(withAttributes: [.font: font]).width
        return textWidth + 16   // padding either side of the text
    }

    // MARK: - Clicks

    /// Left click opens the verse; right click (or control-click, which macOS reports as
    /// a right click) opens the menu.
    @objc private func handleClick() {
        let event = NSApp.currentEvent
        let isSecondary = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true

        if isSecondary {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    // MARK: - Context menu

    private func showContextMenu() {
        if popover.isShown { popover.performClose(nil) }

        // Handing the menu to the status item and clicking it — rather than calling
        // `popUp(positioning:…)` — is what makes the item highlight and the menu track
        // the way every other menu bar item does. It is detached immediately afterwards
        // so a left click still opens the popover rather than this menu.
        statusItem.menu = buildMenu()
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    /// Rebuilt on each open so checkmarks reflect the current state.
    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        if let today = state.today {
            let heading = NSMenuItem(title: today.referenceText, action: nil, keyEquivalent: "")
            heading.isEnabled = false
            menu.addItem(heading)
            menu.addItem(.separator())
        }

        menu.addItem(item("Today's Verse", #selector(menuShowVerse)))
        menu.addItem(item("Read in Context", #selector(menuShowChapter)))
        menu.addItem(.separator())

        let translations = NSMenuItem(title: "Translation", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        for translation in state.availableTranslations {
            let choice = item("\(translation.code) — \(translation.name)",
                              #selector(menuSelectTranslation(_:)))
            choice.representedObject = translation.code
            choice.state = translation.code == state.translationCode ? .on : .off
            submenu.addItem(choice)
        }
        translations.submenu = submenu
        menu.addItem(translations)

        if tickerToggleIsVisible {
            let ticker = item("Show Verse in Menu Bar", #selector(menuToggleTicker))
            ticker.state = state.tickerEnabled ? .on : .off
            menu.addItem(ticker)

            // Only worth showing when there is something to set the speed of.
            if state.tickerEnabled {
                let speeds = NSMenuItem(title: "Ticker Speed", action: nil, keyEquivalent: "")
                let submenu = NSMenu()
                submenu.autoenablesItems = false
                for speed in TickerSpeed.allCases {
                    let choice = item(speed.displayName, #selector(menuSelectTickerSpeed(_:)))
                    choice.representedObject = speed.rawValue
                    choice.state = speed == state.tickerSpeed ? .on : .off
                    // Smoother costs power, and the menu should not hide that.
                    if !speed.isWithinPowerBudget {
                        choice.toolTip = "Smoother scrolling, a little more power."
                    }
                    submenu.addItem(choice)
                }
                speeds.submenu = submenu
                menu.addItem(speeds)
            }
        }

        let launch = item("Launch at Login", #selector(menuToggleLaunchAtLogin))
        launch.state = LaunchAtLogin.isEnabled ? .on : .off
        menu.addItem(launch)

        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(menuShowSettings)))
        menu.addItem(.separator())
        menu.addItem(item("Quit Menu Bar Bible", #selector(menuQuit), key: "q"))

        return menu
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    // MARK: - Menu actions

    @objc private func menuShowVerse() {
        open(on: .verse)
    }

    @objc private func menuShowChapter() {
        open(on: .chapter)
    }

    @objc private func menuShowSettings() {
        open(on: .settings)
    }

    @objc private func menuSelectTranslation(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String else { return }
        // Re-renders today's verse in the new text. It does not re-pick it.
        state.translationCode = code
    }

    @objc private func menuToggleTicker() {
        state.tickerEnabled.toggle()
    }

    @objc private func menuSelectTickerSpeed(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let speed = TickerSpeed(rawValue: raw) else { return }
        state.tickerSpeed = speed
    }

    @objc private func menuToggleLaunchAtLogin() {
        // Failure here is silent by design: a menu has nowhere to put an error message.
        // The settings screen offers the same toggle and does explain what went wrong.
        LaunchAtLogin.set(!LaunchAtLogin.isEnabled)
    }

    @objc private func menuQuit() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Popover

    #if DEBUG
    /// Drives the status item the way a click does, and reports what happened. Used to
    /// check the popover end to end without a clickable session.
    func selfTest() {
        guard let button = statusItem.button else {
            print("[self-test] FAIL: no status item button"); return
        }
        print("[self-test] button present, image=\(button.image != nil), action wired=\(button.action != nil)")
        // Through the real entry point: with no current event this must take the
        // left-click path and open the popover.
        handleClick()
        let view = popover.contentViewController?.view
        print("[self-test] popover shown: \(popover.isShown)")
        print("[self-test] content size: \(view.map { "\(Int($0.frame.width))x\(Int($0.frame.height))" } ?? "nil")")
        handleClick()
        print("[self-test] popover closed: \(!popover.isShown)")

        print("[self-test] context menu:")
        dump(buildMenu(), indent: "  ")

        // The menu must reflect state, not a snapshot taken once at startup.
        let translation = state.translationCode
        let ticker = state.tickerEnabled
        state.translationCode = translation == "KJV" ? "WEB" : "KJV"
        state.tickerEnabled.toggle()
        print("[self-test] after changing translation to \(state.translationCode) and toggling ticker:")
        dump(buildMenu(), indent: "  ")

        // Both of those persist to UserDefaults. A diagnostic must not leave the user's
        // preferences somewhere they did not put them.
        state.translationCode = translation
        state.tickerEnabled = ticker
        print("[self-test] restored: translation=\(state.translationCode) ticker=\(state.tickerEnabled)")
    }

    private func dump(_ menu: NSMenu, indent: String) {
        for item in menu.items {
            if item.isSeparatorItem {
                print("\(indent)---")
                continue
            }
            let check = item.state == .on ? " [x]" : ""
            let wired = item.submenu != nil ? " >" : (item.action == nil ? " (heading)" : "")
            print("\(indent)\(item.title)\(check)\(wired)")
            if let submenu = item.submenu { dump(submenu, indent: indent + "    ") }
        }
    }
    #endif

    @objc private func togglePopover() {
        // A click always opens on the verse, never on whichever screen was last left
        // behind. The menu items pick their own screen.
        popover.isShown ? popover.performClose(nil) : open(on: .verse)
    }

    private func open(on screen: PopoverScreen) {
        guard let button = statusItem.button else { return }
        state.screen = screen
        if !popover.isShown {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
        popover.contentViewController?.view.window?.makeKey()
    }
}
