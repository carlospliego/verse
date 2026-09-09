import AppKit
import MenuBarBibleCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var state: AppState?
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let state = AppState()
        self.state = state
        self.statusItemController = StatusItemController(state: state)

        #if DEBUG
        if CommandLine.arguments.contains("--self-test") {
            let controller = self.statusItemController
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                MainActor.assumeIsolated {
                    controller?.selfTest()
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

        // Proof that the ticker is actually scrolling, for CPU measurement. Reading the
        // preference back is not proof: it says what was asked for, not what the app is
        // doing, and a measurement of a stopped ticker looks like a triumphant pass.
        if CommandLine.arguments.contains("--report-title") {
            let started = Date()
            Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
                MainActor.assumeIsolated {
                    let elapsed = Int(Date().timeIntervalSince(started))
                    FileHandle.standardError.write(
                        "[t+\(elapsed)s] speed=\(state.tickerSpeed.rawValue) |\(StatusItemTitle.shared.value)|\n"
                            .data(using: .utf8)!)
                }
            }
        }
        #endif
    }

    /// Nothing to restore and no windows to reopen — this app lives in the menu bar.
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
