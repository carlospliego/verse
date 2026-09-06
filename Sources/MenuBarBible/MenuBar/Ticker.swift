import Foundation
import AppKit
import Combine
import MenuBarBibleCore

/// Drives a `TickerWindow` from a timer and reports each new title.
///
/// The constraints in §7.1 are the design, not decoration:
///
/// - **30 characters.** Enforced by `TickerWindow`, which is where it is tested.
/// - **No per-frame animation.** One timer tick, one character of movement. Animating
///   a menu bar string at 60Hz is how these apps end up burning a core. See `interval`
///   for how the rate was chosen.
/// - **Suspended when nothing is watching.** The timer is torn down on display sleep and
///   screen lock, and never created at all for text short enough to sit still.
@MainActor
final class Ticker {

    /// Advance interval.
    ///
    /// The spec sets two numbers that have to be satisfied together: the interval must
    /// be **at least 300ms**, and idle CPU in ticker mode must stay **under 1%**. At the
    /// 300ms floor this measured 1.10% on an M-series laptop, which fails the second.
    ///
    /// What is left at that point is not waste. Profiling shows the remaining time is
    /// `CA::Transaction::commit` — actually drawing the changed text on screen — and
    /// scrolling text cannot be drawn less often than it moves. So the cost is very
    /// nearly linear in the tick rate, and the interval is the only real lever.
    ///
    /// 500ms measures **0.74%** sustained over ten minutes, clears the ceiling with room
    /// to spare, and still reads as a scroll rather than a slideshow.
    static let interval: TimeInterval = 0.5

    var onTitleChange: ((String) -> Void)?

    private var window: TickerWindow?
    private var timer: DispatchSourceTimer?
    private var isSuspendedBySystem = false
    private var isRunning = false
    private var observers: [NSObjectProtocol] = []

    /// Whether a timer is currently scheduled. Read in diagnostics to confirm the thing
    /// really does stop.
    var isTicking: Bool { timer != nil }

    init() {
        observeSystemSleepAndLock()
    }

    deinit {
        timer?.cancel()
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        for observer in observers {
            workspace.removeObserver(observer)
            distributed.removeObserver(observer)
        }
    }

    // MARK: - Control

    /// Starts, or retargets, the ticker. Takes effect immediately with no restart —
    /// toggling the preference is meant to be instant.
    func start(text: String) {
        window = TickerWindow(text: text)
        isRunning = true
        emit()
        resumeIfPossible()
    }

    func stop() {
        isRunning = false
        window = nil
        cancelTimer()
        onTitleChange?("")
    }

    // MARK: - Timer

    private func resumeIfPossible() {
        guard isRunning, !isSuspendedBySystem, timer == nil, let window else { return }
        // Text that fits needs no timer, so idle cost in that case is exactly zero.
        guard !window.fitsWithoutScrolling else { return }

        let timer = DispatchSource.makeTimerSource(queue: .main)
        // Generous leeway lets the system coalesce these wakeups with others, which is
        // most of what keeps idle CPU down.
        timer.schedule(deadline: .now() + Self.interval,
                       repeating: Self.interval,
                       leeway: .milliseconds(100))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            MainActor.assumeIsolated { self.advance() }
        }
        timer.resume()
        self.timer = timer
    }

    private func cancelTimer() {
        timer?.cancel()
        timer = nil
    }

    private func advance() {
        window?.advance()
        emit()
    }

    private func emit() {
        onTitleChange?(window?.title ?? "")
    }

    // MARK: - System suspension

    private func observeSystemSleepAndLock() {
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()

        func observe(_ name: NSNotification.Name, on center: NotificationCenter, suspended: Bool) {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.setSystemSuspended(suspended) }
            })
        }

        observe(NSWorkspace.screensDidSleepNotification, on: workspace, suspended: true)
        observe(NSWorkspace.screensDidWakeNotification, on: workspace, suspended: false)
        observe(NSWorkspace.willSleepNotification, on: workspace, suspended: true)
        observe(NSWorkspace.didWakeNotification, on: workspace, suspended: false)

        // Screen lock has no public AppKit notification; these distributed names are the
        // long-standing way to observe it.
        observe(.init("com.apple.screenIsLocked"), on: distributed, suspended: true)
        observe(.init("com.apple.screenIsUnlocked"), on: distributed, suspended: false)
    }

    private func setSystemSuspended(_ suspended: Bool) {
        guard isSuspendedBySystem != suspended else { return }
        isSuspendedBySystem = suspended
        if suspended {
            cancelTimer()
        } else {
            resumeIfPossible()
        }
    }
}
