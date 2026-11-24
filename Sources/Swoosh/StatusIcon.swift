import AppKit

/// The menu bar glyph: a small window outline with two motion lines trailing
/// it. When Swoosh is paused the motion lines go and only a still window is
/// left. Thin strokes, drawn in code so it stays crisp and sits quietly among
/// the system's own menu bar icons.
enum StatusIcon {
    static func image(active: Bool) -> NSImage {
        let size = NSSize(width: 17, height: 12)
        let image = NSImage(size: size, flipped: false) { _ in
            NSColor.black.setStroke()
            let line: CGFloat = 1.2

            // The window, with a hairline title bar.
            let window = NSBezierPath(roundedRect: NSRect(x: 7.6, y: 1.6, width: 8.8, height: 8.8),
                                      xRadius: 2, yRadius: 2)
            window.lineWidth = line
            window.stroke()
            let titleBar = NSBezierPath()
            titleBar.move(to: NSPoint(x: 7.6, y: 7.9))
            titleBar.line(to: NSPoint(x: 16.4, y: 7.9))
            titleBar.lineWidth = line * 0.8
            titleBar.stroke()

            // Motion lines.
            if active {
                for (y, from) in [(CGFloat(7.4), CGFloat(2.6)), (4.6, 0.8)] {
                    let streak = NSBezierPath()
                    streak.move(to: NSPoint(x: from, y: y))
                    streak.line(to: NSPoint(x: 5.4, y: y))
                    streak.lineWidth = line
                    streak.lineCapStyle = .round
                    streak.stroke()
                }
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = active ? "Swoosh" : "Swoosh (paused)"
        return image
    }
}
