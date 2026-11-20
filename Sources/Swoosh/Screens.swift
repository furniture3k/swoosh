import AppKit

/// Converts between Cocoa (bottom-left origin) and Quartz/AX (top-left origin)
/// global coordinates, and finds screens.
enum Screens {
    static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    /// The conversion is its own inverse.
    static func flip(_ r: CGRect) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    static func visibleArea(_ screen: NSScreen) -> CGRect { flip(screen.visibleFrame) }
    static func fullArea(_ screen: NSScreen) -> CGRect { flip(screen.frame) }

    /// Screen that holds the largest part of `rect` (Quartz coordinates).
    static func screen(for rect: CGRect) -> NSScreen {
        var best: NSScreen = NSScreen.main ?? NSScreen.screens[0]
        var bestArea: CGFloat = -1
        for s in NSScreen.screens {
            let i = fullArea(s).intersection(rect)
            let a = i.isNull ? 0 : i.width * i.height
            if a > bestArea { bestArea = a; best = s }
        }
        return best
    }

    /// Nearest screen whose centre lies in `direction` from `screen`.
    static func neighbor(of screen: NSScreen, _ direction: Direction) -> NSScreen? {
        let from = fullArea(screen)
        let c = CGPoint(x: from.midX, y: from.midY)
        return NSScreen.screens
            .filter { $0 != screen }
            .map { (s: $0, r: fullArea($0)) }
            .filter { item in
                let dx = item.r.midX - c.x, dy = item.r.midY - c.y
                switch direction {
                case .left: return dx < 0 && abs(dx) >= abs(dy)
                case .right: return dx > 0 && abs(dx) >= abs(dy)
                case .up: return dy < 0 && abs(dy) > abs(dx)
                case .down: return dy > 0 && abs(dy) > abs(dx)
                }
            }
            .min { hypot($0.r.midX - c.x, $0.r.midY - c.y) < hypot($1.r.midX - c.x, $1.r.midY - c.y) }?
            .s
    }

    /// Maps a frame proportionally from one visible area to another.
    static func map(_ rect: CGRect, from a: CGRect, to b: CGRect) -> CGRect {
        let sx = b.width / a.width, sy = b.height / a.height
        var r = CGRect(x: b.minX + (rect.minX - a.minX) * sx,
                       y: b.minY + (rect.minY - a.minY) * sy,
                       width: min(rect.width * sx, b.width),
                       height: min(rect.height * sy, b.height))
        r.origin.x = max(b.minX, min(r.minX, b.maxX - r.width))
        r.origin.y = max(b.minY, min(r.minY, b.maxY - r.height))
        return r.integral
    }
}
