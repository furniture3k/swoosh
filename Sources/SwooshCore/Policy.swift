import CoreGraphics

/// Decides whether a gesture that starts at a point belongs to Swoosh.
public enum TitlebarPolicy {
    /// Controls that use scroll / swipe themselves, such as the volume slider
    /// in Music's toolbar or a scrollable tab strip.
    public static let blockingRoles: Set<String> = [
        "AXSlider", "AXScrollBar", "AXValueIndicator", "AXIncrementor",
        "AXLevelIndicator", "AXTextArea", "AXScrollArea",
    ]
    public static let toolbarRoles: Set<String> = ["AXToolbar", "AXTabGroup"]
    /// Only the hit element and its closest ancestors are checked for blocking
    /// roles; web-based apps nest their whole UI inside a scroll area.
    public static let blockingDepth = 3

    /// - Parameters:
    ///   - offsetY: pointer distance below the window's top edge.
    ///   - windowHeight: height of the window.
    ///   - baseHeight: the classic title bar hot-zone height.
    ///   - ancestorRoles: roles from the hit element upward, excluding the window.
    ///   - hitIsWindow: the hit element is the window itself (empty title area).
    public static func accepts(offsetY: CGFloat, windowHeight: CGFloat, baseHeight: CGFloat,
                               ancestorRoles: [String], hitIsWindow: Bool) -> Bool {
        guard offsetY >= 0, offsetY <= windowHeight else { return false }
        if ancestorRoles.prefix(blockingDepth).contains(where: blockingRoles.contains) { return false }
        if offsetY <= baseHeight { return true }
        if offsetY <= baseHeight + 60, ancestorRoles.contains(where: toolbarRoles.contains) { return true }
        if hitIsWindow, offsetY <= baseHeight + 30 { return true }
        return false
    }

    /// A chained window keeps receiving gestures only while the pointer stays
    /// near where the last gesture happened; moving away frees normal scrolling.
    public static func chainApplies(pointer: CGPoint, anchor: CGPoint, now: Double, until: Double,
                                    radius: CGFloat = 40) -> Bool {
        now < until && hypot(pointer.x - anchor.x, pointer.y - anchor.y) <= radius
    }
}

/// Global keyboard shortcut layouts (⌃⌥ + key snaps, ⌃⌥⌘ + key moves screens).
public enum HotkeyScheme: String, CaseIterable, Sendable {
    case off, arrows, wasd, ijkl

    public var title: String {
        switch self {
        case .off: return "Off"
        case .arrows: return "Arrow keys"
        case .wasd: return "W A S D"
        case .ijkl: return "I J K L"
        }
    }

    /// macOS virtual key codes (kVK_*) for each direction.
    public var keyCodes: [(code: UInt32, direction: Direction)] {
        switch self {
        case .off: return []
        case .arrows: return [(123, .left), (124, .right), (126, .up), (125, .down)]
        case .wasd: return [(0, .left), (2, .right), (13, .up), (1, .down)]
        case .ijkl: return [(38, .left), (37, .right), (34, .up), (40, .down)]
        }
    }

    public var labels: [Direction: String] {
        switch self {
        case .off: return [:]
        case .arrows: return [.left: "←", .right: "→", .up: "↑", .down: "↓"]
        case .wasd: return [.left: "A", .right: "D", .up: "W", .down: "S"]
        case .ijkl: return [.left: "J", .right: "L", .up: "I", .down: "K"]
        }
    }
}

/// Reads trackpad preference values the gestures depend on.
public enum TrackpadRequirement: String, CaseIterable, Sendable {
    /// System Settings › Trackpad › Scroll & Zoom › Zoom in or out.
    case pinch = "TrackpadPinch"
    /// System Settings › Trackpad › Scroll & Zoom › Smart zoom.
    case smartZoom = "TrackpadTwoFingerDoubleTapGesture"

    /// Enabled when any trackpad domain has it on. A missing value means the
    /// system default, which is on for both settings.
    public func isEnabled(in domains: [[String: Any]?]) -> Bool {
        let values = domains.compactMap { $0?[rawValue] }
        if values.isEmpty { return true }
        return values.contains { value in
            if let n = value as? Int { return n != 0 }
            if let b = value as? Bool { return b }
            return false
        }
    }
}
