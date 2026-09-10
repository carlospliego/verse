import AppKit
import MenuBarBibleCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var state: AppState?
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let state = AppState()
        self.state = state
        let controller = StatusItemController(state: state)
        self.statusItemController = controller

        #if DEBUG
        // --popover-nudge <points>: override the target gap below the menu bar.
        if let flag = CommandLine.arguments.firstIndex(of: "--popover-nudge"),
           CommandLine.arguments.indices.contains(flag + 1),
           let points = Double(CommandLine.arguments[flag + 1]) {
            StatusItemController.desiredGapBelowMenuBar = points
        }

        // --report-popover: open the popover once the status item has settled into the
        // menu bar and report where it landed. The self-test measures 0.5s after launch,
        // which is before macOS has placed the item, so its geometry is not real.
        if CommandLine.arguments.contains("--report-popover") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                MainActor.assumeIsolated {
                    controller.diagnosticOpenPopover()
                    // Each screen is a different height, so each one resizes the popover
                    // and gives NSPopover a chance to undo the lift.
                    let screens: [(String, PopoverScreen)] =
                        [("verse", .verse), ("chapter", .chapter), ("settings", .settings), ("verse", .verse)]
                    var delay = 1.5
                    for (name, screen) in screens {
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                            MainActor.assumeIsolated {
                                state.screen = screen
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                                    MainActor.assumeIsolated {
                                        print("[screen \(name)]")
                                        print(controller.diagnosticPopoverGeometry)
                                    }
                                }
                            }
                        }
                        delay += 1.4
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay + 1) {
                        MainActor.assumeIsolated { () -> Void in exit(0) }
                    }
                }
            }
        }

        if CommandLine.arguments.contains("--self-test") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                MainActor.assumeIsolated {
                    controller.selfTest()
                    exit(0)
                }
            }
        }

        // Turns ticker mode on through the same property the settings switch is bound
        // to, so a CPU measurement measures what a user would actually get. Setting the
        // preference with the `defaults` CLI instead is not reliable: cfprefsd serves
        // the CLI and the app different snapshots of the domain.
        if CommandLine.arguments.contains("--ticker-on") {
            state.tickerEnabled = true
        }

        // --ticker-speed <leisurely|steady|brisk>, same path as the settings picker.
        if let flag = CommandLine.arguments.firstIndex(of: "--ticker-speed"),
           CommandLine.arguments.indices.contains(flag + 1),
           let speed = TickerSpeed(rawValue: CommandLine.arguments[flag + 1]) {
            state.tickerSpeed = speed
        }

        // Proof that the ticker is really installed and running, for measurement.
        //
        // The previous version of this printed the status item's title, which proved the
        // ticker's *logic* was running but not that the menu bar was drawing it — and
        // that gap produced a completely fictional set of CPU numbers once already. What
        // it reports now is the state of the animation on the layer the window server
        // composites, which is the thing that costs anything.
        if CommandLine.arguments.contains("--report-ticker") {
            let started = Date()
            Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
                MainActor.assumeIsolated {
                    let elapsed = Int(Date().timeIntervalSince(started))
                    let status = controller.diagnosticTickerStatus
                    FileHandle.standardError.write(
                        "[t+\(elapsed)s] speed=\(state.tickerSpeed.rawValue) \(status)\n"
                            .data(using: .utf8)!)
                }
            }
        }
        #endif
    }

    /// Nothing to restore and no windows to reopen — this app lives in the menu bar.
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
