import AppKit
import ApplicationServices
import SwiftUI
import SwooshCore

/// The always-running agent: event tap, hotkeys, menu bar item. It never builds
/// any SwiftUI; Settings runs in a separate short-lived process (see
/// `SettingsAppDelegate`) so the agent's memory stays small.
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let wm = WindowManager()
    private lazy var engine = GestureEngine(windowManager: wm)
    private lazy var hotkeys = Hotkeys(engine: engine)
    private var statusItem: NSStatusItem!
    private var settingsProcess: NSRunningApplication?
    private var permissionTimer: Timer?
    private var lastHotkeyScheme: HotkeyScheme?
    private var visibilityObservation: NSKeyValueObservation?

    func applicationDidFinishLaunching(_ note: Notification) {
        Prefs.registerDefaults()
        NSApp.setActivationPolicy(.accessory)
        setUpStatusItem()
        applyHotkeys()

        NotificationCenter.default.addObserver(self, selector: #selector(defaultsChanged),
                                               name: UserDefaults.didChangeNotification, object: nil)
        // Changes made in the Settings process.
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(settingsProcessChanged),
                                                            name: Prefs.changedNotification, object: nil)

        if AXIsProcessTrusted() {
            engine.start()
        } else {
            promptForAccessibility()
        }
        // Watch for the permission being granted or revoked while running. macOS
        // posts this notification when Accessibility access changes; a slow,
        // coalesced timer is only a fallback (fast while access is missing).
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(accessibilityChanged), name: NSNotification.Name("com.apple.accessibility.api"), object: nil)
        schedulePermissionTimer()

        if let i = CommandLine.arguments.firstIndex(of: "--memory-test"), i + 1 < CommandLine.arguments.count {
            runMemoryTest(output: CommandLine.arguments[i + 1])
            return
        }

        if !Prefs.onboarded {
            Prefs.onboarded = true
            openSettings(tab: .setup)
        }
    }

    /// Physical memory footprint, as reported by `footprint` / Activity Monitor.
    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
    }

    /// `--memory-test <file>`: the agent's footprint while idle, while the
    /// Settings process is open, and after it has quit.
    private func runMemoryTest(output: String) {
        var log = String(format: "agent idle %.1f MB\n", AppDelegate.footprintMB())
        openSettings(tab: .gestures)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            log += String(format: "agent while settings open %.1f MB\n", AppDelegate.footprintMB())
            if let pid = self.settingsProcess?.processIdentifier {
                var info = rusage_info_current()
                let ok = withUnsafeMutablePointer(to: &info) {
                    $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, $0) }
                }
                if ok == 0 { log += String(format: "settings process %.1f MB\n", Double(info.ri_phys_footprint) / 1_048_576) }
            }
            self.settingsProcess?.terminate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                log += String(format: "agent after settings closed %.1f MB\n", AppDelegate.footprintMB())
                log += "settings process exited: \(self.settingsProcess?.isTerminated ?? true)\n"
                try? log.write(toFile: output, atomically: true, encoding: .utf8)
                exit(0)
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Opening the app again (Finder, Spotlight) shows Settings, since there is no Dock icon.
        openSettings(tab: .general)
        return false
    }

    @objc private func settingsProcessChanged() {
        CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication)
        defaultsChanged()
    }

    private func checkPermission() {
        let trusted = AXIsProcessTrusted()
        if trusted, !engine.isRunning { engine.start() }
        if !trusted, engine.isRunning { engine.stop() }
        updateIcon()
        if trusted != lastTrusted { lastTrusted = trusted; schedulePermissionTimer() }
    }

    private var lastTrusted = AXIsProcessTrusted()

    private func schedulePermissionTimer() {
        permissionTimer?.invalidate()
        let interval: TimeInterval = AXIsProcessTrusted() ? 30 : 2
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.checkPermission() }
        timer.tolerance = interval / 2
        RunLoop.main.add(timer, forMode: .common)
        permissionTimer = timer
    }

    @objc private func accessibilityChanged() {
        // The permission database updates just after the notification.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.checkPermission() }
    }

    private func promptForAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    @objc private func defaultsChanged() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.updateIcon()
            self.applyHotkeys()
            if self.statusItem.isVisible != Prefs.showMenuBarIcon { self.statusItem.isVisible = Prefs.showMenuBarIcon }
        }
    }

    private func applyHotkeys() {
        let scheme = Prefs.hotkeys
        guard scheme != lastHotkeyScheme else { return }
        lastHotkeyScheme = scheme
        hotkeys.apply(scheme)
    }

    // MARK: Menu bar

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.behavior = .removalAllowed
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        statusItem.isVisible = Prefs.showMenuBarIcon
        // ⌘-dragging the icon out of the menu bar also hides it; remember that.
        visibilityObservation = statusItem.observe(\.isVisible, options: [.new]) { item, _ in
            if Prefs.showMenuBarIcon != item.isVisible { Prefs.showMenuBarIcon = item.isVisible }
        }
        updateIcon()
    }

    private var lastIconState: Bool?

    private func updateIcon() {
        let active = Prefs.enabled && AXIsProcessTrusted()
        guard active != lastIconState else { return }
        lastIconState = active
        statusItem.button?.image = StatusIcon.image(active: active)
        statusItem.button?.toolTip = active ? "Swoosh" : (AXIsProcessTrusted() ? "Swoosh (paused)" : "Swoosh needs Accessibility access")
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let trusted = AXIsProcessTrusted()

        let header = NSMenuItem(title: trusted ? (Prefs.enabled ? "Swoosh is on" : "Swoosh is paused") : "Swoosh needs Accessibility access",
                                action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        if !trusted {
            let grant = NSMenuItem(title: "Grant Access…", action: #selector(openAccessibility), keyEquivalent: "")
            grant.target = self
            grant.image = NSImage(systemSymbolName: "lock.open", accessibilityDescription: nil)
            menu.addItem(grant)
        } else {
            let toggle = NSMenuItem(title: Prefs.enabled ? "Pause Gestures" : "Resume Gestures",
                                    action: #selector(toggleEnabled), keyEquivalent: "")
            toggle.target = self
            toggle.image = NSImage(systemSymbolName: Prefs.enabled ? "pause.circle" : "play.circle", accessibilityDescription: nil)
            menu.addItem(toggle)
        }
        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettingsFromMenu), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let guide = NSMenuItem(title: "Gesture Guide", action: #selector(openGuide), keyEquivalent: "")
        guide.target = self
        menu.addItem(guide)
        let hide = NSMenuItem(title: "Hide Menu Bar Icon", action: #selector(hideIcon), keyEquivalent: "")
        hide.target = self
        hide.toolTip = "Open Swoosh again from Applications or Spotlight to get to Settings."
        menu.addItem(hide)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Swoosh", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    @objc private func hideIcon() {
        let alert = NSAlert()
        alert.messageText = "Hide the Swoosh menu bar icon?"
        alert.informativeText = "Swoosh keeps running. To get back to Settings, open Swoosh again from Applications or Spotlight, where you can turn the icon back on."
        alert.addButton(withTitle: "Hide Icon")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Prefs.showMenuBarIcon = false
    }

    @objc private func toggleEnabled() {
        UserDefaults.standard.set(!Prefs.enabled, forKey: Prefs.Key.enabled)
        updateIcon()
    }

    @objc private func openAccessibility() {
        promptForAccessibility()
        SystemState.openAccessibilitySettings()
    }

    @objc private func openSettingsFromMenu() { openSettings(tab: .general) }
    @objc private func openGuide() { openSettings(tab: .gestures) }

    /// Shows Settings in its own process (one at a time).
    private func openSettings(tab: SettingsTab) {
        if let running = settingsProcess, !running.isTerminated {
            DistributedNotificationCenter.default().postNotificationName(
                Prefs.showTabNotification, object: String(tab.rawValue), userInfo: nil, deliverImmediately: true)
            running.activate()
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        config.arguments = ["--settings", String(tab.rawValue)]
        config.activates = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { [weak self] app, error in
            DispatchQueue.main.async {
                if let error { NSLog("Swoosh: couldn't open Settings: \(error.localizedDescription)") }
                self?.settingsProcess = app
            }
        }
    }
}

/// `Swoosh --settings <tab>`: a separate process that only shows the Settings
/// window and quits when it closes, giving all its memory back.
final class SettingsAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ note: Notification) {
        Prefs.registerDefaults()
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--settings"), i + 1 < args.count, let raw = Int(args[i + 1]),
           let tab = SettingsTab(rawValue: raw) {
            SettingsRouter.shared.tab = tab
        }
        NSApp.setActivationPolicy(.regular)
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 540),
                         styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        w.contentViewController = NSHostingController(rootView: SettingsView())
        w.title = "Swoosh"
        w.center()
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)

        // Tell the agent about every change so it applies immediately.
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { _ in
            DistributedNotificationCenter.default().postNotificationName(Prefs.changedNotification, object: nil,
                                                                         userInfo: nil, deliverImmediately: true)
        }
        // The agent asking to switch tabs (Settings… / Gesture Guide while open).
        DistributedNotificationCenter.default().addObserver(forName: Prefs.showTabNotification, object: nil, queue: .main) { note in
            if let raw = (note.object as? String).flatMap(Int.init), let tab = SettingsTab(rawValue: raw) {
                SettingsRouter.shared.tab = tab
            }
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        window?.makeKeyAndOrderFront(nil)
        return false
    }
}

let app = NSApplication.shared
if let i = CommandLine.arguments.firstIndex(of: "--render-settings"), i + 1 < CommandLine.arguments.count {
    Prefs.registerDefaults()
    app.setActivationPolicy(.accessory)
    SettingsRenderer.render(to: CommandLine.arguments[i + 1])
    exit(0)
}
if let i = CommandLine.arguments.firstIndex(of: "--benchmark"), i + 1 < CommandLine.arguments.count {
    // Times gesture hit-testing over a grid of points on every screen.
    Prefs.registerDefaults()
    let engine = GestureEngine(windowManager: WindowManager())
    var points: [CGPoint] = []
    for screen in NSScreen.screens {
        let r = Screens.fullArea(screen)
        for yi in 0..<24 { for xi in 0..<16 {
            points.append(CGPoint(x: r.minX + r.width * (CGFloat(xi) + 0.5) / 16,
                                  y: r.minY + r.height * (CGFloat(yi) + 0.5) / 24))
        } }
    }
    var kinds: [String: Int] = [:]
    _ = engine.debugTargetKind(at: points[0]) // warm up
    AXStats.calls = 0
    let start = DispatchTime.now().uptimeNanoseconds
    for _ in 0..<3 { for p in points { kinds[engine.debugTargetKind(at: p), default: 0] += 1 } }
    let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6
    let n = Double(points.count * 3)
    let report = String(format: "trusted=%@ samples=%d avg_ms=%.3f avg_ax_calls=%.2f targets=%@\n",
                        AXIsProcessTrusted() ? "yes" : "no", Int(n), ms / n, Double(AXStats.calls) / n, kinds.description)
    try? report.write(toFile: CommandLine.arguments[i + 1], atomically: true, encoding: .utf8)
    print(report, terminator: "")
    exit(0)
}
if CommandLine.arguments.contains("--settings") {
    let settingsDelegate = SettingsAppDelegate()
    app.delegate = settingsDelegate
    app.run()
} else {
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
