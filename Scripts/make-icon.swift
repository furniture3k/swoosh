// Renders the Swoosh app icon into an .iconset and converts it to .icns.
// Usage: swift Scripts/make-icon.swift Resources/AppIcon.icns
import AppKit

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/AppIcon.icns"

// A loving parody of a certain two-fingertip window app icon: same idea, but
// the fingertips are googly eyes and the window has opinions.
func drawIcon(_ s: CGFloat) {
    // macOS icon grid: 1024 canvas, 824 body.
    let inset = s * 100 / 1024
    let body = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let radius = body.width * 0.2245

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = s * 0.025
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.012)
    shadow.set()
    let squircle = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)
    NSColor.black.setFill()
    squircle.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    squircle.addClip()
    // Sunset background: nothing like a sensible grey.
    NSGradient(colors: [
        NSColor(srgbRed: 1.00, green: 0.78, blue: 0.30, alpha: 1),
        NSColor(srgbRed: 1.00, green: 0.47, blue: 0.36, alpha: 1),
        NSColor(srgbRed: 0.96, green: 0.30, blue: 0.55, alpha: 1),
    ])!.draw(in: body, angle: -70)
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.25), NSColor.white.withAlphaComponent(0)])!
        .draw(in: NSRect(x: body.minX, y: body.midY, width: body.width, height: body.height / 2), angle: -90)

    // The window, tilted as if it just got swooshed.
    let p = { (x: CGFloat, y: CGFloat) in NSPoint(x: body.minX + body.width * x, y: body.minY + body.height * y) }
    NSGraphicsContext.saveGraphicsState()
    let tilt = NSAffineTransform()
    tilt.translateX(by: body.midX, yBy: body.midY)
    tilt.rotate(byDegrees: 6)
    tilt.translateX(by: -body.midX, yBy: -body.midY)
    tilt.concat()

    let card = NSRect(x: body.minX + body.width * 0.13, y: body.minY + body.height * 0.17,
                      width: body.width * 0.74, height: body.height * 0.64)
    let cardRadius = card.width * 0.1
    NSGraphicsContext.saveGraphicsState()
    let cardShadow = NSShadow()
    cardShadow.shadowColor = NSColor(srgbRed: 0.45, green: 0.08, blue: 0.2, alpha: 0.45)
    cardShadow.shadowBlurRadius = s * 0.045
    cardShadow.shadowOffset = NSSize(width: 0, height: -s * 0.02)
    cardShadow.set()
    NSColor(srgbRed: 0.99, green: 0.98, blue: 0.96, alpha: 1).setFill()
    NSBezierPath(roundedRect: card, xRadius: cardRadius, yRadius: cardRadius).fill()
    NSGraphicsContext.restoreGraphicsState()

    // Traffic lights (one of them is clearly panicking).
    let dotR = card.width * 0.035
    let dotY = card.maxY - card.height * 0.13
    for (i, color) in [NSColor(srgbRed: 1, green: 0.37, blue: 0.34, alpha: 1),
                       NSColor(srgbRed: 1, green: 0.74, blue: 0.18, alpha: 1),
                       NSColor(srgbRed: 0.16, green: 0.79, blue: 0.27, alpha: 1)].enumerated() {
        color.setFill()
        let x = card.minX + card.width * 0.1 + CGFloat(i) * dotR * 3.1
        let wobble: CGFloat = i == 1 ? dotR * 0.45 : 0
        NSBezierPath(ovalIn: NSRect(x: x - dotR, y: dotY - dotR + wobble, width: dotR * 2, height: dotR * 2)).fill()
    }

    // Googly eyes, looking in two different directions.
    func googly(center c: NSPoint, r: CGFloat, look: CGVector) {
        NSGraphicsContext.saveGraphicsState()
        let eyeShadow = NSShadow()
        eyeShadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
        eyeShadow.shadowBlurRadius = r * 0.12
        eyeShadow.shadowOffset = NSSize(width: 0, height: -r * 0.06)
        eyeShadow.set()
        let eye = NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        NSColor.white.setFill()
        eye.fill()
        NSGraphicsContext.restoreGraphicsState()
        // Plastic dome rim and inner shading.
        NSGradient(colors: [NSColor(white: 1, alpha: 0), NSColor(white: 0.82, alpha: 1)])!
            .draw(in: NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), relativeCenterPosition: NSPoint(x: -0.2, y: 0.25))
        let rim = NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        rim.lineWidth = r * 0.07
        NSColor(white: 0.25, alpha: 1).setStroke()
        rim.stroke()
        let pr = r * 0.5
        let pc = NSPoint(x: c.x + look.dx * (r - pr - r * 0.08), y: c.y + look.dy * (r - pr - r * 0.08))
        NSColor(white: 0.08, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: pc.x - pr, y: pc.y - pr, width: pr * 2, height: pr * 2)).fill()
        NSColor.white.withAlphaComponent(0.9).setFill()
        NSBezierPath(ovalIn: NSRect(x: pc.x - pr * 0.15 - pr * 0.3, y: pc.y + pr * 0.25, width: pr * 0.42, height: pr * 0.42)).fill()
    }
    let eyeR = card.width * 0.175
    googly(center: p(0.34, 0.47), r: eyeR, look: CGVector(dx: 0.75, dy: -0.66))
    googly(center: p(0.665, 0.49), r: eyeR * 1.06, look: CGVector(dx: -0.35, dy: 0.94))

    // A smug little swoosh of a smile.
    let smile = NSBezierPath()
    smile.move(to: p(0.42, 0.265))
    smile.curve(to: p(0.62, 0.255), controlPoint1: p(0.47, 0.205), controlPoint2: p(0.56, 0.2))
    smile.lineWidth = s * 0.018
    smile.lineCapStyle = .round
    NSColor(srgbRed: 0.93, green: 0.33, blue: 0.45, alpha: 1).setStroke()
    smile.stroke()

    NSGraphicsContext.restoreGraphicsState() // tilt
    NSGraphicsContext.restoreGraphicsState() // clip
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
