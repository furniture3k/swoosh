import AppKit

/// The menu bar glyph, drawn in code so it stays crisp at every scale: a
/// window outline with a snapped left pane and speed lines on the right.
enum StatusIcon {
    static func image(active: Bool) -> NSImage {
        let size = NSSize(width: 20, height: 16)
        let image = NSImage(size: size, flipped: false) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()

            let frame = NSRect(x: 1.25, y: 1.75, width: 17.5, height: 12.5)
            let outline = NSBezierPath(roundedRect: frame, xRadius: 3.2, yRadius: 3.2)
            outline.lineWidth = 1.5
            outline.stroke()

            if active {
                // Filled left pane, as if a window was just snapped there.
                let pane = NSBezierPath(roundedRect: NSRect(x: 3.4, y: 3.9, width: 6.3, height: 8.2), xRadius: 1.6, yRadius: 1.6)
                pane.fill()
            } else {
                let pane = NSBezierPath(roundedRect: NSRect(x: 3.9, y: 4.4, width: 5.3, height: 7.2), xRadius: 1.2, yRadius: 1.2)
                pane.lineWidth = 1
                pane.stroke()
            }

            // Speed lines: the window is swooshing into place.
            for (y, from) in [(9.9, 12.0), (6.1, 13.7)] as [(CGFloat, CGFloat)] {
                let line = NSBezierPath()
                line.move(to: NSPoint(x: from, y: y))
                line.line(to: NSPoint(x: 16.3, y: y))
                line.lineWidth = 1.6
                line.lineCapStyle = .round
                line.stroke()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = active ? "Swoosh" : "Swoosh (paused)"
        return image
    }
}
