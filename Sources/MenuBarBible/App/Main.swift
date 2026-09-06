import AppKit

/// A plain AppKit entry point rather than a SwiftUI `App`.
///
/// The status item is AppKit-owned (see `StatusItemController`), which leaves a SwiftUI
/// `App` with no scene to declare. Giving it an inert `Settings` scene looks like the
/// tidy answer and silently does not work: with no real scene the app never finishes
/// launching, `applicationDidFinishLaunching` never fires, and no status item is ever
/// created — a menu bar app that starts and shows nothing, with no error anywhere.
///
/// Owning the lifecycle directly is unambiguous. The popover content is still SwiftUI.
@main
enum Main {
    @MainActor
    static func main() {
        let application = NSApplication.shared

        #if DEBUG
        PreviewRenderer.runIfRequested()
        #endif

        // Menu bar only: no Dock icon. Matches LSUIElement in the Info.plist, and set
        // here too so it holds when the binary is run straight from a build directory.
        application.setActivationPolicy(.accessory)

        let delegate = AppDelegate()
        application.delegate = delegate
        application.run()
    }
}
