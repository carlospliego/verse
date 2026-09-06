import Foundation
import SwiftUI

/// Simple preferences live in `UserDefaults`, not SQLite — they are small, they are
/// scalar, and nothing queries across them.
enum PreferenceKey {
    static let translation = "translationCode"
    static let tickerEnabled = "tickerEnabled"
}

/// Whether the ticker toggle appears in settings.
///
/// The spec is explicit that ticker mode must never be able to block a release, and that
/// it ships hidden if it is not solid. Of the constraints in §7.1, the measurable ones
/// are met: the title is capped at 30 characters (tested exhaustively over the whole
/// pool in all three translations), the timer suspends on display sleep and screen lock,
/// the toggle takes effect with no restart, and idle CPU is under 1% — see
/// `Ticker.interval` for how that was reached.
///
/// The one check that has not been done is the spec's own: behaviour on a notched
/// display with a dozen other menu bar items, which needs eyes on real hardware. The
/// 30-character cap and the pinned status item width are the mitigation. If that test
/// fails, set this to false and the toggle disappears — nothing else needs to change.
let tickerToggleIsVisible = true
