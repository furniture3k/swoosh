import CoreGraphics

/// Pure geometry helpers. All rects use global top-left (Quartz / AX) coordinates
/// unless stated otherwise.
public enum Geometry {
    /// Converts between Cocoa (bottom-left origin) and Quartz (top-left origin).
    /// The conversion is its own inverse.
    public static func flip(_ r: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    public static func approximatelyEqual(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 6) -> Bool {
        abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance
            && abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
    }

    /// The layout whose frame `frame` currently occupies, if any. Exact matches
    /// on the finer layouts win over coarser ones, so the order of `allCases` matters
    /// only for identical rects.
    public static func detect(frame: CGRect, area: CGRect, gap: CGFloat, tolerance: CGFloat = 6) -> Layout? {
        Layout.allCases.first { approximatelyEqual($0.rect(in: area, gap: gap), frame, tolerance: tolerance) }
    }

    /// Index of the rect holding the largest part of `rect`.
    public static func bestIndex(for rect: CGRect, in rects: [CGRect]) -> Int? {
        var best: Int?
        var bestArea: CGFloat = -1
        for (i, r) in rects.enumerated() {
            let inter = r.intersection(rect)
            let a = inter.isNull ? 0 : inter.width * inter.height
            if a > bestArea { bestArea = a; best = i }
        }
        if bestArea <= 0, !rects.isEmpty {
            // Off-screen: fall back to the nearest centre.
            let c = CGPoint(x: rect.midX, y: rect.midY)
            return rects.indices.min { distance(c, center(rects[$0])) < distance(c, center(rects[$1])) }
        }
        return best
    }

    /// Nearest rect whose centre lies in `direction` from `from`.
    public static func neighbor(of from: CGRect, in candidates: [CGRect], _ direction: Direction) -> Int? {
        let c = center(from)
        return candidates.indices
            .filter { candidates[$0] != from }
            .filter { i in
                let dx = candidates[i].midX - c.x, dy = candidates[i].midY - c.y
                switch direction {
                case .left: return dx < 0 && abs(dx) >= abs(dy)
                case .right: return dx > 0 && abs(dx) >= abs(dy)
                case .up: return dy < 0 && abs(dy) > abs(dx)
                case .down: return dy > 0 && abs(dy) > abs(dx)
                }
            }
            .min { distance(c, center(candidates[$0])) < distance(c, center(candidates[$1])) }
    }

    /// Maps a frame proportionally from one area to another, kept inside `b`.
    public static func map(_ rect: CGRect, from a: CGRect, to b: CGRect) -> CGRect {
        guard a.width > 0, a.height > 0 else { return centered(rect.size, in: b) }
        let sx = b.width / a.width, sy = b.height / a.height
        var r = CGRect(x: b.minX + (rect.minX - a.minX) * sx,
                       y: b.minY + (rect.minY - a.minY) * sy,
                       width: min(rect.width * sx, b.width),
                       height: min(rect.height * sy, b.height))
        r = clamp(CGRect(x: r.minX.rounded(), y: r.minY.rounded(), width: r.width.rounded(), height: r.height.rounded()), to: b)
        return r
    }

    public static func centered(_ size: CGSize, in area: CGRect) -> CGRect {
        let w = min(size.width, area.width), h = min(size.height, area.height)
        // Round the origin only; `.integral` would grow the size by a point.
        return CGRect(x: (area.midX - w / 2).rounded(), y: (area.midY - h / 2).rounded(), width: w.rounded(), height: h.rounded())
    }

    /// Moves (and if needed shrinks) `r` so it lies within `area`.
    public static func clamp(_ r: CGRect, to area: CGRect) -> CGRect {
        var out = r
        out.size.width = min(out.width, area.width)
        out.size.height = min(out.height, area.height)
        out.origin.x = max(area.minX, min(out.minX, area.maxX - out.width))
        out.origin.y = max(area.minY, min(out.minY, area.maxY - out.height))
        return out
    }

    /// Frame for "Restore": the saved pre-snap frame brought onto `area`, or a
    /// comfortable centred default.
    public static func restoreFrame(saved: CGRect?, area: CGRect) -> CGRect {
        guard let saved, saved.width > 0, saved.height > 0 else {
            return centered(CGSize(width: area.width * 0.6, height: area.height * 0.7), in: area)
        }
        let titleProbe = CGPoint(x: saved.midX, y: saved.minY + 10)
        if area.contains(titleProbe) { return clamp(saved, to: area) }
        return centered(saved.size, in: area)
    }

    /// Frame for "Drag to Unsnap": the pre-snap size, placed so the point the
    /// user grabbed stays under the cursor (same relative position across the
    /// title bar), with the top edge where it is now. Kept on screen.
    /// - Parameters:
    ///   - grabRatio: where along the window's width the drag started (0...1).
    public static func dragRestoreFrame(saved: CGSize, current: CGRect, cursor: CGPoint,
                                        grabRatio: CGFloat, area: CGRect) -> CGRect {
        let w = min(saved.width, area.width), h = min(saved.height, area.height)
        let ratio = max(0, min(1, grabRatio))
        var x = cursor.x - w * ratio
        // Keep a margin of title bar on both sides of the cursor.
        let margin = min(24, w / 4)
        x = min(max(x, cursor.x - w + margin), cursor.x - margin)
        // Don't push the window off the left / right of the screen it is on.
        x = min(max(x, area.minX - w + 60), area.maxX - 60)
        return CGRect(x: x.rounded(), y: current.minY.rounded(), width: w.rounded(), height: h.rounded())
    }

    /// Whether `point` could be on the title bar of a window snapped inside
    /// `area`. Snapped windows' top edges only sit on a few rows (top, a third,
    /// half, two thirds, the almost-maximize inset), so most clicks can be
    /// ruled out with arithmetic alone, before any Accessibility request.
    public static func couldBeSnappedTitleBar(_ point: CGPoint, area: CGRect, gap: CGFloat, zone: CGFloat) -> Bool {
        guard point.x >= area.minX, point.x <= area.maxX else { return false }
        return snappedRowTops(area: area, gap: gap).contains { top in point.y >= top - 2 && point.y <= top + zone }
    }

    static func snappedRowTops(area: CGRect, gap: CGFloat) -> Set<CGFloat> {
        Set(Layout.allCases.map { $0.rect(in: area, gap: gap).minY })
    }

    /// Shrunken preview used for "Minimize": a small card near the bottom centre.
    public static func minimizePreview(for frame: CGRect, in area: CGRect) -> CGRect {
        let w = min(frame.width, area.width) * 0.25, h = min(frame.height, area.height) * 0.25
        return CGRect(x: area.midX - w / 2, y: area.maxY - h - 12, width: w, height: h).integral
    }

    /// Work area after reserving the Stage Manager strip on the left.
    public static func workArea(visible: CGRect, stageManagerInset: CGFloat) -> CGRect {
        let inset = max(0, min(stageManagerInset, visible.width / 3))
        return CGRect(x: visible.minX + inset, y: visible.minY, width: visible.width - inset, height: visible.height)
    }

    /// The menu bar strip of a screen: between the top of the full frame and
    /// the top of the visible frame. Empty when the menu bar auto-hides.
    public static func menuBarStrip(full: CGRect, visible: CGRect) -> CGRect {
        let h = visible.minY - full.minY
        guard h > 0 else { return .null }
        return CGRect(x: full.minX, y: full.minY, width: full.width, height: h)
    }

    static func center(_ r: CGRect) -> CGPoint { CGPoint(x: r.midX, y: r.midY) }
    static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
}
