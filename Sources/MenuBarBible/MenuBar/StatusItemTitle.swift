import Foundation
import SwiftUI

/// The status item's title, published on its own.
///
/// Deliberately *not* a property of `AppState`. The ticker republishes three times a
/// second, and anything the `App`'s own body reads invalidates the entire scene — the
/// whole popover view tree included, open or not. Holding the title in a separate
/// object that only `StatusItemLabel` observes keeps each tick's redraw to the single
/// piece of text that actually changed.
///
/// A shared instance rather than owned state: there is exactly one status item, and the
/// `App` struct must not hold it, because holding it would resubscribe the scene.
@MainActor
final class StatusItemTitle: ObservableObject {
    static let shared = StatusItemTitle()

    @Published private(set) var value: String = ""

    private init() {}

    func set(_ newValue: String) {
        // Publishing an unchanged value would still invalidate the label.
        guard newValue != value else { return }
        value = newValue
    }
}
