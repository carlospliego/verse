import Foundation

/// How fast the ticker scrolls, in points per second.
///
/// Points, not characters. The scroll is a Core Animation translation now, so it moves
/// continuously rather than in character steps and there is no interval to set — the
/// window server interpolates every frame and this process does no per-frame work at
/// all. That is also why none of these settings carries a power warning any more: the
/// old ones each had a different tick rate and so a different CPU cost, and these do not
/// tick.
public enum TickerSpeed: String, CaseIterable, Sendable {
    case leisurely
    case steady
    case brisk

    public static let `default` = TickerSpeed.steady

    /// Points travelled per second.
    ///
    /// The menu bar font averages a little over six points per character, so these work
    /// out to roughly 3, 5.5 and 9 characters a second. Reading pace rather than
    /// stock-ticker pace: the point is to be legible in a glance, not to finish.
    public var pointsPerSecond: Double {
        switch self {
        case .leisurely: return 20
        case .steady:    return 35
        case .brisk:     return 55
        }
    }

    public var displayName: String {
        switch self {
        case .leisurely: return "Leisurely"
        case .steady:    return "Steady"
        case .brisk:     return "Brisk"
        }
    }
}
