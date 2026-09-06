import Foundation

/// The scrolling-window arithmetic behind ticker mode.
///
/// Kept here, apart from the timer and the status item, so the constraint that actually
/// matters — a title that never exceeds 30 characters, whatever the verse — can be
/// tested without a menu bar.
public struct TickerWindow {

    /// Hard cap. macOS gives status items whatever horizontal room is left over, and on
    /// a notched display a long title is truncated or pushed under the notch.
    public static let maxLength = 30

    private let characters: [Character]
    public private(set) var offset = 0

    public init(text: String, separator: String = "   \u{00B7}   ") {
        // Padding so the end of the passage does not run straight into its start.
        self.characters = Array(TickerWindow.normalize(text) + separator)
    }

    public var isEmpty: Bool { characters.isEmpty }

    /// True when the text fits without moving, so no timer is needed at all.
    public var fitsWithoutScrolling: Bool { characters.count <= Self.maxLength }

    public var length: Int { characters.count }

    /// The visible slice, wrapping around the end of the text.
    public var title: String {
        guard !characters.isEmpty else { return "" }
        let count = min(Self.maxLength, characters.count)
        var slice = String()
        slice.reserveCapacity(count)
        for i in 0..<count {
            slice.append(characters[(offset + i) % characters.count])
        }
        return slice
    }

    public mutating func advance() {
        guard !characters.isEmpty else { return }
        offset = (offset + 1) % characters.count
    }

    /// Collapses runs of whitespace so the scroll advances one visible character at a
    /// time and a line break in the source text does not open a gap.
    public static func normalize(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
