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

    var onTitleChange: ((String) -> Void)?

    /// Changing this reschedules the timer at the new interval, keeping the scroll
    /// position — the text carries on from where it was rather than snapping back.
    var speed: TickerSpeed = .default {
        didSet {
            guard speed != oldValue, timer != nil else { return }
            cancelTimer()
            resumeIfPossible()
        }
    }

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
    func start(text: String, speed: TickerSpeed) {
        self.speed = speed
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
        // Leeway lets the system coalesce these wakeups with others, which is a real
        // part of what keeps the cost down. Kept to a fraction of the interval so it
        // cannot visibly stutter the scroll at the faster settings.
        let interval = speed.interval
        timer.schedule(deadline: .now() + interval,
                       repeating: interval,
                       leeway: .milliseconds(Int(interval * 1000 / 5)))
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
        // One character. It is the smallest step the medium allows, and therefore the
        // smoothest; speed is the interval, not the distance.
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
