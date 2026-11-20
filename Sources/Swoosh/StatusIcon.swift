import AppKit

/// The menu bar glyph: a pair of googly eyes looking in different directions.
/// When Swoosh is paused they close. Drawn in code so it stays crisp.
enum StatusIcon {
    static func image(active: Bool) -> NSImage {
        let size = NSSize(width: 22, height: 16)
        let image = NSImage(size: size, flipped: false) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()
            let eyes: [(center: NSPoint, r: CGFloat, look: CGVector)] = [
                (NSPoint(x: 5.6, y: 7.6), 4.6, CGVector(dx: 0.7, dy: -0.7)),
                (NSPoint(x: 16.3, y: 8.2), 4.9, CGVector(dx: -0.4, dy: 0.9)),
            ]
            for eye in eyes {
                if active {
                    let ring = NSBezierPath(ovalIn: NSRect(x: eye.center.x - eye.r, y: eye.center.y - eye.r,
                                                           width: eye.r * 2, height: eye.r * 2))
                    ring.lineWidth = 1.4
                    ring.stroke()
                    let pr = eye.r * 0.48
                    let travel = eye.r - pr - 0.9
                    let pc = NSPoint(x: eye.center.x + eye.look.dx * travel, y: eye.center.y + eye.look.dy * travel)
                    NSBezierPath(ovalIn: NSRect(x: pc.x - pr, y: pc.y - pr, width: pr * 2, height: pr * 2)).fill()
                } else {
                    // Asleep: closed eyelids.
                    let lid = NSBezierPath()
                    lid.move(to: NSPoint(x: eye.center.x - eye.r, y: eye.center.y))
                    lid.curve(to: NSPoint(x: eye.center.x + eye.r, y: eye.center.y),
                              controlPoint1: NSPoint(x: eye.center.x - eye.r * 0.5, y: eye.center.y - eye.r * 0.75),
                              controlPoint2: NSPoint(x: eye.center.x + eye.r * 0.5, y: eye.center.y - eye.r * 0.75))
                    lid.lineWidth = 1.6
                    lid.lineCapStyle = .round
                    lid.stroke()
                }
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = active ? "Swoosh" : "Swoosh (paused)"
        return image
    }
}
