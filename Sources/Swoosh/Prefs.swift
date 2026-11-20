import Foundation

/// UserDefaults-backed settings. Keys are shared with the SwiftUI settings view.
enum Prefs {
    enum Key {
        static let enabled = "enabled"
        static let sensitivity = "swipeThreshold"
        static let gap = "windowGap"
        static let titlebarHeight = "titlebarHeight"
        static let haptics = "haptics"
        static let showPreview = "showPreview"
        static let chainTimeout = "chainTimeout"
        static let activateAfterSnap = "activateAfterSnap"
        static let excludedApps = "excludedApps"
        static let swooshCount = "swooshCount"
    }

    static let defaultExcluded = [
        "com.apple.CharacterPaletteIM",
        "com.apple.notificationcenterui",
        "com.apple.Spotlight",
        "com.apple.controlcenter",
        "com.apple.PIPAgent",
    ].joined(separator: ", ")

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Key.enabled: true,
            Key.sensitivity: 45.0,
            Key.gap: 0.0,
            Key.titlebarHeight: 40.0,
            Key.haptics: true,
            Key.showPreview: true,
            Key.chainTimeout: 1.0,
            Key.activateAfterSnap: true,
            Key.excludedApps: defaultExcluded,
            Key.swooshCount: 0,
        ])
    }

    private static var d: UserDefaults { .standard }
    static var enabled: Bool { d.bool(forKey: Key.enabled) }
    static var sensitivity: CGFloat { CGFloat(d.double(forKey: Key.sensitivity)) }
    static var gap: CGFloat { CGFloat(d.double(forKey: Key.gap)) }
    static var titlebarHeight: CGFloat { CGFloat(d.double(forKey: Key.titlebarHeight)) }
    static var haptics: Bool { d.bool(forKey: Key.haptics) }
    static var showPreview: Bool { d.bool(forKey: Key.showPreview) }
    static var chainTimeout: TimeInterval { d.double(forKey: Key.chainTimeout) }
    static var activateAfterSnap: Bool { d.bool(forKey: Key.activateAfterSnap) }
    static var excludedApps: Set<String> {
        Set((d.string(forKey: Key.excludedApps) ?? "")
            .split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty })
    }
    static func countSwoosh() { d.set(d.integer(forKey: Key.swooshCount) + 1, forKey: Key.swooshCount) }
}
