// Renders the Swoosh app icon into an .iconset and converts it to .icns.
// Usage: swift Scripts/make-icon.swift Resources/AppIcon.icns
import AppKit

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/AppIcon.icns"

func drawIcon(_ s: CGFloat) {
    // macOS icon grid: 1024 canvas, 824 body, 185 corner radius.
    let inset = s * 100 / 1024
    let body = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let radius = body.width * 0.2245

    // Drop shadow under the body.
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = s * 0.025
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.012)
    shadow.set()
    let squircle = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)
    NSColor.black.setFill()
    squircle.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Background gradient: violet top-left → cyan bottom-right.
    NSGraphicsContext.saveGraphicsState()
    squircle.addClip()
    NSGradient(colors: [
        NSColor(srgbRed: 0.44, green: 0.33, blue: 0.98, alpha: 1),
        NSColor(srgbRed: 0.27, green: 0.45, blue: 0.98, alpha: 1),
        NSColor(srgbRed: 0.13, green: 0.78, blue: 0.86, alpha: 1),
    ])!.draw(in: body, angle: -50)
    // Soft top highlight.
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.22), NSColor.white.withAlphaComponent(0)])!
        .draw(in: NSRect(x: body.minX, y: body.midY, width: body.width, height: body.height / 2), angle: -90)

    // Window card.
    let card = NSRect(x: body.minX + body.width * 0.16, y: body.minY + body.height * 0.22,
                      width: body.width * 0.68, height: body.height * 0.52)
    let cardRadius = card.width * 0.08
    NSGraphicsContext.saveGraphicsState()
    let cardShadow = NSShadow()
    cardShadow.shadowColor = NSColor(srgbRed: 0.08, green: 0.05, blue: 0.35, alpha: 0.45)
    cardShadow.shadowBlurRadius = s * 0.04
    cardShadow.shadowOffset = NSSize(width: 0, height: -s * 0.015)
    cardShadow.set()
    NSColor.white.withAlphaComponent(0.96).setFill()
    NSBezierPath(roundedRect: card, xRadius: cardRadius, yRadius: cardRadius).fill()
    NSGraphicsContext.restoreGraphicsState()

    // Title bar dots.
    let dotR = card.width * 0.028
    let dotY = card.maxY - card.height * 0.12
    for (i, color) in [NSColor(srgbRed: 1, green: 0.37, blue: 0.34, alpha: 1),
                       NSColor(srgbRed: 1, green: 0.74, blue: 0.18, alpha: 1),
                       NSColor(srgbRed: 0.16, green: 0.79, blue: 0.27, alpha: 1)].enumerated() {
        color.setFill()
        let x = card.minX + card.width * 0.07 + CGFloat(i) * dotR * 3
        NSBezierPath(ovalIn: NSRect(x: x - dotR, y: dotY - dotR, width: dotR * 2, height: dotR * 2)).fill()
    }

    // Snapped left pane.
    let content = NSRect(x: card.minX + card.width * 0.06, y: card.minY + card.height * 0.09,
                         width: card.width * 0.88, height: card.height * 0.66)
    let pane = NSRect(x: content.minX, y: content.minY, width: content.width * 0.46, height: content.height)
    NSGradient(colors: [NSColor(srgbRed: 0.42, green: 0.36, blue: 0.98, alpha: 1),
                        NSColor(srgbRed: 0.20, green: 0.62, blue: 0.95, alpha: 1)])!
        .draw(in: NSBezierPath(roundedRect: pane, xRadius: cardRadius * 0.6, yRadius: cardRadius * 0.6), angle: -60)
    // Ghost right pane.
    let ghost = NSRect(x: pane.maxX + content.width * 0.08, y: content.minY, width: content.width * 0.46, height: content.height)
    let ghostPath = NSBezierPath(roundedRect: ghost, xRadius: cardRadius * 0.6, yRadius: cardRadius * 0.6)
    NSColor(srgbRed: 0.35, green: 0.45, blue: 0.95, alpha: 0.12).setFill()
    ghostPath.fill()
    ghostPath.lineWidth = s * 0.006
    ghostPath.setLineDash([s * 0.018, s * 0.012], count: 2, phase: 0)
    NSColor(srgbRed: 0.35, green: 0.45, blue: 0.95, alpha: 0.45).setStroke()
    ghostPath.stroke()
    NSGraphicsContext.restoreGraphicsState()

    // The swoosh: a tapered white arc sweeping across the card.
    NSGraphicsContext.saveGraphicsState()
    let arcShadow = NSShadow()
    arcShadow.shadowColor = NSColor(srgbRed: 0.1, green: 0.05, blue: 0.4, alpha: 0.35)
    arcShadow.shadowBlurRadius = s * 0.02
    arcShadow.shadowOffset = NSSize(width: 0, height: -s * 0.008)
    arcShadow.set()
    let p = { (x: CGFloat, y: CGFloat) in NSPoint(x: body.minX + body.width * x, y: body.minY + body.height * y) }
    let swoosh = NSBezierPath()
    swoosh.move(to: p(0.86, 0.86))
    swoosh.curve(to: p(0.10, 0.20), controlPoint1: p(0.80, 0.42), controlPoint2: p(0.42, 0.14))
    swoosh.curve(to: p(0.86, 0.86), controlPoint1: p(0.50, 0.26), controlPoint2: p(0.74, 0.50))
    swoosh.close()
    NSColor.white.setFill()
    swoosh.fill()
    NSGraphicsContext.restoreGraphicsState()
}

func png(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    drawIcon(CGFloat(px))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Swoosh-\(getpid()).iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! png(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try! png(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try! png(1024).write(to: URL(fileURLWithPath: (output as NSString).deletingPathExtension + "-1024.png"))

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", output]
try! task.run()
task.waitUntilExit()
try? fm.removeItem(at: iconset)
print(task.terminationStatus == 0 ? "Wrote \(output)" : "iconutil failed")
exit(task.terminationStatus)
