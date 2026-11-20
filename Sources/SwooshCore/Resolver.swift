import CoreGraphics

/// Everything about the window and settings that affects what a gesture does.
public struct GestureContext: Sendable {
    /// Snap state of the window when the gesture began (nil = unsnapped).
    public var origin: Layout?
    public var grid: Grid
    /// Swipe up fills "almost" the whole desktop instead of all of it.
    public var upFillsAlmost: Bool
    /// Two fingers rested on the trackpad before the swipe started.
    public var hold: Bool
    public var isFullScreen: Bool
    /// Directions in which another screen exists.
    public var screens: Set<Direction>

    public init(origin: Layout? = nil, grid: Grid = .halves, upFillsAlmost: Bool = false,
                hold: Bool = false, isFullScreen: Bool = false, screens: Set<Direction> = []) {
        self.origin = origin
        self.grid = grid
        self.upFillsAlmost = upFillsAlmost
        self.hold = hold
        self.isFullScreen = isFullScreen
        self.screens = screens
    }
}

/// Resolves a whole title-bar gesture, i.e. every swipe made since the gesture
/// began (several strokes made in quick succession count as one gesture), into
/// what should happen. This follows Swish's documented behaviour:
///
/// * Every gesture starts fresh: a swipe up maximizes even if the window is a half.
/// * Swipe left/right: halves (2×2) or thirds (3×2, 3×3).
/// * Horizontal and vertical in one gesture, in either order: a quarter, sixth or ninth.
/// * Swipe up once: fill the desktop. Twice: top half (or the upper sixth of a third).
/// * Swipe down once: minimize. Twice: bottom half (or the lower sixth of a third).
/// * Tap and hold, then swipe up: full screen. In thirds modes, hold + sideways: middle third.
public enum Resolver {
    public static func resolve(_ steps: [Direction], _ ctx: GestureContext) -> Outcome {
        guard let last = steps.last else { return .none }

        if ctx.isFullScreen {
            // Only leaving full screen makes sense here (Swish: tap, hold, swipe down).
            return last == .down || last == .up ? .toggleFullScreen : .none
        }

        let horizontals = steps.filter(\.isHorizontal)
        let verticals = steps.filter { !$0.isHorizontal }

        // Vertical intent: the trailing run of the most recent vertical direction.
        let vDir = verticals.last
        let vCount = vDir.map { d in verticals.reversed().prefix { $0 == d }.count } ?? 0
        // Horizontal intent: last horizontal direction; both directions = middle column.
        let hDir = horizontals.last
        let hCount = hDir.map { d in horizontals.reversed().prefix { $0 == d }.count } ?? 0
        let bothSides = horizontals.contains(.left) && horizontals.contains(.right)

        switch (hDir, vDir) {
        case (nil, nil):
            return .none

        case (nil, let v?):
            return vertical(v, count: vCount, ctx)

        case (let h?, nil):
            return horizontal(h, count: hCount, middle: bothSides || ctx.hold, single: steps.count == 1, ctx)

        case (let h?, let v?):
            let middleRow = verticals.contains(.up) && verticals.contains(.down)
            return corner(h, v, middleRow: middleRow, middle: bothSides || ctx.hold, ctx)
        }
    }

    /// Whether another stroke could still change the outcome, so the gesture
    /// should wait briefly before doing something irreversible (minimizing).
    public static func waitsForFollowUp(_ steps: [Direction], _ ctx: GestureContext) -> Bool {
        resolve(steps, ctx) == .minimize
    }

    // MARK: Pieces

    private static func vertical(_ v: Direction, count: Int, _ ctx: GestureContext) -> Outcome {
        let column = ctx.origin?.thirdColumn
        if v == .up {
            if count == 1 {
                if ctx.hold { return .toggleFullScreen }
                return .layout(ctx.upFillsAlmost ? .almostMaximize : .maximize)
            }
            if ctx.grid != .halves, let c = column { return .layout(Layout.topSixth(c)) }
            return .layout(.topHalf)
        } else {
            if count == 1 { return .minimize }
            if ctx.grid != .halves, let c = column { return .layout(Layout.bottomSixth(c)) }
            return .layout(.bottomHalf)
        }
    }

    private static func horizontal(_ h: Direction, count: Int, middle: Bool, single: Bool, _ ctx: GestureContext) -> Outcome {
        let left = h == .left
        switch ctx.grid {
        case .halves:
            let half: Layout = left ? .leftHalf : .rightHalf
            // Already in that half: carry on to the next screen in that direction.
            if single, ctx.origin == half, ctx.screens.contains(h) {
                return .layoutOnScreen(left ? .rightHalf : .leftHalf, h)
            }
            return .layout(half)

        case .thirds, .ninths:
            if middle { return .layout(.centerThird) }
            let third: Layout = left ? .leftThird : .rightThird
            let twoThirds: Layout = left ? .leftTwoThirds : .rightTwoThirds
            if count >= 2 { return .layout(twoThirds) }
            // A fresh swipe toggles between the third and two thirds on that side.
            if single, ctx.origin == third { return .layout(twoThirds) }
            return .layout(third)
        }
    }

    private static func corner(_ h: Direction, _ v: Direction, middleRow: Bool, middle: Bool, _ ctx: GestureContext) -> Outcome {
        let left = h == .left, top = v == .up
        switch ctx.grid {
        case .halves:
            return .layout(top ? (left ? .topLeft : .topRight) : (left ? .bottomLeft : .bottomRight))
        case .thirds:
            let c = middle ? 1 : (left ? 0 : 2)
            return .layout(top ? Layout.topSixth(c) : Layout.bottomSixth(c))
        case .ninths:
            let c = middle ? 1 : (left ? 0 : 2)
            // One vertical swipe: top / bottom row. Up and down in the same
            // gesture: the middle row.
            return .layout(.ninth(col: c, row: middleRow ? 1 : (top ? 0 : 2)))
        }
    }
}

/// What a swipe on a Dock icon does (Swish's Dock gestures).
public enum DockAction: Equatable, Sendable {
    case none
    /// Restore the last minimized window (all with the secondary modifier) and chain it.
    case unminimize(all: Bool)
    /// Minimize the frontmost window (all with the secondary modifier).
    case minimize(all: Bool)
    /// Activate the next / previous window of the app and chain it.
    case cycle(forward: Bool)
    case quit
    case newWindow
    case hide(others: Bool)

    public static func swipe(_ d: Direction, secondary: Bool) -> DockAction {
        switch d {
        case .up: return .unminimize(all: secondary)
        case .down: return .minimize(all: secondary)
        case .right: return .cycle(forward: true)
        case .left: return .cycle(forward: false)
        }
    }

    public var title: String {
        switch self {
        case .none: return ""
        case .unminimize(let all): return all ? "Restore All Windows" : "Restore Window"
        case .minimize(let all): return all ? "Minimize All Windows" : "Minimize Window"
        case .cycle(let forward): return forward ? "Next Window" : "Previous Window"
        case .quit: return "Quit App"
        case .newWindow: return "New Window"
        case .hide(let others): return others ? "Hide Other Apps" : "Hide App"
        }
    }
}
