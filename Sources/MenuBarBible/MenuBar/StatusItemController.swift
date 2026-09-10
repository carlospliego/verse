import AppKit
import SwiftUI
import Combine
import MenuBarBibleCore

/// Owns the status item and the popover.
///
/// `MenuBarExtra` was the starting point and is the right default — but it renders its
/// label through SwiftUI, and the ticker rewrites that label continuously. Measured on
/// this machine, that cost about 3% CPU sustained, against a hard requirement of under
/// 1%. Each update walked a SwiftUI update, an `NSHostingView` re-measure, and a menu bar
/// re-layout, and none of that gets cheaper by being asked more politely.
///
/// So the status item drops to AppKit. The popover content stays SwiftUI —
/// `PopoverRootView` and everything under it is unchanged.
///
/// Ticker mode is a `TickerView` layered over the button: a Core Animation marquee, not
/// a timer retitling the item. See that type for why.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let state: AppState
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var cancellables = Set<AnyCancellable>()
    private var systemObservers: [NSObjectProtocol] = []
    private var popoverResizeObserver: NSObjectProtocol?

    /// The scrolling verse, created the first time the ticker is switched on.
    private var tickerView: TickerView?

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
        observeTickerState()
        observeSystemSleepAndLock()
    }

    deinit {
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        for observer in systemObservers {
            workspace.removeObserver(observer)
            distributed.removeObserver(observer)
        }
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

    // MARK: - Ticker

    /// Watches the three things that decide what the status item shows.
    private func observeTickerState() {
        state.$tickerEnabled
            .combineLatest(state.$tickerSpeed, state.$today)
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled, speed, today in
                self?.applyTicker(enabled: enabled, speed: speed, today: today)
            }
            .store(in: &cancellables)
    }

    private func applyTicker(enabled: Bool, speed: TickerSpeed, today: DailyVerse?) {
        guard let button = statusItem.button else { return }

        guard enabled, let today, !today.tickerText.isEmpty else {
            tickerView?.removeFromSuperview()
            tickerView = nil
            button.image = icon
            button.imagePosition = .imageOnly
            statusItem.length = NSStatusItem.variableLength
            return
        }

        // The icon comes off while the verse scrolls. It was also the largest single
        // cost in the old timer-driven ticker: `book.closed` is an SF Symbol, a vector
        // image re-resolved on every redraw, and retitling the button redrew it. Beyond
        // that, scrolling text does not need a book beside it saying it is a book.
        button.image = nil
        button.title = ""
        button.imagePosition = .noImage
        statusItem.length = TickerView.preferredWidth

        let view: TickerView
        if let existing = tickerView {
            view = existing
        } else {
            view = TickerView(frame: button.bounds)
            view.autoresizingMask = [.width, .height]
            button.addSubview(view)
            view.installTracking(on: button)
            tickerView = view
        }
        view.frame = button.bounds
        view.configure(text: today.tickerText, speed: speed)
    }

    /// Freezes the scroll when nothing can see it.
    ///
    /// There is no timer to stop any more, but a paused layer is one the window server
    /// stops compositing, which is what the requirement is really about.
    private func observeSystemSleepAndLock() {
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()

        func observe(_ name: NSNotification.Name, on center: NotificationCenter, pause: Bool) {
            systemObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    if pause { self?.tickerView?.pauseAnimation() }
                    else { self?.tickerView?.resumeAnimation() }
                }
            })
        }

        observe(NSWorkspace.screensDidSleepNotification, on: workspace, pause: true)
        observe(NSWorkspace.screensDidWakeNotification, on: workspace, pause: false)
        observe(NSWorkspace.willSleepNotification, on: workspace, pause: true)
        observe(NSWorkspace.didWakeNotification, on: workspace, pause: false)

        // Screen lock has no public AppKit notification; these distributed names are the
        // long-standing way to observe it.
        observe(.init("com.apple.screenIsLocked"), on: distributed, pause: true)
        observe(.init("com.apple.screenIsUnlocked"), on: distributed, pause: false)
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
    /// What the status item is actually doing, for measurement harnesses.
    var diagnosticTickerStatus: String {
        guard let view = tickerView else { return "ticker=off (icon mode)" }
        let onScreen = view.superview != nil && view.window != nil
        var line = "ticker=on animating=\(view.isAnimating) inWindow=\(onScreen) "
                 + "tracking=\(view.diagnosticHasTracking) "
                 + "offset=\(Int(view.diagnosticScrollOffset))pt"
               if let button = statusItem.button, let window = button.window {
            let r = window.convertToScreen(button.convert(button.bounds, to: nil))
            let pointer = NSEvent.mouseLocation
            line += " buttonRect=\(Int(r.midX)),\(Int(r.midY))"
            line += " pointer=\(Int(pointer.x)),\(Int(pointer.y))"
            line += " inside=\(r.contains(pointer))"
        }
        return line
    }

    func diagnosticOpenPopover() { open(on: .verse) }

    /// Where the popover actually landed, relative to the menu bar.
    ///
    /// `NSPopover` exposes no control over its distance from the anchor, so the only
    /// way to know whether a change moved it is to read back the window it opened.
    var diagnosticPopoverGeometry: String {
        guard let button = statusItem.button,
              let statusWindow = button.window,
              let popoverWindow = popover.contentViewController?.view.window,
              let screen = statusWindow.screen ?? NSScreen.main
        else { return "[self-test] geometry unavailable" }

        let gap = screen.visibleFrame.maxY - popoverWindow.frame.maxY
        var out: [String] = []
        // visibleFrame is authoritative for where the menu bar actually ends;
        // NSStatusBar.thickness is the item height and understates it on a notched
        // display, where the menu bar is taller than the items inside it.
        let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
        out.append("[self-test] screen top \(Int(screen.frame.maxY)) statusThickness \(Int(NSStatusBar.system.thickness))pt realMenuBar \(Int(menuBarHeight))pt")
        out.append("[self-test] visibleFrame maxY \(Int(screen.visibleFrame.maxY))")
        out.append("[self-test] statusWindow minY \(Int(statusWindow.frame.minY))")
        let buttonInScreen = statusWindow.convertToScreen(button.convert(button.bounds, to: nil))
        out.append("[self-test] button in screen: \(rect(buttonInScreen))")
        out.append("[self-test] popoverWindow: \(rect(popoverWindow.frame))")
        out.append("[self-test] popover contentSize: \(popover.contentSize)")
        let contentInScreen = popoverWindow.convertToScreen(
            popoverWindow.contentView?.convert(popoverWindow.contentView?.bounds ?? .zero, to: nil) ?? .zero)
        out.append("[self-test] popover contentView in screen: \(rect(contentInScreen))")
        out.append("[self-test] button.bottom -> popover.top: \(Int(buttonInScreen.minY - popoverWindow.frame.maxY))pt")
        out.append("[self-test] gap below menu bar: \(Int(gap))pt")
        return out.joined(separator: "\n")
    }

    private func rect(_ r: NSRect) -> String {
        "x\(Int(r.minX)) y\(Int(r.minY)) w\(Int(r.width)) h\(Int(r.height)) maxY\(Int(r.maxY))"
    }
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
        print(diagnosticPopoverGeometry)
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

    /// How far below the menu bar the popover should sit.
    ///
    /// Left to itself `NSPopover` opens **81pt** below the menu bar on this machine,
    /// which reads as detached from the thing it belongs to. Native menu bar popovers
    /// sit a few points down.
    static var desiredGapBelowMenuBar: CGFloat = 6

    /// Switching between the verse, chapter and settings screens resizes the popover,
    /// and `NSPopover` re-positions itself when it does — undoing the lift. Re-applying
    /// on resize keeps it put; the correction is zero when nothing has moved.
    private func observePopoverResize() {
        guard popoverResizeObserver == nil,
              let window = popover.contentViewController?.view.window else { return }
        popoverResizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.liftPopoverIfNeeded() }
        }
    }

    private func open(on screen: PopoverScreen) {
        guard let button = statusItem.button else { return }
        state.screen = screen
        if !popover.isShown {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            liftPopoverIfNeeded()
            observePopoverResize()
        }
        popover.contentViewController?.view.window?.makeKey()
    }

    /// Pulls the popover up so it sits just under the menu bar.
    ///
    /// `NSPopover` offers no API for its distance from the anchor. Raising the
    /// positioning rect does not work — it clamps, and past a point refuses to show at
    /// all — so the window is moved after the fact, in the same turn as `show` and
    /// before it is drawn, so there is no visible jump.
    ///
    /// The distance is *measured* rather than hard-coded. An 81pt constant happened to
    /// be right on this display, but the default spacing and the menu bar's own height
    /// both vary — a notched display's menu bar is 34pt where `NSStatusBar.thickness`
    /// still reports 22 — so instead this reads back where the window actually landed
    /// and closes the difference. It is also self-limiting: once the gap is right the
    /// correction is zero, which makes it safe to call repeatedly.
    private func liftPopoverIfNeeded() {
        guard let window = popover.contentViewController?.view.window,
              let screen = window.screen ?? statusItem.button?.window?.screen ?? NSScreen.main
        else { return }

        let gap = screen.visibleFrame.maxY - window.frame.maxY
        let correction = gap - Self.desiredGapBelowMenuBar

        // Only ever pull it up, and only when the error is worth a move. Pushing it down
        // is not this method's job, and a sub-point correction is just jitter.
        guard correction > 1 else { return }
        window.setFrameOrigin(NSPoint(x: window.frame.origin.x,
                                      y: window.frame.origin.y + correction))
    }
}
