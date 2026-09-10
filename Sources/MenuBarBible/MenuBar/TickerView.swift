import AppKit
import MenuBarBibleCore

/// The scrolling verse, as a Core Animation marquee inside the status item.
///
/// The previous ticker retitled the status button on a timer. That can only ever step by
/// a whole character — about seven points — so it jumped visibly however fast it ran,
/// and each step cost a synchronous menu bar redraw in this process.
///
/// This instead hands the window server one instruction: translate a text layer at a
/// constant rate, forever. Interpolation happens outside this process, in fractions of a
/// point, at the display's own refresh rate. The motion is continuous and there is no
/// timer here at all.
@MainActor
final class TickerView: NSView {

    /// Holds the doubled text and is the thing that actually moves.
    private let scrollLayer = CATextLayer()

    private var text: String = ""
    private var speed: TickerSpeed = .default

    /// Width of one copy-plus-gap: the exact distance one loop travels.
    private var loopWidth: CGFloat = 0

    private var isPaused = false

    /// The verse only moves while the pointer is over it. At rest it shows the opening
    /// words, held still and legible — a line of text scrolling past forever is harder
    /// to read at a glance than one that simply sits there, and it asks the eye to
    /// follow something the reader did not ask for. Motion is opt-in, on hover.
    private var isHovering = false

    private var trackingArea: NSTrackingArea?

    static let font = NSFont.menuBarFont(ofSize: 0)

    /// The item's width, from §7.1's 30-character cap.
    static var preferredWidth: CGFloat {
        let sample = String(repeating: "n", count: TickerLayout.visibleCharacters)
        return ceil((sample as NSString).size(withAttributes: [.font: font]).width)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true          // clip the overhang to the item's width
        scrollLayer.isWrapped = false
        scrollLayer.truncationMode = .none
        scrollLayer.alignmentMode = .left
        scrollLayer.font = TickerView.font
        scrollLayer.fontSize = TickerView.font.pointSize
        scrollLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        layer?.addSublayer(scrollLayer)
        applyTextColor()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Clicks belong to the status item button underneath, not to this view — otherwise
    /// covering the button with a subview would swallow every click and the popover and
    /// context menu would stop opening.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    // MARK: - Configuration

    func configure(text: String, speed: TickerSpeed) {
        let changedText = text != self.text
        self.text = text
        self.speed = speed
        if changedText { rebuildText() }
        updateMotion()
    }

    // MARK: - Hover

    /// Tracking lives on the status button rather than on this view.
    ///
    /// This view returns nil from `hitTest` so clicks reach the button underneath, and a
    /// view that is invisible to hit testing is not a reliable place to hang mouse
    /// tracking. The button is the thing the pointer is really over.
    func installTracking(on host: NSView) {
        if let trackingArea { host.removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self,
                                  userInfo: nil)
        host.addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { setHovering(true) }
    override func mouseExited(with event: NSEvent) { setHovering(false) }

    func setHovering(_ hovering: Bool) {
        guard hovering != isHovering else { return }
        isHovering = hovering
        updateMotion()
    }

    private func rebuildText() {
        let looped = TickerLayout.looped(text)
        scrollLayer.string = looped

        let attributes: [NSAttributedString.Key: Any] = [.font: TickerView.font]
        let fullWidth = (looped as NSString).size(withAttributes: attributes).width
        loopWidth = fullWidth * TickerLayout.loopFraction

        // Vertically centred on the layer, full text width so nothing truncates.
        let height = bounds.height > 0 ? bounds.height : TickerView.font.boundingRectForFont.height
        scrollLayer.frame = CGRect(x: 0, y: 0, width: ceil(fullWidth), height: height)
    }

    override func layout() {
        super.layout()
        if scrollLayer.frame.height != bounds.height { rebuildText() }
    }

    // MARK: - Animation

    /// Starts or stops the scroll to match the hover state.
    ///
    /// Removing the animation returns the layer to its model position, which is the
    /// start of the verse — so stopping and resting at the opening words are the same
    /// operation, with no extra bookkeeping.
    private func updateMotion() {
        guard isHovering, !isPaused else {
            scrollLayer.removeAnimation(forKey: Self.animationKey)
            return
        }
        restartAnimation()
    }

    private func restartAnimation() {
        scrollLayer.removeAnimation(forKey: Self.animationKey)
        guard loopWidth > 0, speed.pointsPerSecond > 0 else { return }

        let animation = CABasicAnimation(keyPath: "position.x")
        let start = scrollLayer.frame.width / 2          // position is the layer's centre
        animation.fromValue = start
        animation.toValue = start - loopWidth
        animation.duration = loopWidth / speed.pointsPerSecond
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        // Linear, explicitly. The default ease-in-out would make a marquee surge and
        // stall once per loop, which reads as broken rather than gentle.
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        scrollLayer.add(animation, forKey: Self.animationKey)
    }

    static let animationKey = "verseScroll"

    #if DEBUG
    /// Drives hover from code, to check the state machine without a mouse.
    func diagnosticSetHovering(_ hovering: Bool) {
        isHovering = hovering
        updateMotion()
    }

    /// Where the text currently sits, so "static" can be shown to actually be static.
    var diagnosticScrollOffset: CGFloat {
        let presented = scrollLayer.presentation() ?? scrollLayer
        return scrollLayer.frame.width / 2 - presented.position.x
    }

    var diagnosticHasTracking: Bool { trackingArea != nil }

    /// Everything that could plausibly make the layer draw nothing.
    var diagnosticDescription: String {
        let colour = scrollLayer.foregroundColor.map { NSColor(cgColor: $0)?.description ?? "?" } ?? "nil"
        var lines: [String] = []
        lines.append("      view.bounds=\(bounds.size) viewLayer.bounds=\(layer?.bounds.size ?? .zero)")
        lines.append("      masksToBounds=\(layer?.masksToBounds ?? false) sublayers=\(layer?.sublayers?.count ?? 0)")
        lines.append("      textLayer.frame=\(scrollLayer.frame)")
        lines.append("      string=\(((scrollLayer.string as? String) ?? "").count) chars fontSize=\(scrollLayer.fontSize)")
        lines.append("      font=\(String(describing: scrollLayer.font)) foreground=\(colour)")
        lines.append("      contentsScale=\(scrollLayer.contentsScale) loopWidth=\(loopWidth)")
        return lines.joined(separator: "\n")
    }
    #endif

    /// True when the scroll instruction is actually installed. Read by diagnostics.
    var isAnimating: Bool { scrollLayer.animation(forKey: Self.animationKey) != nil }

    /// Freezes the layer's local time. Nothing is running to stop, but a paused layer
    /// stops the window server compositing it, which is the point when the display is
    /// asleep or the screen is locked.
    func pauseAnimation() {
        isPaused = true
        guard scrollLayer.speed != 0 else { return }
        let frozen = scrollLayer.convertTime(CACurrentMediaTime(), from: nil)
        scrollLayer.speed = 0
        scrollLayer.timeOffset = frozen
    }

    func resumeAnimation() {
        isPaused = false
        guard scrollLayer.speed == 0 else { return }
        let frozen = scrollLayer.timeOffset
        scrollLayer.speed = 1
        scrollLayer.timeOffset = 0
        scrollLayer.beginTime = 0
        // Shift beginTime by the time spent paused, so the scroll carries on from where
        // it stopped instead of snapping.
        scrollLayer.beginTime = scrollLayer.convertTime(CACurrentMediaTime(), from: nil) - frozen
    }

    // MARK: - Appearance

    /// A `CATextLayer` gets none of the automatic menu bar behaviour a template image
    /// does, so the colour is resolved by hand and re-resolved whenever the menu bar
    /// switches between light and dark.
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTextColor()
    }

    private func applyTextColor() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            scrollLayer.foregroundColor = NSColor.labelColor.cgColor
        }
    }

    /// Renders the layer tree as it currently stands.
    ///
    /// Goes through `CALayer.render(in:)` rather than `cacheDisplay(in:to:)`. The latter
    /// draws a view's own `draw(_:)` output and silently ignores manually added
    /// sublayers, so it returns a perfectly blank image for this view — which looks like
    /// proof the ticker renders, and is the opposite.
    func snapshot(background: NSColor = .clear) -> NSImage? {
        guard bounds.width > 0, bounds.height > 0, let layer else { return nil }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let pixels = CGSize(width: bounds.width * scale, height: bounds.height * scale)

        guard let context = CGContext(data: nil,
                                      width: Int(pixels.width),
                                      height: Int(pixels.height),
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        context.setFillColor(background.cgColor)
        context.fill(CGRect(origin: .zero, size: pixels))
        context.scaleBy(x: scale, y: scale)
        layer.render(in: context)

        guard let image = context.makeImage() else { return nil }
        return NSImage(cgImage: image, size: bounds.size)
    }
}
