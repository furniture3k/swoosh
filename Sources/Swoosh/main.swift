import AppKit
import ApplicationServices
import SwiftUI
import SwooshCore

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

        if AXIsProcessTrusted() {
            engine.start()
        } else {
            promptForAccessibility()
        }
        // Watch for the permission being granted or revoked while running.
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.checkPermission()
        }

        if !Prefs.onboarded {
            Prefs.onboarded = true
            openSettings(tab: .setup)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Opening the app again (Finder, Spotlight) shows Settings, since there is no Dock icon.
        openSettings(tab: SettingsRouter.shared.tab)
        return false
    }

    private func checkPermission() {
        let trusted = AXIsProcessTrusted()
        if trusted, !engine.isRunning { engine.start() }
        if !trusted, engine.isRunning { engine.stop() }
        updateIcon()
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

    @objc private func openSettingsFromMenu() { openSettings(tab: SettingsRouter.shared.tab) }
    @objc private func openGuide() { openSettings(tab: .gestures) }

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
        // Show in the Dock and app switcher while Settings is open.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === settingsWindow else { return }
        NSApp.setActivationPolicy(.accessory)
    }
}

let app = NSApplication.shared
if let i = CommandLine.arguments.firstIndex(of: "--render-settings"), i + 1 < CommandLine.arguments.count {
    Prefs.registerDefaults()
    app.setActivationPolicy(.accessory)
    SettingsRenderer.render(to: CommandLine.arguments[i + 1])
    exit(0)
}
let delegate = AppDelegate()
app.delegate = delegate
app.run()
