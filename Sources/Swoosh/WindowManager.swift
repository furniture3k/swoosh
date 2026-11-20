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

    /// The window whose title bar / toolbar region is under `point`.
    func titlebarWindow(at point: CGPoint, allowFullScreen: Bool = false) -> AXUIElement? {
        guard let el = AXUIElement.element(at: point),
              let win = el.windowAncestor(),
              let frame = win.frame,
              isEligible(win, allowFullScreen: allowFullScreen) else { return nil }
        let accepted = TitlebarPolicy.accepts(
            offsetY: point.y - frame.minY,
            windowHeight: frame.height,
            baseHeight: Prefs.titlebarHeight,
            ancestorRoles: el.roles(upTo: win),
            hitIsWindow: CFEqual(el, win))
        return accepted && frame.contains(point) ? win : nil
    }

    func isEligible(_ win: AXUIElement, allowFullScreen: Bool = false) -> Bool {
        guard let pid = win.pid, pid != ownPID else { return false }
        if !allowFullScreen, isFullScreen(win) { return false }
        let sub = win.subrole
        guard sub == nil || sub == "AXStandardWindow" || sub == "AXDialog" else { return false }
        return !isExcluded(pid: pid)
    }

    private func isExcluded(pid: pid_t) -> Bool {
        guard let bundle = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier else { return false }
        return Prefs.excludedApps.contains(bundle)
    }

    func isFullScreen(_ win: AXUIElement) -> Bool { win.bool("AXFullScreen") ?? false }
    func isAlive(_ win: AXUIElement) -> Bool { win.frame != nil }

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
        case .layout(let l): return l.rect(in: area, gap: Prefs.gap)
        case .restore: return Geometry.restoreFrame(saved: savedFrames[win], area: area)
        case .minimize: return Geometry.minimizePreview(for: f, in: area)
        case .moveScreen(let d):
            let scr = Screens.screen(for: f)
            guard let target = Screens.neighbor(of: scr, d) else { return nil }
            return Geometry.map(f, from: Screens.workArea(scr), to: Screens.workArea(target))
        }
    }

    // MARK: Actions

    func apply(_ outcome: Outcome, to win: AXUIElement) {
        guard let f = win.frame else { return }
        switch outcome {
        case .none, .minimizeAll, .unminimizeAll:
            return
        case .layout(let l):
            if state(of: win) == nil { savedFrames[win] = f }
            let target = l.rect(in: workArea(for: f), gap: Prefs.gap)
            let result = setFrame(win, target)
            lastSnap[win] = (l, result)
        case .restore:
            setFrame(win, Geometry.restoreFrame(saved: savedFrames[win], area: workArea(for: f)))
            savedFrames[win] = nil
            lastSnap[win] = nil
        case .minimize:
            win.set("AXMinimized", kCFBooleanTrue)
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
