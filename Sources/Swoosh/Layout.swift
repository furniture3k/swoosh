import AppKit

enum Direction: String {
    case left, right, up, down
}

/// Snap positions, expressed as fractions of a screen's visible area
/// (x, y measured from the top-left).
enum Layout: String, CaseIterable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case topLeft, topRight, bottomLeft, bottomRight
    case leftThird, centerThird, rightThird, leftTwoThirds, rightTwoThirds
    case topLeftSixth, topCenterSixth, topRightSixth
    case bottomLeftSixth, bottomCenterSixth, bottomRightSixth
    case maximize, almostMaximize

    private static let t: CGFloat = 1.0 / 3.0

    var unit: CGRect {
        let t = Layout.t
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
        case .maximize: return CGRect(x: 0, y: 0, width: 1, height: 1)
        case .almostMaximize: return CGRect(x: 0.04, y: 0.04, width: 0.92, height: 0.92)
        }
    }

    /// Target frame inside `area` (global top-left coordinates) with `gap` points
    /// between windows and around the screen edge.
    func rect(in area: CGRect, gap: CGFloat) -> CGRect {
        let u = unit
        if self == .almostMaximize {
            return CGRect(x: area.minX + area.width * u.minX, y: area.minY + area.height * u.minY,
                          width: area.width * u.width, height: area.height * u.height).integral
        }
        let usable = area.insetBy(dx: gap / 2, dy: gap / 2)
        let r = CGRect(x: usable.minX + usable.width * u.minX,
                       y: usable.minY + usable.height * u.minY,
                       width: usable.width * u.width,
                       height: usable.height * u.height)
        return r.insetBy(dx: gap / 2, dy: gap / 2).integral
    }

    var title: String {
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
        case .maximize: return "Maximize"
        case .almostMaximize: return "Almost Maximize"
        }
    }
}

/// What a gesture will do when the fingers lift.
enum Outcome: Equatable {
    case none
    case layout(Layout)
    case minimize
    case restore
    case moveScreen(Direction)

    var title: String {
        switch self {
        case .none: return ""
        case .layout(let l): return l.title
        case .minimize: return "Minimize"
        case .restore: return "Restore"
        case .moveScreen(let d): return "Move to \(d.rawValue.capitalized) Screen"
        }
    }
}

/// The swipe grammar: each swipe step moves the window from its current snap
/// state to a neighbouring one, so repeated swipes walk through halves → thirds →
/// two-thirds and halves + perpendicular swipes reach quarters and sixths.
enum Grammar {
    static func next(from state: Layout?, step: Direction) -> Outcome {
        switch (state, step) {
        // Unsnapped
        case (nil, .left): return .layout(.leftHalf)
        case (nil, .right): return .layout(.rightHalf)
        case (nil, .up): return .layout(.maximize)
        case (nil, .down): return .minimize

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

        // Quarters: swiping toward an edge the quarter already touches expands it
        // to the half along that edge; swiping away moves to the adjacent quarter.
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
        case (.leftThird, .up): return .layout(.topLeftSixth)
        case (.leftThird, .down): return .layout(.bottomLeftSixth)
        case (.centerThird, .left): return .layout(.leftThird)
        case (.centerThird, .right): return .layout(.rightThird)
        case (.centerThird, .up): return .layout(.topCenterSixth)
        case (.centerThird, .down): return .layout(.bottomCenterSixth)
        case (.rightThird, .right): return .layout(.rightTwoThirds)
        case (.rightThird, .left): return .layout(.centerThird)
        case (.rightThird, .up): return .layout(.topRightSixth)
        case (.rightThird, .down): return .layout(.bottomRightSixth)
        case (.leftTwoThirds, .left): return .layout(.leftHalf)
        case (.leftTwoThirds, .right): return .layout(.rightThird)
        case (.rightTwoThirds, .right): return .layout(.rightHalf)
        case (.rightTwoThirds, .left): return .layout(.leftThird)
        case (.leftTwoThirds, .up), (.rightTwoThirds, .up): return .layout(.maximize)
        case (.leftTwoThirds, .down), (.rightTwoThirds, .down): return .minimize

        // Sixths
        case (.topLeftSixth, .up): return .layout(.leftThird)
        case (.topCenterSixth, .up): return .layout(.centerThird)
        case (.topRightSixth, .up): return .layout(.rightThird)
        case (.bottomLeftSixth, .down): return .layout(.leftThird)
        case (.bottomCenterSixth, .down): return .layout(.centerThird)
        case (.bottomRightSixth, .down): return .layout(.rightThird)
        case (.topLeftSixth, .down): return .layout(.bottomLeftSixth)
        case (.topCenterSixth, .down): return .layout(.bottomCenterSixth)
        case (.topRightSixth, .down): return .layout(.bottomRightSixth)
        case (.bottomLeftSixth, .up): return .layout(.topLeftSixth)
        case (.bottomCenterSixth, .up): return .layout(.topCenterSixth)
        case (.bottomRightSixth, .up): return .layout(.topRightSixth)
        case (.topLeftSixth, .right): return .layout(.topCenterSixth)
        case (.topCenterSixth, .left): return .layout(.topLeftSixth)
        case (.topCenterSixth, .right): return .layout(.topRightSixth)
        case (.topRightSixth, .left): return .layout(.topCenterSixth)
        case (.bottomLeftSixth, .right): return .layout(.bottomCenterSixth)
        case (.bottomCenterSixth, .left): return .layout(.bottomLeftSixth)
        case (.bottomCenterSixth, .right): return .layout(.bottomRightSixth)
        case (.bottomRightSixth, .left): return .layout(.bottomCenterSixth)
        case (.topLeftSixth, .left), (.bottomLeftSixth, .left),
             (.topRightSixth, .right), (.bottomRightSixth, .right): return .none

        // Maximized
        case (.maximize, .up): return .layout(.almostMaximize)
        case (.almostMaximize, .up): return .layout(.maximize)
        case (.maximize, .down), (.almostMaximize, .down): return .restore
        case (.maximize, .left), (.almostMaximize, .left): return .layout(.leftHalf)
        case (.maximize, .right), (.almostMaximize, .right): return .layout(.rightHalf)
        }
    }
}
