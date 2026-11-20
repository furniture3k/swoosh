import Foundation
import SwooshCore

/// UserDefaults-backed settings. Keys are shared with the SwiftUI settings view.
enum Prefs {
    enum Key {
        static let enabled = "enabled"
        static let sensitivity = "swipeThreshold"
        static let gap = "windowGap"
        static let matchSystemMargins = "matchSystemMargins"
        static let titlebarHeight = "titlebarHeight"
        static let haptics = "haptics"
        static let showPreview = "showPreview"
        static let chainTimeout = "chainTimeout"
        static let activateAfterSnap = "activateAfterSnap"
        static let excludedApps = "excludedApps"
        static let swooshCount = "swooshCount"
        static let grid = "grid"
        static let hotkeys = "hotkeyScheme"
        static let menubarGestures = "menubarGestures"
        static let pinchGestures = "pinchGestures"
        static let doubleTapGesture = "doubleTapGesture"
        static let stageManagerOffset = "stageManagerOffset"
        static let onboarded = "onboarded"
    }

    static let defaultExcluded = [
        "com.apple.CharacterPaletteIM",
        "com.apple.notificationcenterui",
        "com.apple.Spotlight",
        "com.apple.controlcenter",
        "com.apple.PIPAgent",
    ].joined(separator: "\n")

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Key.enabled: true,
            Key.sensitivity: 45.0,
            Key.gap: 0.0,
            Key.matchSystemMargins: false,
            Key.titlebarHeight: 40.0,
            Key.haptics: true,
            Key.showPreview: true,
            Key.chainTimeout: 1.0,
            Key.activateAfterSnap: true,
            Key.excludedApps: defaultExcluded,
            Key.swooshCount: 0,
            Key.grid: Grid.sixths.rawValue,
            Key.hotkeys: HotkeyScheme.arrows.rawValue,
            Key.menubarGestures: true,
            Key.pinchGestures: true,
            Key.doubleTapGesture: true,
            Key.stageManagerOffset: 120.0,
            Key.onboarded: false,
        ])
    }

    private static var d: UserDefaults { .standard }
    static var enabled: Bool { d.bool(forKey: Key.enabled) }
    static var sensitivity: CGFloat { CGFloat(d.double(forKey: Key.sensitivity)) }
    static var titlebarHeight: CGFloat { CGFloat(d.double(forKey: Key.titlebarHeight)) }
    static var haptics: Bool { d.bool(forKey: Key.haptics) }
    static var showPreview: Bool { d.bool(forKey: Key.showPreview) }
    static var chainTimeout: TimeInterval { d.double(forKey: Key.chainTimeout) }
    static var activateAfterSnap: Bool { d.bool(forKey: Key.activateAfterSnap) }
    static var menubarGestures: Bool { d.bool(forKey: Key.menubarGestures) }
    static var pinchGestures: Bool { d.bool(forKey: Key.pinchGestures) }
    static var doubleTapGesture: Bool { d.bool(forKey: Key.doubleTapGesture) }
    static var stageManagerOffset: CGFloat { CGFloat(d.double(forKey: Key.stageManagerOffset)) }
    static var grid: Grid { Grid(rawValue: d.string(forKey: Key.grid) ?? "") ?? .sixths }
    static var hotkeys: HotkeyScheme { HotkeyScheme(rawValue: d.string(forKey: Key.hotkeys) ?? "") ?? .off }
    static var onboarded: Bool {
        get { d.bool(forKey: Key.onboarded) }
        set { d.set(newValue, forKey: Key.onboarded) }
    }

    /// Gap between snapped windows: the custom value, or macOS's own tiling
    /// margin when "Match macOS tiling margins" is on.
    static var gap: CGFloat {
        if d.bool(forKey: Key.matchSystemMargins) { return SystemState.tiledWindowMarginsEnabled ? 8 : 0 }
        return CGFloat(d.double(forKey: Key.gap))
    }

    static var excludedApps: Set<String> {
        Set((d.string(forKey: Key.excludedApps) ?? "")
            .split(whereSeparator: { $0 == "," || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty })
    }

    static func countSwoosh() { d.set(d.integer(forKey: Key.swooshCount) + 1, forKey: Key.swooshCount) }
}
