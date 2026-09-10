import Foundation

/// The text-shaping rules behind the scrolling menu bar item.
///
/// The ticker used to advance a 30-character window one character at a time on a timer.
/// It could not be made smooth, and the reason is arithmetic rather than tuning: the
/// smallest step available to text is one character, about seven points in the menu bar
/// font, so every advance is a seven-point jump however often it fires. Raising the rate
/// buys more jumps per second, not smaller ones.
///
/// Scrolling is now a Core Animation translation of a text layer, which moves in
/// fractions of a point and is interpolated by the window server. What is left for this
/// type is the shaping: how wide the item may be, and how the text is composed so the
/// loop has no seam.
public enum TickerLayout {

    /// The width cap, still expressed in characters.
    ///
    /// §7.1 caps the status item at 30 characters. That number is really about not
    /// hogging a menu bar that has to share space with a notch, so it now sets the
    /// *width* of a fixed-size item rather than the length of a string. The constraint
    /// is unchanged; only its unit is.
    public static let visibleCharacters = 30

    /// The break between the end of the passage and its beginning.
    ///
    /// Whitespace, no glyph. A middle dot lived here once and read as debris drifting
    /// through the scripture.
    public static let gap = "     "

    /// The text to scroll, composed so the wrap is seamless.
    ///
    /// Two copies with a gap after each. The animation translates by exactly one
    /// copy-plus-gap and repeats, so the second copy is always occupying the space the
    /// first is vacating and the loop has no visible seam or blank sweep.
    public static func looped(_ text: String) -> String {
        let unit = normalize(text) + gap
        return unit + unit
    }

    /// The fraction of `looped(_:)` that one loop covers — always exactly half.
    public static let loopFraction = 0.5

    /// Collapses runs of whitespace, so a line break in the source text does not open a
    /// hole in the middle of the scroll.
    public static func normalize(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
