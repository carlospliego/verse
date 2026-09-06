import Foundation
import ServiceManagement

/// Launch at login, in one place.
///
/// Both the settings screen and the status item's context menu offer this, and they must
/// not drift apart — particularly in how they handle failure, which is common enough to
/// matter: `SMAppService` needs a signed app in a stable location and refuses while the
/// app is running from a build directory.
enum LaunchAtLogin {

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Returns nil on success, or a message to show the user.
    @discardableResult
    static func set(_ enabled: Bool) -> String? {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            return "Couldn't change this. Move the app to /Applications and try again."
        }
    }
}
