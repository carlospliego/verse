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
        #endif
    }

    /// Nothing to restore and no windows to reopen — this app lives in the menu bar.
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
