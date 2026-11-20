import CoreGraphics

public enum Direction: String, CaseIterable, Sendable {
    case left, right, up, down

    public var isHorizontal: Bool { self == .left || self == .right }
}

/// Which finer grid vertical swipes on a third lead to.
public enum Grid: String, CaseIterable, Sendable {
    /// 3×2: thirds split into top / bottom sixths.
    case sixths
    /// 3×3: thirds split into top / middle / bottom ninths.
    case ninths
}

/// Snap positions, expressed as fractions of a screen's work area
/// (x, y measured from the top-left).
public enum Layout: Hashable, Sendable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case topLeft, topRight, bottomLeft, bottomRight
    case leftThird, centerThird, rightThird, leftTwoThirds, rightTwoThirds
    case topLeftSixth, topCenterSixth, topRightSixth
    case bottomLeftSixth, bottomCenterSixth, bottomRightSixth
    /// col and row are 0...2.
    case ninth(col: Int, row: Int)
    case maximize, almostMaximize

    public static let allCases: [Layout] = [
        .leftHalf, .rightHalf, .topHalf, .bottomHalf,
        .topLeft, .topRight, .bottomLeft, .bottomRight,
        .leftThird, .centerThird, .rightThird, .leftTwoThirds, .rightTwoThirds,
        .topLeftSixth, .topCenterSixth, .topRightSixth,
        .bottomLeftSixth, .bottomCenterSixth, .bottomRightSixth,
        .maximize, .almostMaximize,
    ] + (0..<3).flatMap { row in (0..<3).map { col in Layout.ninth(col: col, row: row) } }

    public var unit: CGRect {
        let t: CGFloat = 1.0 / 3.0
        switch self {
        case .leftHalf: return CGRect(x: 0, y: 0, width: 0.5, height: 1)
        case .rightHalf: return CGRect(x: 0.5, y: 0, width: 0.5, height: 1)
        case .topHalf: return CGRect(x: 0, y: 0, width: 1, height: 0.5)
        case .bottomHalf: return CGRect(x: 0, y: 0.5, width: 1, height: 0.5)
        case .topLeft: return CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
        case .topRight: return CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5)
        case .bottomLeft: return CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5)
        case .bottomRight: return CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
        case .leftThird: return CGRect(x: 0, y: 0, width: t, height: 1)
        case .centerThird: return CGRect(x: t, y: 0, width: t, height: 1)
        case .rightThird: return CGRect(x: 2 * t, y: 0, width: t, height: 1)
        case .leftTwoThirds: return CGRect(x: 0, y: 0, width: 2 * t, height: 1)
        case .rightTwoThirds: return CGRect(x: t, y: 0, width: 2 * t, height: 1)
        case .topLeftSixth: return CGRect(x: 0, y: 0, width: t, height: 0.5)
        case .topCenterSixth: return CGRect(x: t, y: 0, width: t, height: 0.5)
        case .topRightSixth: return CGRect(x: 2 * t, y: 0, width: t, height: 0.5)
        case .bottomLeftSixth: return CGRect(x: 0, y: 0.5, width: t, height: 0.5)
        case .bottomCenterSixth: return CGRect(x: t, y: 0.5, width: t, height: 0.5)
        case .bottomRightSixth: return CGRect(x: 2 * t, y: 0.5, width: t, height: 0.5)
        case .ninth(let c, let r): return CGRect(x: CGFloat(c) * t, y: CGFloat(r) * t, width: t, height: t)
        case .maximize: return CGRect(x: 0, y: 0, width: 1, height: 1)
        case .almostMaximize: return CGRect(x: 0.04, y: 0.04, width: 0.92, height: 0.92)
        }
    }

    /// Target frame inside `area` (top-left coordinates) with `gap` points
    /// between windows and around the edge of the area.
    public func rect(in area: CGRect, gap: CGFloat) -> CGRect {
        let u = unit
        if self == .almostMaximize {
            return CGRect(x: area.minX + area.width * u.minX, y: area.minY + area.height * u.minY,
                          width: area.width * u.width, height: area.height * u.height).integral
        }
        let g = max(0, gap)
        let usable = area.insetBy(dx: g / 2, dy: g / 2)
        let r = CGRect(x: usable.minX + usable.width * u.minX,
                       y: usable.minY + usable.height * u.minY,
                       width: usable.width * u.width,
                       height: usable.height * u.height)
        return r.insetBy(dx: g / 2, dy: g / 2).integral
    }

    public var title: String {
        switch self {
        case .leftHalf: return "Left Half"
        case .rightHalf: return "Right Half"
        case .topHalf: return "Top Half"
        case .bottomHalf: return "Bottom Half"
        case .topLeft: return "Top Left"
        case .topRight: return "Top Right"
        case .bottomLeft: return "Bottom Left"
        case .bottomRight: return "Bottom Right"
        case .leftThird: return "Left Third"
        case .centerThird: return "Center Third"
        case .rightThird: return "Right Third"
        case .leftTwoThirds: return "Left Two Thirds"
        case .rightTwoThirds: return "Right Two Thirds"
        case .topLeftSixth: return "Top Left Sixth"
        case .topCenterSixth: return "Top Center Sixth"
        case .topRightSixth: return "Top Right Sixth"
        case .bottomLeftSixth: return "Bottom Left Sixth"
        case .bottomCenterSixth: return "Bottom Center Sixth"
        case .bottomRightSixth: return "Bottom Right Sixth"
        case .ninth(let c, let r):
            let cols = ["Left", "Center", "Right"], rows = ["Top", "Middle", "Bottom"]
            return "\(rows[r]) \(cols[c]) Ninth"
        case .maximize: return "Maximize"
        case .almostMaximize: return "Almost Maximize"
        }
    }

    /// Column (0...2) of a third-wide layout, if it is one.
    var thirdColumn: Int? {
        switch self {
        case .leftThird, .topLeftSixth, .bottomLeftSixth: return 0
        case .centerThird, .topCenterSixth, .bottomCenterSixth: return 1
        case .rightThird, .topRightSixth, .bottomRightSixth: return 2
        case .ninth(let c, _): return c
        default: return nil
        }
    }

    static func third(_ col: Int) -> Layout { [.leftThird, .centerThird, .rightThird][col] }
    static func topSixth(_ col: Int) -> Layout { [.topLeftSixth, .topCenterSixth, .topRightSixth][col] }
    static func bottomSixth(_ col: Int) -> Layout { [.bottomLeftSixth, .bottomCenterSixth, .bottomRightSixth][col] }
}

/// What a gesture will do when it completes.
public enum Outcome: Equatable, Sendable {
    case none
    case layout(Layout)
    case minimize
    case restore
    case moveScreen(Direction)
    case minimizeAll
    case unminimizeAll

    public var title: String {
        switch self {
        case .none: return ""
        case .layout(let l): return l.title
        case .minimize: return "Minimize"
        case .restore: return "Restore"
        case .moveScreen(let d): return "Move to \(d.rawValue.capitalized) Screen"
        case .minimizeAll: return "Minimize All Windows"
        case .unminimizeAll: return "Restore Minimized Windows"
        }
    }
}

/// The swipe grammar: each swipe step moves a window from its current snap
/// state to a neighbouring one, so repeated swipes walk halves → thirds →
/// two-thirds, and a perpendicular swipe reaches quarters, sixths or ninths.
public enum Grammar {
    public static func next(from state: Layout?, step: Direction, grid: Grid = .sixths) -> Outcome {
        guard let state else {
            switch step {
            case .left: return .layout(.leftHalf)
            case .right: return .layout(.rightHalf)
            case .up: return .layout(.maximize)
            case .down: return .minimize
            }
        }

        switch (state, step) {
        // Halves
        case (.leftHalf, .left): return .layout(.leftThird)
        case (.leftHalf, .right): return .layout(.rightHalf)
        case (.leftHalf, .up): return .layout(.topLeft)
        case (.leftHalf, .down): return .layout(.bottomLeft)
        case (.rightHalf, .right): return .layout(.rightThird)
        case (.rightHalf, .left): return .layout(.leftHalf)
        case (.rightHalf, .up): return .layout(.topRight)
        case (.rightHalf, .down): return .layout(.bottomRight)
        case (.topHalf, .up): return .layout(.maximize)
        case (.topHalf, .down): return .layout(.bottomHalf)
        case (.topHalf, .left): return .layout(.topLeft)
        case (.topHalf, .right): return .layout(.topRight)
        case (.bottomHalf, .up): return .layout(.topHalf)
        case (.bottomHalf, .down): return .minimize
        case (.bottomHalf, .left): return .layout(.bottomLeft)
        case (.bottomHalf, .right): return .layout(.bottomRight)

        // Quarters: toward an edge the quarter touches → the half along that
        // edge; away from it → the adjacent quarter.
        case (.topLeft, .left): return .layout(.leftHalf)
        case (.topLeft, .up): return .layout(.topHalf)
        case (.topLeft, .right): return .layout(.topRight)
        case (.topLeft, .down): return .layout(.bottomLeft)
        case (.topRight, .right): return .layout(.rightHalf)
        case (.topRight, .up): return .layout(.topHalf)
        case (.topRight, .left): return .layout(.topLeft)
        case (.topRight, .down): return .layout(.bottomRight)
        case (.bottomLeft, .left): return .layout(.leftHalf)
        case (.bottomLeft, .down): return .layout(.bottomHalf)
        case (.bottomLeft, .right): return .layout(.bottomRight)
        case (.bottomLeft, .up): return .layout(.topLeft)
        case (.bottomRight, .right): return .layout(.rightHalf)
        case (.bottomRight, .down): return .layout(.bottomHalf)
        case (.bottomRight, .left): return .layout(.bottomLeft)
        case (.bottomRight, .up): return .layout(.topRight)

        // Thirds
        case (.leftThird, .left): return .layout(.leftTwoThirds)
        case (.leftThird, .right): return .layout(.centerThird)
        case (.centerThird, .left): return .layout(.leftThird)
        case (.centerThird, .right): return .layout(.rightThird)
        case (.rightThird, .right): return .layout(.rightTwoThirds)
        case (.rightThird, .left): return .layout(.centerThird)
        case (.leftThird, .up), (.centerThird, .up), (.rightThird, .up):
            let c = state.thirdColumn!
            return .layout(grid == .ninths ? .ninth(col: c, row: 0) : Layout.topSixth(c))
        case (.leftThird, .down), (.centerThird, .down), (.rightThird, .down):
            let c = state.thirdColumn!
            return .layout(grid == .ninths ? .ninth(col: c, row: 2) : Layout.bottomSixth(c))

        // Two thirds
        case (.leftTwoThirds, .left): return .layout(.leftHalf)
        case (.leftTwoThirds, .right): return .layout(.rightThird)
        case (.rightTwoThirds, .right): return .layout(.rightHalf)
        case (.rightTwoThirds, .left): return .layout(.leftThird)
        case (.leftTwoThirds, .up), (.rightTwoThirds, .up): return .layout(.maximize)
        case (.leftTwoThirds, .down), (.rightTwoThirds, .down): return .minimize

        // Sixths: vertical toward the sixth's edge → back to the third;
        // the other way → the other row; horizontal → neighbouring column.
        case (.topLeftSixth, _), (.topCenterSixth, _), (.topRightSixth, _):
            let c = state.thirdColumn!
            switch step {
            case .up: return .layout(Layout.third(c))
            case .down: return .layout(Layout.bottomSixth(c))
            case .left: return c > 0 ? .layout(Layout.topSixth(c - 1)) : .none
            case .right: return c < 2 ? .layout(Layout.topSixth(c + 1)) : .none
            }
        case (.bottomLeftSixth, _), (.bottomCenterSixth, _), (.bottomRightSixth, _):
            let c = state.thirdColumn!
            switch step {
            case .down: return .layout(Layout.third(c))
            case .up: return .layout(Layout.topSixth(c))
            case .left: return c > 0 ? .layout(Layout.bottomSixth(c - 1)) : .none
            case .right: return c < 2 ? .layout(Layout.bottomSixth(c + 1)) : .none
            }

        // Ninths: walk the 3×3 grid; pushing past the top or bottom row grows
        // back into the column's third.
        case (.ninth(let c, let r), _):
            switch step {
            case .up: return r == 0 ? .layout(Layout.third(c)) : .layout(.ninth(col: c, row: r - 1))
            case .down: return r == 2 ? .layout(Layout.third(c)) : .layout(.ninth(col: c, row: r + 1))
            case .left: return c > 0 ? .layout(.ninth(col: c - 1, row: r)) : .none
            case .right: return c < 2 ? .layout(.ninth(col: c + 1, row: r)) : .none
            }

        // Maximized: down always minimizes (it never shrinks the window first).
        case (.maximize, .up): return .layout(.almostMaximize)
        case (.almostMaximize, .up): return .layout(.maximize)
        case (.maximize, .down), (.almostMaximize, .down): return .minimize
        case (.maximize, .left), (.almostMaximize, .left): return .layout(.leftHalf)
        case (.maximize, .right), (.almostMaximize, .right): return .layout(.rightHalf)
        }
    }
}
