import CoreGraphics

/// Turns two-finger scroll deltas into discrete swipe steps. A session spans
/// one gesture, which can be several strokes (fingers lifted in between) made
/// in quick succession, such as a double swipe.
public struct SwipeSession {
    public enum Mode: Equatable, Sendable {
        /// Snap / minimize the window under the title bar (Swish rules, `Resolver`).
        case window
        /// Move the window to the neighbouring screen (modifier held).
        case screenMove
        /// Swipe on the menu bar: minimize / restore all windows on that screen.
        case menubar
        /// Swipe on a Dock icon.
        case dock(secondary: Bool)
    }

    public let mode: Mode
    public var context: GestureContext
    public let threshold: CGFloat

    /// Registered steps across all strokes, in order.
    public private(set) var steps: [Direction] = []
    public private(set) var strokes = 0

    private var accX: CGFloat = 0
    private var accY: CGFloat = 0
    private var lastStep: Direction?

    public init(mode: Mode = .window, context: GestureContext = GestureContext(), threshold: CGFloat = 45) {
        self.mode = mode
        self.context = context
        self.threshold = max(10, threshold)
        strokes = 1
    }

    /// Convenience used by tests.
    public init(origin: Layout?, grid: Grid = .halves, threshold: CGFloat = 45) {
        self.init(context: GestureContext(origin: origin, grid: grid), threshold: threshold)
    }

    /// Starts another stroke in the same gesture (fingers lifted and put back).
    public mutating func beginStroke() {
        strokes += 1
        accX = 0
        accY = 0
        lastStep = nil
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
        // Within a stroke, a long swipe in one direction counts once; turning
        // registers a new step. A new stroke may repeat the direction (double swipe).
        guard dir != lastStep else { return nil }
        lastStep = dir
        steps.append(dir)
        return dir
    }

    /// Adds a step directly (tests, keyboard).
    public mutating func step(_ dir: Direction) {
        steps.append(dir)
        lastStep = dir
    }

    public var outcome: Outcome {
        switch mode {
        case .window:
            return Resolver.resolve(steps, context)
        case .screenMove:
            return steps.last.map { .moveScreen($0) } ?? .none
        case .menubar:
            switch steps.last {
            case .down?: return .minimizeAll
            case .up?: return .unminimizeAll
            default: return .none
            }
        case .dock:
            return .none
        }
    }

    public var dockAction: DockAction {
        guard case .dock(let secondary) = mode, let last = steps.last else { return .none }
        return DockAction.swipe(last, secondary: secondary)
    }

    /// The gesture is complete once this outcome is applied (no follow-up strokes).
    public var endsOnLift: Bool {
        mode == .window && Resolver.endsGesture(outcome)
    }
}
