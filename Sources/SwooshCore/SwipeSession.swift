import CoreGraphics

/// Turns a stream of two-finger scroll deltas into discrete swipe steps and
/// tracks the outcome the gesture will have when the fingers lift.
public struct SwipeSession {
    public enum Mode: Equatable, Sendable {
        /// Snap / minimize the window under the title bar.
        case window
        /// Move the window to the neighbouring screen (modifier held).
        case screenMove
        /// Swipe on the menu bar: minimize / restore all windows on that screen.
        case menubar
    }

    public let mode: Mode
    /// Snap state of the window when the gesture began (nil = unsnapped).
    public let origin: Layout?
    public let grid: Grid
    public let threshold: CGFloat

    public private(set) var state: Layout?
    public private(set) var outcome: Outcome = .none
    /// Registered steps, in order.
    public private(set) var steps: [Direction] = []

    private var accX: CGFloat = 0
    private var accY: CGFloat = 0
    private var lastStep: Direction?
    private var history: [(outcome: Outcome, state: Layout?)] = []

    public init(mode: Mode = .window, origin: Layout?, grid: Grid = .sixths, threshold: CGFloat = 45) {
        self.mode = mode
        self.origin = origin
        self.grid = grid
        self.threshold = max(10, threshold)
        self.state = origin
    }

    /// Feeds one scroll delta, normalised so +dx = fingers right and
    /// +dy = fingers down. Returns the step registered by this delta, if any.
    @discardableResult
    public mutating func feed(dx: CGFloat, dy: CGFloat) -> Direction? {
        accX += dx
        accY += dy
        guard max(abs(accX), abs(accY)) >= threshold else { return nil }
        let dir: Direction = abs(accX) > abs(accY)
            ? (accX > 0 ? .right : .left)
            : (accY > 0 ? .down : .up)
        accX = 0
        accY = 0
        // A long swipe in one direction counts once; turning registers a new step.
        guard dir != lastStep else { return nil }
        lastStep = dir
        step(dir)
        return dir
    }

    /// Applies one step directly (used by keyboard shortcuts and by `feed`).
    public mutating func step(_ dir: Direction) {
        steps.append(dir)
        switch mode {
        case .screenMove:
            outcome = .moveScreen(dir)
        case .menubar:
            if dir == .down { outcome = .minimizeAll } else if dir == .up { outcome = .unminimizeAll }
        case .window:
            windowStep(dir)
        }
    }

    private mutating func windowStep(_ dir: Direction) {
        // "Both orders work": from an unsnapped window, up-then-sideways and
        // down-then-sideways reach the quarters just like sideways-then-up/down.
        if steps.count == 2, origin == nil, dir.isHorizontal, history.count == 1 {
            let first = steps[0]
            if first == .up || first == .down {
                let quarter: Layout = first == .up
                    ? (dir == .left ? .topLeft : .topRight)
                    : (dir == .left ? .bottomLeft : .bottomRight)
                push(.layout(quarter))
                return
            }
        }

        if outcome == .minimize {
            // Swiping back up undoes a pending minimize.
            if dir == .up, let previous = history.popLast() {
                outcome = previous.outcome
                state = previous.state
            }
            return
        }

        let next = Grammar.next(from: state, step: dir, grid: grid)
        if next != .none { push(next) }
    }

    private mutating func push(_ next: Outcome) {
        history.append((outcome, state))
        outcome = next
        switch next {
        case .layout(let l): state = l
        case .restore: state = nil
        default: break
        }
    }
}
