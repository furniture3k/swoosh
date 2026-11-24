import AppKit
import ApplicationServices
import SwiftUI
import SwooshCore

/// The always-running agent: event tap, hotkeys, menu bar item, and the
/// Settings window (built only when opened, released when closed).
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private let wm = WindowManager()
    private lazy var engine = GestureEngine(windowManager: wm)
    private lazy var hotkeys = Hotkeys(engine: engine)
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
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

        engine.onPermissionLost = { [weak self] in self?.checkPermission() }
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

    /// `--memory-test <file>`: the footprint while idle, while Settings is
    /// open, and after it has closed.
    private func runMemoryTest(output: String) {
        var log = String(format: "idle %.1f MB\n", AppDelegate.footprintMB())
        openSettings(tab: .gestures)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            log += String(format: "settings open %.1f MB\n", AppDelegate.footprintMB())
            self.settingsWindow?.close()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                log += String(format: "settings closed %.1f MB\n", AppDelegate.footprintMB())
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

    private func checkPermission() {
        let trusted = AXIsProcessTrusted()
        if trusted, !engine.isRunning {
            engine.stop()   // drop a tap the system disabled, then make a fresh one
            engine.start()
        }
        // Remove the tap the moment access is gone, even if it is already
        // disabled: an active tap without permission can freeze input.
        if !trusted, engine.hasTap { engine.stop() }
        updateIcon()
        if trusted != lastTrusted { lastTrusted = trusted; schedulePermissionTimer() }
    }

    private var lastTrusted = AXIsProcessTrusted()

    private func schedulePermissionTimer() {
        permissionTimer?.invalidate()
        // Fallback for when the change notification is missed. Short enough that
        // a revoked permission is noticed quickly; coalesced to save power.
        let interval: TimeInterval = AXIsProcessTrusted() ? 3 : 2
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.checkPermission() }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        permissionTimer = timer
    }

    @objc private func accessibilityChanged() {
        // The permission database can update a moment after the notification,
        // so check right away and then a few more times.
        for delay in [0.0, 0.15, 0.4, 0.8, 1.5, 3.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.checkPermission() }
        }
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

    /// Shows the Settings window, in this process, so there is only ever one
    /// Swoosh running. The Dock icon appears only while it is open.
    private func openSettings(tab: SettingsTab) {
        SettingsRouter.shared.tab = tab
        if settingsWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 540),
                             styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            w.contentViewController = NSHostingController(rootView: SettingsView())
            w.title = "Swoosh"
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            settingsWindow = w
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ note: Notification) {
        guard (note.object as? NSWindow) === settingsWindow else { return }
        // Drop the SwiftUI views and go back to being a menu bar agent.
        DispatchQueue.main.async { [weak self] in
            self?.settingsWindow?.contentViewController = nil
            self?.settingsWindow = nil
            NSApp.setActivationPolicy(.accessory)
        }
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
    let scrollCalls = Double(AXStats.calls)
    // Mouse-down cost for drag to unsnap (runs on every click).
    let wmClick = WindowManager()
    AXStats.calls = 0
    var hits = 0
    let clickStart = DispatchTime.now().uptimeNanoseconds
    for _ in 0..<3 { for p in points where wmClick.dragUnsnapCandidate(at: p) != nil { hits += 1 } }
    let clickMs = Double(DispatchTime.now().uptimeNanoseconds - clickStart) / 1e6
    let clickCalls = Double(AXStats.calls) / n
    let report = String(format: "trusted=%@ samples=%d scroll_avg_ms=%.3f scroll_ax_calls=%.2f targets=%@ click_avg_ms=%.3f click_ax_calls=%.2f click_hits=%d\n",
                        AXIsProcessTrusted() ? "yes" : "no", Int(n), ms / n, Double(AXStats.calls == 0 ? 0 : 0) + scrollCalls / n,
                        kinds.description, clickMs / n, clickCalls, hits)
    try? report.write(toFile: CommandLine.arguments[i + 1], atomically: true, encoding: .utf8)
    print(report, terminator: "")
    exit(0)
}
if let i = CommandLine.arguments.firstIndex(of: "--probe"), i + 2 < CommandLine.arguments.count {
    // Read-only: what Swoosh sees along an app's title bar. --probe <bundle id> <out>
    Prefs.registerDefaults()
    let bundle = CommandLine.arguments[i + 1], out = CommandLine.arguments[i + 2]
    let wm = WindowManager()
    var log = "trusted=\(AXIsProcessTrusted())\n"
    guard let target = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first else {
        try? "not running\n".write(toFile: out, atomically: true, encoding: .utf8); exit(1)
    }
    let appEl = AXUIElementCreateApplication(target.processIdentifier)
    for win in appEl.windows {
        guard let f = win.frame else { continue }
        log += "window \(win.string("AXTitle") ?? "?") role=\(win.role ?? "?") sub=\(win.subrole ?? "?") frame=\(f) state=\(String(describing: wm.state(of: win)))\n"
        for dy in [4.0, 12, 20, 30, 45] {
            for fx in [0.1, 0.3, 0.5, 0.7, 0.9] {
                let p = CGPoint(x: f.minX + f.width * fx, y: f.minY + dy)
                guard let el = AXUIElement.element(at: p) else { log += "  (\(Int(fx*100))%, +\(Int(dy))) no element\n"; continue }
                var chain: [String] = []
                var cur: AXUIElement? = el
                for _ in 0..<8 { guard let c = cur else { break }; chain.append(c.role ?? "?"); if c.role == "AXWindow" { break }; cur = c.parent }
                let hitWin = el.windowAncestor()
                log += "  (\(Int(fx*100))%, +\(Int(dy))) pid=\(el.pid ?? -1) chain=\(chain.joined(separator: ">")) window=\(hitWin.map { CFEqual($0, win) } ?? false) titlebar=\(wm.titlebarWindow(at: p) != nil) drag=\(wm.debugDragWindow(at: p))\n"
            }
        }
    }
    try? log.write(toFile: out, atomically: true, encoding: .utf8)
    exit(0)
}
if let i = CommandLine.arguments.firstIndex(of: "--drag-test"), i + 1 < CommandLine.arguments.count {
    // Snaps Finder's front window, then drags its title bar with synthetic events.
    Prefs.registerDefaults()
    app.setActivationPolicy(.accessory)
    let out = CommandLine.arguments[i + 1]
    let wm = WindowManager()
    let engine = GestureEngine(windowManager: wm)
    var log = "trusted=\(AXIsProcessTrusted()) tap=\(engine.start())\n"
    func wait(_ t: TimeInterval) { RunLoop.main.run(until: Date().addingTimeInterval(t)) }
    func post(_ type: CGEventType, _ p: CGPoint) {
        CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
    }
    guard let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first,
          let win = AXUIElementCreateApplication(finder.processIdentifier).windows.first(where: { $0.subrole == "AXStandardWindow" }),
          let original = win.frame else {
        try? (log + "no Finder window\n").write(toFile: out, atomically: true, encoding: .utf8); exit(1)
    }
    log += "original \(original)\n"
    let dragOnly = CommandLine.arguments.contains("drag-only") || CommandLine.arguments.contains("post-only")
    if CommandLine.arguments.contains("post-only") { engine.stop() } // only post events; let the real agent react
    if !dragOnly { wm.apply(.layout(.maximize), to: win) }
    wait(0.6)
    if CommandLine.arguments.contains("snap-only") {
        try? (log + "snapped only\n").write(toFile: out, atomically: true, encoding: .utf8); exit(0)
    }
    let snapped = win.frame ?? .zero
    log += "snapped \(snapped) state=\(String(describing: wm.state(of: win)))\n"
    let grab = CGPoint(x: snapped.midX, y: snapped.minY + 14)
    log += "candidate at grab: \(wm.dragUnsnapCandidate(at: grab) != nil)\n"
    post(.leftMouseDown, grab); wait(0.15)
    for step in 1...15 {
        post(.leftMouseDragged, CGPoint(x: grab.x, y: grab.y + CGFloat(step) * 8)); wait(0.03)
        if step == 6 { log += "mid-drag AX position \(String(describing: win.position))\n" }
    }
    post(.leftMouseUp, CGPoint(x: grab.x, y: grab.y + 120)); wait(0.6)
    log += "final \(String(describing: win.frame))\nstats \(engine.dragStats)\n"
    try? log.write(toFile: out, atomically: true, encoding: .utf8)
    if !dragOnly, let f = win.frame, f.size != original.size { win.setFrame(original) }
    exit(0)
}
let delegate = AppDelegate()
app.delegate = delegate
app.run()
