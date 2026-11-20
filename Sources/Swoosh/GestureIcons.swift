import AppKit
import SwooshCore

/// Where a gesture started.
enum OriginGlyph { case titlebar, dock, menubar, keyboard }

/// What the fingers did.
enum GestureGlyph: Hashable {
    case swipe(Direction)
    case pinchIn, pinchOut, doubleTap, hold
}

/// What happens.
enum ActionGlyph: Hashable {
    case layout(Layout)
    case minimize, unminimize, minimizeAll, unminimizeAll
    case close, quit, fullScreen, restore, center
    case moveScreen(Direction)
    case hide, cycle, newWindow
}

extension ActionGlyph {
    init?(_ outcome: Outcome) {
        switch outcome {
        case .none: return nil
        case .layout(let l), .layoutOnScreen(let l, _): self = .layout(l)
        case .minimize: self = .minimize
        case .restore: self = .restore
        case .moveScreen(let d): self = .moveScreen(d)
        case .minimizeAll: self = .minimizeAll
        case .unminimizeAll: self = .unminimizeAll
        case .toggleFullScreen: self = .fullScreen
        }
    }

    init?(_ action: DockAction) {
        switch action {
        case .none: return nil
        case .unminimize(let all): self = all ? .unminimizeAll : .unminimize
        case .minimize(let all): self = all ? .minimizeAll : .minimize
        case .cycle: self = .cycle
        case .quit: self = .quit
        case .newWindow: self = .newWindow
        case .hide: self = .hide
        }
    }
}

/// Swoosh's own icon set, drawn in code on a 24 × 24 grid as template images
/// so they tint correctly anywhere (HUD, settings, light and dark mode).
enum GestureIcons {
    private static var cache: [String: NSImage] = [:]

    static func origin(_ o: OriginGlyph, size: CGFloat = 18) -> NSImage {
        image("o\(o)\(size)", size) {
            switch o {
            case .titlebar:
                stroke(rounded(3, 5, 18, 14, 2.5), 1.6)
                fill(rounded(3, 15, 18, 4, 1.5))
            case .dock:
                stroke(rounded(2, 6, 20, 14, 2.5), 1.4, alpha: 0.5)
                fill(rounded(4, 3, 16, 6, 2))
                for x in [6.0, 10.5, 15.0] { fill(rounded(x, 4.4, 3, 3, 0.8), color: .white) }
            case .menubar:
                stroke(rounded(2, 4, 20, 16, 2.5), 1.6)
                fill(rounded(2, 16, 20, 4, 1.5))
            case .keyboard:
                stroke(rounded(2, 6, 20, 12, 2.5), 1.6)
                for (x, y) in [(5.0, 13.0), (9.0, 13.0), (13.0, 13.0), (17.0, 13.0), (5.0, 9.5), (17.0, 9.5)] {
                    fill(rounded(x - 1, y - 1, 2.2, 2, 0.5))
                }
                fill(rounded(8, 8.5, 8, 2, 0.8))
            }
        }
    }

    static func gesture(_ g: GestureGlyph, size: CGFloat = 18) -> NSImage {
        image("g\(g)\(size)", size) {
            switch g {
            case .swipe(let d):
                rotated(for: d) {
                    // Two fingertips with a motion arrow.
                    dot(5.5, 8.5, 2.3); dot(5.5, 15.5, 2.3)
                    line(10, 12, 19.5, 12, 2)
                    line(15.5, 8, 19.8, 12, 2); line(15.5, 16, 19.8, 12, 2)
                }
            case .pinchIn:
                dot(9.5, 14.5, 2.3); dot(14.5, 9.5, 2.3)
                arrow(from: (2.5, 21.5), to: (7, 17))
                arrow(from: (21.5, 2.5), to: (17, 7))
            case .pinchOut:
                dot(10, 14, 2.3); dot(14, 10, 2.3)
                arrow(from: (7.5, 16.5), to: (3, 21))
                arrow(from: (16.5, 7.5), to: (21, 3))
            case .doubleTap:
                dot(9, 12, 2.4); dot(15, 12, 2.4)
                stroke(NSBezierPath(ovalIn: NSRect(x: 4, y: 7, width: 16, height: 10)), 1.4)
                stroke(NSBezierPath(ovalIn: NSRect(x: 1, y: 4, width: 22, height: 16)), 1.2, alpha: 0.45)
            case .hold:
                dot(9, 12, 2.4); dot(15, 12, 2.4)
                let arc = NSBezierPath()
                arc.appendArc(withCenter: NSPoint(x: 12, y: 12), radius: 9, startAngle: 90, endAngle: -180, clockwise: true)
                stroke(arc, 2)
                stroke(NSBezierPath(ovalIn: NSRect(x: 3, y: 3, width: 18, height: 18)), 1, alpha: 0.35)
            }
        }
    }

    static func action(_ a: ActionGlyph, size: CGFloat = 18) -> NSImage {
        image("a\(a)\(size)", size) {
            switch a {
            case .layout(let l):
                let screen = NSRect(x: 1.5, y: 4, width: 21, height: 16)
                stroke(rounded(screen.minX, screen.minY, screen.width, screen.height, 2.5), 1.5)
                let inner = screen.insetBy(dx: 2.3, dy: 2.3)
                let u = l.unit
                let r = NSRect(x: inner.minX + inner.width * u.minX,
                               y: inner.maxY - inner.height * (u.minY + u.height),
                               width: inner.width * u.width, height: inner.height * u.height)
                fill(rounded(r.minX + 0.4, r.minY + 0.4, r.width - 0.8, r.height - 0.8, 1.2))
            case .minimize, .minimizeAll:
                fill(rounded(4, 3, 16, 2.6, 1.3))
                arrow(from: (12, 21), to: (12, 8), width: 2)
                if a == .minimizeAll { line(7, 17, 12, 12.5, 1.6); line(17, 17, 12, 12.5, 1.6) }
            case .unminimize, .unminimizeAll:
                fill(rounded(4, 3, 16, 2.6, 1.3))
                arrow(from: (12, 7.5), to: (12, 21), width: 2)
                if a == .unminimizeAll { line(7, 11, 12, 15.5, 1.6); line(17, 11, 12, 15.5, 1.6) }
            case .close:
                stroke(NSBezierPath(ovalIn: NSRect(x: 2.5, y: 2.5, width: 19, height: 19)), 1.6)
                line(8, 8, 16, 16, 2); line(16, 8, 8, 16, 2)
            case .quit:
                let arc = NSBezierPath()
                arc.appendArc(withCenter: NSPoint(x: 12, y: 11), radius: 8, startAngle: 60, endAngle: 120, clockwise: true)
                stroke(arc, 2)
                line(12, 11, 12, 21, 2)
            case .fullScreen:
                stroke(rounded(2, 4, 20, 16, 2.5), 1.4, alpha: 0.5)
                arrow(from: (10.5, 10.5), to: (4.5, 16.5), width: 1.8, head: 3.5)
                arrow(from: (13.5, 13.5), to: (19.5, 7.5), width: 1.8, head: 3.5)
            case .restore, .center:
                stroke(rounded(1.5, 4, 21, 16, 2.5), 1.5)
                fill(rounded(7, 8.5, 10, 7, 1.5))
            case .moveScreen(let d):
                rotated(for: d) {
                    stroke(rounded(1.5, 7, 8, 10, 1.6), 1.4, alpha: 0.5)
                    stroke(rounded(14.5, 7, 8, 10, 1.6), 1.6)
                    arrow(from: (6, 12), to: (17.5, 12), width: 1.8, head: 3)
                }
            case .hide:
                let eye = NSBezierPath()
                eye.move(to: NSPoint(x: 2, y: 12))
                eye.curve(to: NSPoint(x: 22, y: 12), controlPoint1: NSPoint(x: 7, y: 20), controlPoint2: NSPoint(x: 17, y: 20))
                eye.curve(to: NSPoint(x: 2, y: 12), controlPoint1: NSPoint(x: 17, y: 4), controlPoint2: NSPoint(x: 7, y: 4))
                stroke(eye, 1.6)
                dot(12, 12, 3)
                line(4, 3.5, 20, 20.5, 2)
            case .cycle:
                let top = NSBezierPath()
                top.appendArc(withCenter: NSPoint(x: 12, y: 12), radius: 8, startAngle: 160, endAngle: 20, clockwise: true)
                stroke(top, 1.8)
                line(20, 12, 17.2, 15.8, 1.8); line(20, 12, 21.8, 16.2, 1.8)
                let bottom = NSBezierPath()
                bottom.appendArc(withCenter: NSPoint(x: 12, y: 12), radius: 8, startAngle: -20, endAngle: -160, clockwise: true)
                stroke(bottom, 1.8)
                line(4, 12, 6.8, 8.2, 1.8); line(4, 12, 2.2, 7.8, 1.8)
            case .newWindow:
                stroke(rounded(2.5, 4, 19, 16, 2.5), 1.5)
                fill(rounded(2.5, 16.5, 19, 3.5, 1.5))
                line(12, 7, 12, 14.5, 2); line(8.2, 10.8, 15.8, 10.8, 2)
            }
        }
    }

    // MARK: Drawing helpers (24 × 24 grid, y up)

    private static func image(_ key: String, _ size: CGFloat, _ draw: @escaping () -> Void) -> NSImage {
        if let cached = cache[key] { return cached }
        let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let scale = rect.width / 24
            NSGraphicsContext.current?.cgContext.scaleBy(x: scale, y: scale)
            NSColor.black.set()
            draw()
            return true
        }
        img.isTemplate = true
        cache[key] = img
        return img
    }

    private static func rounded(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> NSBezierPath {
        NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: r, yRadius: r)
    }

    private static func stroke(_ p: NSBezierPath, _ width: CGFloat, alpha: CGFloat = 1) {
        NSColor.black.withAlphaComponent(alpha).setStroke()
        p.lineWidth = width
        p.lineCapStyle = .round
        p.lineJoinStyle = .round
        p.stroke()
    }

    private static func fill(_ p: NSBezierPath, color: NSColor = .black) {
        if color == .white {
            // Punch a hole (template images only use alpha).
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            NSColor.black.setFill()
            p.fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
        } else {
            color.setFill()
            p.fill()
        }
    }

    private static func dot(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) {
        fill(NSBezierPath(ovalIn: NSRect(x: x - r, y: y - r, width: r * 2, height: r * 2)))
    }

    private static func line(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat, _ w: CGFloat) {
        let p = NSBezierPath()
        p.move(to: NSPoint(x: x1, y: y1))
        p.line(to: NSPoint(x: x2, y: y2))
        stroke(p, w)
    }

    private static func arrow(from a: (CGFloat, CGFloat), to b: (CGFloat, CGFloat), width: CGFloat = 1.8, head: CGFloat = 4) {
        line(a.0, a.1, b.0, b.1, width)
        let angle = atan2(b.1 - a.1, b.0 - a.0)
        for side in [CGFloat.pi * 0.78, -CGFloat.pi * 0.78] {
            line(b.0, b.1, b.0 + cos(angle + side) * head, b.1 + sin(angle + side) * head, width)
        }
    }

    /// Draws a right-pointing design rotated to face `d`.
    private static func rotated(for d: Direction, _ draw: () -> Void) {
        let angle: CGFloat
        switch d {
        case .right: angle = 0
        case .up: angle = 90
        case .left: angle = 180
        case .down: angle = 270
        }
        NSGraphicsContext.saveGraphicsState()
        let t = NSAffineTransform()
        t.translateX(by: 12, yBy: 12)
        t.rotate(byDegrees: angle)
        t.translateX(by: -12, yBy: -12)
        t.concat()
        draw()
        NSGraphicsContext.restoreGraphicsState()
    }
}
