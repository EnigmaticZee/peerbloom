// Draws the DMG background in the Ocean colours of the app icon (Support/AppIcon.icon).
// Run: swift scripts/make-art.swift   (writes into Support/)
import AppKit

let support = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Support")

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

// Ocean, from the falling tile to the arrow tip.
let ocean: [UInt32] = [0x3C6BFF, 0x2F8CF0, 0x26B8F0, 0x2DE1C2]
let navy = color(0x0E2A4A)

func render(width: Int, height: Int, _ draw: (CGContext) -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    // Flip so y grows downwards, like a design tool.
    ctx.cgContext.translateBy(x: 0, y: CGFloat(height))
    ctx.cgContext.scaleBy(x: 1, y: -1)
    draw(ctx.cgContext)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func save(_ rep: NSBitmapImageRep, _ url: URL) {
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

/// A rounded tile like the pieces in the icon, with a soft trail above it when it's falling.
func tile(_ ctx: CGContext, x: CGFloat, y: CGFloat, size: CGFloat, angle: CGFloat, hex: UInt32, alpha: CGFloat,
          trail: CGFloat, k: CGFloat) {
    let s = size * k
    ctx.saveGState()
    ctx.translateBy(x: x * k, y: y * k)
    if trail > 0 {
        let t = trail * k
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -s * 0.4, y: -s / 2 - t))
        path.addLine(to: CGPoint(x: s * 0.4, y: -s / 2 - t))
        path.addLine(to: CGPoint(x: s * 0.47, y: -s / 2))
        path.addLine(to: CGPoint(x: -s * 0.47, y: -s / 2))
        path.closeSubpath()
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                           colors: [color(hex, 0).cgColor, color(hex, alpha * 0.6).cgColor] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: -s / 2 - t), end: CGPoint(x: 0, y: -s / 2), options: [])
        ctx.restoreGState()
    }
    ctx.rotate(by: angle * .pi / 180)
    let rect = CGRect(x: -s / 2, y: -s / 2, width: s, height: s)
    let shape = CGPath(roundedRect: rect, cornerWidth: s * 0.24, cornerHeight: s * 0.24, transform: nil)
    ctx.addPath(shape)
    ctx.clip()
    let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                       colors: [color(hex, alpha * 0.75).cgColor, color(hex, alpha).cgColor] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: rect.minY), end: CGPoint(x: 0, y: rect.maxY), options: [])
    ctx.restoreGState()
}

// MARK: - DMG background (660 × 420 points)

func drawBackground(_ ctx: CGContext, scale k: CGFloat) {
    let w = 660 * k, h = 420 * k
    // Light, so Finder's dark icon labels stay readable, with a faint cool tint.
    let bg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                        colors: [color(0xFBFCFE).cgColor, color(0xEAF1F8).cgColor] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: .zero, end: CGPoint(x: 0, y: h), options: [])

    // Pieces settling along the bottom edge, a few still falling. Faint, so the icons stay the focus.
    let pieces: [(x: CGFloat, y: CGFloat, size: CGFloat, angle: CGFloat, colour: Int, alpha: CGFloat, trail: CGFloat)] = [
        (34, 398, 34, 0, 1, 0.10, 0),
        (78, 404, 26, 0, 2, 0.08, 0),
        (128, 396, 30, 0, 0, 0.07, 0),
        (226, 402, 24, 0, 3, 0.08, 0),
        (318, 400, 28, 0, 1, 0.06, 0),
        (436, 404, 26, 0, 2, 0.07, 0),
        (536, 398, 32, 0, 0, 0.08, 0),
        (588, 404, 24, 0, 3, 0.09, 0),
        (632, 396, 34, 0, 1, 0.10, 0),
        (96, 330, 18, -12, 0, 0.20, 46),
        (574, 318, 16, 10, 3, 0.22, 40),
        (612, 52, 14, -8, 2, 0.18, 34),
        (52, 70, 12, 9, 1, 0.16, 30),
    ]
    for p in pieces {
        tile(ctx, x: p.x, y: p.y, size: p.size, angle: p.angle, hex: ocean[p.colour], alpha: p.alpha, trail: p.trail, k: k)
    }

    func text(_ s: String, size: CGFloat, weight: NSFont.Weight, color c: NSColor, centerY: CGFloat, tracking: CGFloat = 0) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size * k, weight: weight),
            .foregroundColor: c,
            .kern: tracking * k
        ]
        let str = NSAttributedString(string: s, attributes: attrs)
        let b = str.size()
        ctx.saveGState()
        // Undo the flip for text, then place it.
        ctx.textMatrix = .identity
        ctx.translateBy(x: 0, y: h)
        ctx.scaleBy(x: 1, y: -1)
        str.draw(at: CGPoint(x: (w - b.width) / 2, y: h - centerY * k - b.height / 2))
        ctx.restoreGState()
    }
    text("Peerbloom", size: 30, weight: .bold, color: navy, centerY: 58, tracking: -0.4)
    text("Drag Peerbloom into Applications to install", size: 13, weight: .regular, color: color(0x4E5E73), centerY: 92)

    // Dotted arrow between the two icons (centred at x 180 and 480, y 205), fading blue to aqua.
    let y = 205 * k
    let arrow = CGMutablePath()
    arrow.move(to: CGPoint(x: 380 * k, y: y - 9 * k))
    arrow.addLine(to: CGPoint(x: 391 * k, y: y))
    arrow.addLine(to: CGPoint(x: 380 * k, y: y + 9 * k))
    ctx.saveGState()
    ctx.setLineWidth(2.5 * k)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.setLineDash(phase: 0, lengths: [1 * k, 9 * k])
    ctx.move(to: CGPoint(x: 268 * k, y: y))
    ctx.addLine(to: CGPoint(x: 384 * k, y: y))
    ctx.replacePathWithStrokedPath()
    ctx.setLineDash(phase: 0, lengths: [])
    ctx.addPath(arrow.copy(strokingWithWidth: 2.5 * k, lineCap: .round, lineJoin: .round, miterLimit: 10))
    ctx.clip()
    let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                       colors: [color(ocean[1]).cgColor, color(ocean[3]).cgColor] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: 268 * k, y: y), end: CGPoint(x: 392 * k, y: y), options: [])
    ctx.restoreGState()

    text("Free and open source · Version 1.0", size: 11, weight: .medium, color: color(0x7D8A9C), centerY: 330)
}

save(render(width: 660, height: 420) { drawBackground($0, scale: 1) }, support.appendingPathComponent("dmg-background.png"))
save(render(width: 1320, height: 840) { drawBackground($0, scale: 2) }, support.appendingPathComponent("dmg-background@2x.png"))
print("Wrote DMG background to \(support.path)")
