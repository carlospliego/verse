import AppKit

// Renders the app icon at every size the .icns needs.
// Placeholder art: §11 lists icon design as an open question.

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else { image.unlockFocus(); return image }
    let s = size / 1024.0
    ctx.scaleBy(x: s, y: s)

    // Rounded slab background
    let inset: CGFloat = 64, side: CGFloat = 896, radius: CGFloat = 200
    let slab = CGPath(roundedRect: CGRect(x: inset, y: inset, width: side, height: side),
                      cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.saveGState()
    ctx.addPath(slab); ctx.clip()
    let space = CGColorSpaceCreateDeviceRGB()
    let gradient = CGGradient(colorsSpace: space,
                              colors: [CGColor(red: 0.23, green: 0.25, blue: 0.29, alpha: 1),
                                       CGColor(red: 0.13, green: 0.15, blue: 0.17, alpha: 1)] as CFArray,
                              locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 960), end: CGPoint(x: 0, y: 64), options: [])
    ctx.restoreGState()

    // Open book, centred
    ctx.saveGState()
    ctx.translateBy(x: 512, y: 470)

    let page = CGColor(red: 0.98, green: 0.97, blue: 0.95, alpha: 1)
    func leaf(mirrored: Bool) -> CGPath {
        let p = CGMutablePath()
        let d: CGFloat = mirrored ? -1 : 1
        p.move(to: CGPoint(x: d * 300, y: 150))
        p.addQuadCurve(to: CGPoint(x: d * 8, y: 150), control: CGPoint(x: d * 150, y: 200))
        p.addLine(to: CGPoint(x: d * 8, y: -170))
        p.addQuadCurve(to: CGPoint(x: d * 300, y: -170), control: CGPoint(x: d * 150, y: -120))
        p.closeSubpath()
        return p
    }
    ctx.setFillColor(page)
    ctx.addPath(leaf(mirrored: true)); ctx.fillPath()
    ctx.addPath(leaf(mirrored: false)); ctx.fillPath()

    // Spine
    ctx.setFillColor(CGColor(red: 0.79, green: 0.76, blue: 0.70, alpha: 1))
    ctx.addPath(CGPath(roundedRect: CGRect(x: -9, y: -176, width: 18, height: 336),
                       cornerWidth: 6, cornerHeight: 6, transform: nil))
    ctx.fillPath()

    // Lines of text
    ctx.setStrokeColor(CGColor(red: 0.71, green: 0.67, blue: 0.60, alpha: 1))
    ctx.setLineWidth(14); ctx.setLineCap(.round)
    for (i, y) in [90, 20, -50].enumerated() {
        let tilt = CGFloat(22 - i * 0)
        ctx.move(to: CGPoint(x: -250, y: CGFloat(y)));   ctx.addLine(to: CGPoint(x: -60, y: CGFloat(y) + tilt))
        ctx.move(to: CGPoint(x: 60, y: CGFloat(y) + tilt)); ctx.addLine(to: CGPoint(x: 250, y: CGFloat(y)))
    }
    ctx.strokePath()
    ctx.restoreGState()

    image.unlockFocus()
    return image
}

let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

for (size, scale) in [(16,1),(16,2),(32,1),(32,2),(128,1),(128,2),(256,1),(256,2),(512,1),(512,2)] {
    let pixels = CGFloat(size * scale)
    let image = drawIcon(size: pixels)
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { continue }
    let name = scale == 1 ? "icon_\(size)x\(size).png" : "icon_\(size)x\(size)@2x.png"
    try? png.write(to: URL(fileURLWithPath: "\(out)/\(name)"))
    print("wrote \(name) (\(Int(pixels))px)")
}
