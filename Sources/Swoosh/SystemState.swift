import AppKit
import ApplicationServices
import SwooshCore

/// Reads macOS settings that affect Swoosh.
enum SystemState {
    private static func value(_ key: String, _ domain: String) -> Any? {
        CFPreferencesCopyAppValue(key as CFString, domain as CFString)
    }

    private static func bool(_ key: String, _ domain: String, default def: Bool) -> Bool {
        guard let v = value(key, domain) else { return def }
        return (v as? NSNumber)?.boolValue ?? def
    }

    private static var stageCache: (value: Bool, at: TimeInterval) = (false, -.infinity)

    /// Stage Manager is on and its recent-apps strip is shown. Re-read from
    /// disk at most every few seconds; it is consulted on every gesture.
    static var stageManagerStripVisible: Bool {
        let now = ProcessInfo.processInfo.systemUptime
        if now - stageCache.at > 5 {
            CFPreferencesAppSynchronize("com.apple.WindowManager" as CFString)
            stageCache = (bool("GloballyEnabled", "com.apple.WindowManager", default: false)
                && !bool("AutoHide", "com.apple.WindowManager", default: false), now)
        }
        return stageCache.value
    }

    /// macOS 15+ "Tiled windows have margins" setting.
    static var tiledWindowMarginsEnabled: Bool {
        bool("EnableTiledWindowMargins", "com.apple.WindowManager", default: true)
    }

    private static let trackpadDomains = [
        "com.apple.AppleMultitouchTrackpad",
        "com.apple.driver.AppleBluetoothMultitouch.trackpad",
    ]

    static func trackpadSetting(_ req: TrackpadRequirement) -> Bool {
        let domains: [[String: Any]?] = trackpadDomains.map { domain in
            CFPreferencesAppSynchronize(domain as CFString)
            return value(req.rawValue, domain).map { [req.rawValue: $0] }
        }
        return req.isEnabled(in: domains)
    }

    static var accessibilityGranted: Bool { AXIsProcessTrusted() }

    static func openTrackpadSettings() {
        open("x-apple.systempreferences:com.apple.Trackpad-Settings.extension")
    }

    static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    private static func open(_ s: String) {
        if let url = URL(string: s) { NSWorkspace.shared.open(url) }
    }
}
