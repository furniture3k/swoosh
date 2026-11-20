import AppKit
import ApplicationServices
import SwooshCore

/// Finds windows and applies gesture outcomes to them.
final class WindowManager {
    /// Frames from before a window was first snapped, used by "Restore".
    private var savedFrames: [AXUIElement: CGRect] = [:]
    /// The layout Swoosh last applied to a window and the frame that resulted.
    /// Lets windows with a minimum size (which cannot match the exact layout
    /// rect) still chain correctly.
    private var lastSnap: [AXUIElement: (layout: Layout, frame: CGRect)] = [:]
    private let ownPID = ProcessInfo.processInfo.processIdentifier
    private let bulkQueue = DispatchQueue(label: "swoosh.bulk", qos: .userInitiated)

    // MARK: Hit testing

    enum Hit {
        case window(AXUIElement)
        case dock(NSRunningApplication)
    }

    /// What a gesture at `point` would act on: one hit test, then the cheapest
    /// checks first. A scroll in a window's content (the common case) is
    /// rejected after about three Accessibility requests.
    func hit(at point: CGPoint, allowFullScreen: Bool, dock: Bool) -> Hit? {
        guard let el = AXUIElement.element(at: point), let pid = el.pid, pid != ownPID else { return nil }
        if pid == dockPID {
            guard dock, let app = dockApp(element: el) else { return nil }
            return .dock(app)
        }
        if isExcluded(pid: pid) { return nil }
        return titlebarWindow(element: el, at: point, allowFullScreen: allowFullScreen).map { .window($0) }
    }

    /// The window whose title bar / toolbar region is under `point`.
    func titlebarWindow(at point: CGPoint, allowFullScreen: Bool = false) -> AXUIElement? {
        guard let el = AXUIElement.element(at: point), let pid = el.pid, pid != ownPID, !isExcluded(pid: pid) else { return nil }
        return titlebarWindow(element: el, at: point, allowFullScreen: allowFullScreen)
    }

    private func titlebarWindow(element el: AXUIElement, at point: CGPoint, allowFullScreen: Bool) -> AXUIElement? {
        let own = el.attributes(["AXRole", "AXWindow"])
        let hitIsWindow = (own[0] as? String) == "AXWindow"
        guard let win = hitIsWindow ? el : (AXUIElement.asElement(own[1]) ?? el.windowAncestor()) else { return nil }

        let w = win.attributes(["AXPosition", "AXSize", "AXSubrole", "AXFullScreen"])
        guard let origin = AXUIElement.asPoint(w[0]), let size = AXUIElement.asSize(w[1]) else { return nil }
        let frame = CGRect(origin: origin, size: size)
        let base = Prefs.titlebarHeight
        let offsetY = point.y - frame.minY
        // Fast reject: nowhere near the top of the window.
        guard frame.contains(point), offsetY >= 0, offsetY <= base + 60 else { return nil }

        if !allowFullScreen, (w[3] as? NSNumber)?.boolValue == true { return nil }
        let sub = w[2] as? String
        guard sub == nil || sub == "AXStandardWindow" || sub == "AXDialog" else { return nil }

        // Only walk as far up the tree as the policy needs.
        let depth = offsetY <= base ? TitlebarPolicy.blockingDepth : 10
        let roles = hitIsWindow ? [] : el.roles(upTo: win, limit: depth)
        let accepted = TitlebarPolicy.accepts(offsetY: offsetY, windowHeight: frame.height, baseHeight: base,
                                              ancestorRoles: roles, hitIsWindow: hitIsWindow)
        return accepted ? win : nil
    }

    func isEligible(_ win: AXUIElement, allowFullScreen: Bool = false) -> Bool {
        guard let pid = win.pid, pid != ownPID else { return false }
        let v = win.attributes(["AXSubrole", "AXFullScreen"])
        if !allowFullScreen, (v[1] as? NSNumber)?.boolValue == true { return false }
        let sub = v[0] as? String
        guard sub == nil || sub == "AXStandardWindow" || sub == "AXDialog" else { return false }
        return !isExcluded(pid: pid)
    }

    private var bundleIDs: [pid_t: String] = [:]

    private func isExcluded(pid: pid_t) -> Bool {
        let excluded = Prefs.excludedApps
        guard !excluded.isEmpty else { return false }
        if bundleIDs[pid] == nil {
            if bundleIDs.count > 200 { bundleIDs.removeAll() }
            bundleIDs[pid] = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? ""
        }
        return excluded.contains(bundleIDs[pid]!)
    }

    private var cachedDockPID: pid_t?

    /// The Dock's process, looked up once and refreshed if the Dock restarts.
    private var dockPID: pid_t? {
        if let pid = cachedDockPID, kill(pid, 0) == 0 { return pid }
        cachedDockPID = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier
        return cachedDockPID
    }

    func isFullScreen(_ win: AXUIElement) -> Bool { win.bool("AXFullScreen") ?? false }
    func isAlive(_ win: AXUIElement) -> Bool { win.role != nil }

    /// Focused window of the frontmost app (keyboard shortcuts act on it).
    func frontmostWindow() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != ownPID else { return nil }
        let el = AXUIElementCreateApplication(app.processIdentifier)
        guard let win = el.element("AXFocusedWindow") ?? el.element("AXMainWindow"),
              isEligible(win) else { return nil }
        return win
    }

    // MARK: State

    func workArea(for frame: CGRect) -> CGRect { Screens.workArea(Screens.screen(for: frame)) }

    /// Which layout (if any) the window currently occupies.
    func state(of win: AXUIElement) -> Layout? {
        guard let f = win.frame else { return nil }
        if let l = Geometry.detect(frame: f, area: workArea(for: f), gap: Prefs.gap) { return l }
        if let snap = lastSnap[win], Geometry.approximatelyEqual(snap.frame, f, tolerance: 2) { return snap.layout }
        return nil
    }

    // MARK: Preview

    /// Frame the outcome would produce, for the overlay.
    func previewFrame(_ outcome: Outcome, for win: AXUIElement?) -> CGRect? {
        guard let win, let f = win.frame else { return nil }
        let area = workArea(for: f)
        switch outcome {
        case .none, .minimizeAll, .unminimizeAll: return nil
        case .toggleFullScreen: return Screens.fullArea(Screens.screen(for: f))
        case .layoutOnScreen(let l, let d):
            guard let target = Screens.neighbor(of: Screens.screen(for: f), d) else { return nil }
            return l.rect(in: Screens.workArea(target), gap: Prefs.gap)
        case .layout(let l): return l.rect(in: area, gap: Prefs.gap)
        case .restore: return Geometry.restoreFrame(saved: savedFrame(for: win), area: area)
        case .minimize: return Geometry.minimizePreview(for: f, in: area)
        case .moveScreen(let d):
            let scr = Screens.screen(for: f)
            guard let target = Screens.neighbor(of: scr, d) else { return nil }
            return Geometry.map(f, from: Screens.workArea(scr), to: Screens.workArea(target))
        }
    }

    /// Directions in which another screen exists, relative to the window.
    func screenDirections(for win: AXUIElement) -> Set<Direction> {
        guard let f = win.frame else { return [] }
        let scr = Screens.screen(for: f)
        return Set(Direction.allCases.filter { Screens.neighbor(of: scr, $0) != nil })
    }

    // MARK: Dock

    /// The running app whose Dock icon is under `point`.
    func dockApp(at point: CGPoint) -> NSRunningApplication? {
        guard let el = AXUIElement.element(at: point), el.pid == dockPID else { return nil }
        return dockApp(element: el)
    }

    private func dockApp(element el: AXUIElement) -> NSRunningApplication? {
        let v = el.attributes(["AXRole", "AXSubrole", "AXURL", "AXTitle"])
        guard (v[0] as? String) == "AXDockItem", (v[1] as? String) == "AXApplicationDockItem" else { return nil }
        let running = NSWorkspace.shared.runningApplications
        if let url = v[2] as? URL {
            let path = url.standardizedFileURL.resolvingSymlinksInPath().path
            if let app = running.first(where: { $0.bundleURL?.standardizedFileURL.resolvingSymlinksInPath().path == path }) {
                return app
            }
        }
        let title = v[3] as? String
        return running.first { $0.activationPolicy == .regular && $0.localizedName == title }
    }

    /// Windows that could be minimized or cycled (standard, not minimized).
    private func visibleWindows(of app: NSRunningApplication) -> [AXUIElement] {
        AXUIElementCreateApplication(app.processIdentifier).windows.filter {
            $0.subrole == "AXStandardWindow" && $0.bool("AXMinimized") != true
        }
    }

    private func minimizedWindows(of app: NSRunningApplication) -> [AXUIElement] {
        AXUIElementCreateApplication(app.processIdentifier).windows.filter { $0.bool("AXMinimized") == true }
    }

    /// Performs a Dock gesture. Returns the window to chain follow-up gestures to.
    @discardableResult
    func perform(_ action: DockAction, on app: NSRunningApplication) -> AXUIElement? {
        guard !Prefs.excludedApps.contains(app.bundleIdentifier ?? "") else { return nil }
        defer { Prefs.countSwoosh() }
        switch action {
        case .none:
            return nil
        case .unminimize(let all):
            let minimized = minimizedWindows(of: app)
            guard !minimized.isEmpty else {
                // Nothing minimized: just bring the app forward.
                app.unhide()
                app.activate()
                return visibleWindows(of: app).first
            }
            // Most recently minimized by Swoosh first, then whatever the app lists.
            let recent = minimizedOrder.reversed().first { item in minimized.contains { CFEqual($0, item) } }
            let targets = all ? minimized : [recent ?? minimized[0]]
            for w in targets { w.set("AXMinimized", kCFBooleanFalse) }
            minimizedOrder.removeAll { item in targets.contains { CFEqual($0, item) } }
            app.unhide()
            app.activate()
            targets.last?.perform("AXRaise")
            return targets.last
        case .minimize(let all):
            let windows = visibleWindows(of: app)
            for w in all ? windows : Array(windows.prefix(1)) { minimize(w) }
            return nil
        case .cycle(let forward):
            let windows = visibleWindows(of: app)
            guard !windows.isEmpty else { app.activate(); return nil }
            // AXWindows is front-to-back: forward brings the second window up,
            // backward brings the last one up.
            let next = windows.count > 1 ? (forward ? windows[1] : windows[windows.count - 1]) : windows[0]
            next.perform("AXRaise")
            next.set("AXMain", kCFBooleanTrue)
            app.activate()
            return next
        case .quit:
            guard app.bundleIdentifier != "com.apple.finder" else { NSSound.beep(); return nil }
            app.terminate()
            return nil
        case .newWindow:
            app.activate()
            // ⌘N to the app, after it has come to the front.
            let pid = app.processIdentifier
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                let src = CGEventSource(stateID: .hidSystemState)
                for down in [true, false] {
                    let e = CGEvent(keyboardEventSource: src, virtualKey: 45, keyDown: down)
                    e?.flags = .maskCommand
                    e?.postToPid(pid)
                }
            }
            return nil
        case .hide(let others):
            if others {
                for other in NSWorkspace.shared.runningApplications
                where other.activationPolicy == .regular && other != app && other.processIdentifier != ownPID {
                    other.hide()
                }
                app.activate()
            } else {
                app.hide()
            }
            return nil
        }
    }

    /// Windows minimized by Swoosh, oldest first (Dock swipe up restores the latest).
    private var minimizedOrder: [AXUIElement] = []

    private func minimize(_ win: AXUIElement) {
        win.set("AXMinimized", kCFBooleanTrue)
        minimizedOrder.append(win)
        if minimizedOrder.count > 50 { minimizedOrder.removeFirst(minimizedOrder.count - 50) }
    }

    // MARK: Drag to unsnap

    /// Debug: would a drag starting at `point` be considered (ignoring saved frames)?
    func debugDragWindow(at point: CGPoint) -> Bool { dragWindow(at: point) != nil }

    /// A window Swoosh snapped, grabbed by its title bar at `point`: returns it
    /// with the frame it had before snapping. Cheap when nothing is snapped.
    func dragUnsnapCandidate(at point: CGPoint) -> (window: AXUIElement, frame: CGRect, saved: CGRect)? {
        guard hasSavedFrames, let win = dragWindow(at: point), let saved = savedFrame(for: win),
              let frame = win.frame, state(of: win) != nil else { return nil }
        return (win, frame, saved)
    }

    // MARK: Remembered pre-snap frames

    /// Pre-snap frames also live on disk, keyed by app and window title, so a
    /// window snapped before Swoosh restarted (e.g. after an update) can still
    /// be dragged back to its old size.
    private static let persistedKey = "preSnapFrames"

    private var hasSavedFrames: Bool {
        !savedFrames.isEmpty || !(UserDefaults.standard.dictionary(forKey: Self.persistedKey)?.isEmpty ?? true)
    }

    private func persistKey(for win: AXUIElement) -> String? {
        guard let pid = win.pid, let bundle = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier else { return nil }
        return bundle + "|" + (win.string("AXTitle") ?? "")
    }

    private func rememberFrame(_ frame: CGRect, for win: AXUIElement) {
        savedFrames[win] = frame
        guard let key = persistKey(for: win) else { return }
        var all = UserDefaults.standard.dictionary(forKey: Self.persistedKey) ?? [:]
        all[key] = [frame.minX, frame.minY, frame.width, frame.height, Date().timeIntervalSince1970]
        if all.count > 60 {
            // Drop the oldest entries.
            let sorted = all.sorted { (($0.value as? [Double])?.last ?? 0) < (($1.value as? [Double])?.last ?? 0) }
            for (k, _) in sorted.prefix(all.count - 60) { all[k] = nil }
        }
        UserDefaults.standard.set(all, forKey: Self.persistedKey)
    }

    private func savedFrame(for win: AXUIElement) -> CGRect? {
        if let f = savedFrames[win] { return f }
        guard let key = persistKey(for: win), let all = UserDefaults.standard.dictionary(forKey: Self.persistedKey) else { return nil }
        // Exact app + title, else the most recent entry for the same app: some
        // apps change their window title constantly (VS Code shows the open file).
        let bundlePrefix = String(key.prefix { $0 != "|" }) + "|"
        let entry = (all[key] as? [Double]) ?? all
            .filter { $0.key.hasPrefix(bundlePrefix) }
            .compactMap { $0.value as? [Double] }
            .max { ($0.last ?? 0) < ($1.last ?? 0) }
        guard let v = entry, v.count >= 4 else { return nil }
        return CGRect(x: v[0], y: v[1], width: v[2], height: v[3])
    }

    private func forgetFrame(for win: AXUIElement) {
        savedFrames[win] = nil
        guard let key = persistKey(for: win),
              var all = UserDefaults.standard.dictionary(forKey: Self.persistedKey) else { return }
        let before = all.count
        all[key] = nil
        if all.count == before {
            // Title changed since snapping: drop the app's latest entry instead.
            let bundlePrefix = String(key.prefix { $0 != "|" }) + "|"
            if let latest = all.filter({ $0.key.hasPrefix(bundlePrefix) })
                .max(by: { (($0.value as? [Double])?.last ?? 0) < (($1.value as? [Double])?.last ?? 0) })?.key {
                all[latest] = nil
            }
        }
        if all.count != before { UserDefaults.standard.set(all, forKey: Self.persistedKey) }
    }

    /// The window whose top strip (title bar / toolbar height) is under `point`.
    /// Unlike `titlebarWindow`, this ignores what kind of element was hit: some
    /// apps (VS Code and other Electron apps) expose their title bar as a scroll
    /// area. That's safe here because unsnapping only happens once the window
    /// actually moves.
    private func dragWindow(at point: CGPoint) -> AXUIElement? {
        guard let el = AXUIElement.element(at: point), let pid = el.pid, pid != ownPID, pid != dockPID,
              !isExcluded(pid: pid) else { return nil }
        let own = el.attributes(["AXRole", "AXWindow"])
        guard let win = (own[0] as? String) == "AXWindow" ? el : (AXUIElement.asElement(own[1]) ?? el.windowAncestor()),
              let frame = win.frame, frame.contains(point) else { return nil }
        let offsetY = point.y - frame.minY
        guard offsetY >= 0, offsetY <= Prefs.titlebarHeight + 60, isEligible(win) else { return nil }
        return win
    }

    /// Restores the pre-snap size while the user drags the window away.
    func unsnapForDrag(_ win: AXUIElement, saved: CGRect, cursor: CGPoint, grabRatio: CGFloat) {
        guard let current = win.frame else { return }
        let target = Geometry.dragRestoreFrame(saved: saved.size, current: current, cursor: cursor,
                                               grabRatio: grabRatio, area: workArea(for: current))
        win.setSize(target.size)
        win.setPosition(target.origin)
        forgetFrame(for: win)
        lastSnap[win] = nil
    }

    // MARK: Actions

    func apply(_ outcome: Outcome, to win: AXUIElement) {
        guard let f = win.frame else { return }
        switch outcome {
        case .none, .minimizeAll, .unminimizeAll:
            return
        case .layout(let l):
            if state(of: win) == nil { rememberFrame(f, for: win) }
            let target = l.rect(in: workArea(for: f), gap: Prefs.gap)
            let result = setFrame(win, target)
            lastSnap[win] = (l, result)
        case .restore:
            setFrame(win, Geometry.restoreFrame(saved: savedFrame(for: win), area: workArea(for: f)))
            forgetFrame(for: win)
            lastSnap[win] = nil
        case .minimize:
            minimize(win)
        case .toggleFullScreen:
            toggleFullScreen(win)
            return
        case .layoutOnScreen(let l, let d):
            guard let target = Screens.neighbor(of: Screens.screen(for: f), d) else { return }
            if state(of: win) == nil { rememberFrame(f, for: win) }
            let rect = l.rect(in: Screens.workArea(target), gap: Prefs.gap)
            // Move first so the window is resized against the right screen.
            setFrame(win, CGRect(origin: rect.origin, size: f.size))
            lastSnap[win] = (l, setFrame(win, rect))
        case .moveScreen:
            guard let target = previewFrame(outcome, for: win) else { return }
            let previous = state(of: win)
            let result = setFrame(win, target)
            // Keep a snapped window snapped to the same layout on the new screen.
            if let previous {
                let exact = previous.rect(in: workArea(for: result), gap: Prefs.gap)
                lastSnap[win] = (previous, setFrame(win, exact))
            }
        }
        if outcome != .minimize, Prefs.activateAfterSnap { focus(win) }
        trimCaches()
        Prefs.countSwoosh()
    }

    /// Double tap: unsnap a snapped window, otherwise centre it.
    func unsnapOrCenter(_ win: AXUIElement) {
        guard let f = win.frame else { return }
        if state(of: win) != nil {
            apply(.restore, to: win)
            return
        }
        setFrame(win, Geometry.centered(f.size, in: workArea(for: f)))
        if Prefs.activateAfterSnap { focus(win) }
        Prefs.countSwoosh()
    }

    func close(_ win: AXUIElement) {
        guard let button = win.element("AXCloseButton"), button.perform("AXPress") else {
            NSSound.beep()
            return
        }
        Prefs.countSwoosh()
    }

    func quitApp(_ win: AXUIElement) {
        guard let pid = win.pid, let app = NSRunningApplication(processIdentifier: pid),
              app.bundleIdentifier != "com.apple.finder" else { NSSound.beep(); return }
        app.terminate()
        Prefs.countSwoosh()
    }

    func toggleFullScreen(_ win: AXUIElement) {
        let full = isFullScreen(win)
        if !win.set("AXFullScreen", full ? kCFBooleanFalse : kCFBooleanTrue) {
            win.element("AXFullScreenButton")?.perform("AXPress")
        }
        Prefs.countSwoosh()
    }

    /// Minimizes every window on `screen` (menu bar swipe down).
    func minimizeAll(on screen: NSScreen) { bulk(on: screen, minimize: true) }

    /// Restores every minimized window that belongs to `screen` (menu bar swipe up).
    func unminimizeAll(on screen: NSScreen) { bulk(on: screen, minimize: false) }

    private func bulk(on screen: NSScreen, minimize: Bool) {
        let screens = NSScreen.screens.map(Screens.fullArea)
        guard let index = NSScreen.screens.firstIndex(of: screen) else { return }
        let excluded = Prefs.excludedApps
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != ownPID
                && !excluded.contains($0.bundleIdentifier ?? "")
        }.map(\.processIdentifier)
        // AX calls to many apps can be slow; keep them off the event-tap thread.
        bulkQueue.async {
            for pid in apps {
                for win in AXUIElementCreateApplication(pid).windows {
                    guard win.subrole == "AXStandardWindow", let f = win.frame,
                          Geometry.bestIndex(for: f, in: screens) == index else { continue }
                    let isMin = win.bool("AXMinimized") ?? false
                    if minimize, !isMin { win.set("AXMinimized", kCFBooleanTrue) }
                    if !minimize, isMin { win.set("AXMinimized", kCFBooleanFalse) }
                }
            }
        }
        Prefs.countSwoosh()
    }

    /// Sets the frame and returns the frame the window actually ended up with.
    @discardableResult
    private func setFrame(_ win: AXUIElement, _ rect: CGRect) -> CGRect {
        // Apps animate AX-driven resizes while "enhanced UI" is on (set by
        // assistive clients); switch it off for the move, then restore it.
        let app = win.pid.map { AXUIElementCreateApplication($0) }
        let enhanced = app?.bool("AXEnhancedUserInterface") ?? false
        if enhanced { app?.set("AXEnhancedUserInterface", kCFBooleanFalse) }
        win.setFrame(rect)
        if enhanced { app?.set("AXEnhancedUserInterface", kCFBooleanTrue) }
        return win.frame ?? rect
    }

    private func focus(_ win: AXUIElement) {
        win.perform("AXRaise")
        if let pid = win.pid { NSRunningApplication(processIdentifier: pid)?.activate() }
    }

    private func trimCaches() {
        if savedFrames.count > 100 { savedFrames = savedFrames.filter { isAlive($0.key) } }
        if lastSnap.count > 100 { lastSnap = lastSnap.filter { isAlive($0.key) } }
    }
}
