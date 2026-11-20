import AppKit
import ApplicationServices

/// Finds windows under the cursor and applies gesture outcomes to them.
final class WindowManager {
    /// Frames from before a window was first snapped, used by "Restore".
    private var savedFrames: [AXUIElement: CGRect] = [:]
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    // MARK: Hit testing

    /// The standard window whose title bar / toolbar region is under `point`.
    func titlebarWindow(at point: CGPoint) -> AXUIElement? {
        guard let el = AXUIElement.element(at: point),
              let win = el.windowAncestor(),
              let frame = win.frame,
              isEligible(win) else { return nil }

        let y = point.y - frame.minY
        guard y >= 0, frame.contains(point) else { return nil }
        let base = Prefs.titlebarHeight
        if y <= base { return win }
        // Unified toolbars and tab strips sit below the classic title bar height.
        if y <= base + 60, el.hasAncestor(withRoleIn: ["AXToolbar", "AXTabGroup"], upTo: win) { return win }
        if y <= base + 30, CFEqual(el, win) { return win }
        return nil
    }

    func isEligible(_ win: AXUIElement) -> Bool {
        guard let pid = win.pid, pid != ownPID else { return false }
        if win.bool("AXFullScreen") == true { return false }
        let sub = win.subrole
        guard sub == nil || sub == "AXStandardWindow" || sub == "AXDialog" else { return false }
        if let bundle = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier,
           Prefs.excludedApps.contains(bundle) { return false }
        return true
    }

    func isAlive(_ win: AXUIElement) -> Bool { win.frame != nil }

    // MARK: State

    func screen(of win: AXUIElement) -> NSScreen {
        Screens.screen(for: win.frame ?? .zero)
    }

    /// Which layout (if any) the window currently occupies.
    func detect(_ win: AXUIElement) -> Layout? {
        guard let f = win.frame else { return nil }
        let area = Screens.visibleArea(screen(of: f))
        let tol: CGFloat = 6
        return Layout.allCases.first { l in
            let r = l.rect(in: area, gap: Prefs.gap)
            return abs(r.minX - f.minX) <= tol && abs(r.minY - f.minY) <= tol
                && abs(r.width - f.width) <= tol && abs(r.height - f.height) <= tol
        }
    }

    private func screen(of frame: CGRect) -> NSScreen { Screens.screen(for: frame) }

    // MARK: Preview

    /// Frame (Quartz coordinates) the outcome would produce, for the overlay.
    func previewFrame(_ outcome: Outcome, for win: AXUIElement) -> CGRect? {
        guard let f = win.frame else { return nil }
        let scr = screen(of: f)
        let area = Screens.visibleArea(scr)
        switch outcome {
        case .none: return nil
        case .layout(let l): return l.rect(in: area, gap: Prefs.gap)
        case .restore: return restoreFrame(for: win, current: f, area: area)
        case .minimize:
            let w = min(f.width, area.width) * 0.25, h = min(f.height, area.height) * 0.25
            return CGRect(x: area.midX - w / 2, y: area.maxY - h - 12, width: w, height: h)
        case .moveScreen(let d):
            guard let target = Screens.neighbor(of: scr, d) else { return nil }
            return Screens.map(f, from: area, to: Screens.visibleArea(target))
        }
    }

    private func restoreFrame(for win: AXUIElement, current: CGRect, area: CGRect) -> CGRect {
        if let saved = savedFrames[win] {
            // Keep the saved size but bring it onto the current screen.
            var r = saved
            r.size.width = min(r.width, area.width)
            r.size.height = min(r.height, area.height)
            if !area.intersects(r) || !area.contains(CGPoint(x: r.midX, y: r.minY + 10)) {
                r.origin = CGPoint(x: area.midX - r.width / 2, y: area.midY - r.height / 2)
            }
            return r.integral
        }
        let w = area.width * 0.6, h = area.height * 0.7
        return CGRect(x: area.midX - w / 2, y: area.midY - h / 2, width: w, height: h).integral
    }

    // MARK: Actions

    func apply(_ outcome: Outcome, to win: AXUIElement) {
        guard let f = win.frame else { return }
        switch outcome {
        case .none: return
        case .layout(let l):
            if detect(win) == nil { savedFrames[win] = f }
            let area = Screens.visibleArea(screen(of: f))
            setFrame(win, l.rect(in: area, gap: Prefs.gap))
        case .restore:
            let area = Screens.visibleArea(screen(of: f))
            setFrame(win, restoreFrame(for: win, current: f, area: area))
            savedFrames[win] = nil
        case .minimize:
            win.set("AXMinimized", kCFBooleanTrue)
        case .moveScreen:
            guard let target = previewFrame(outcome, for: win) else { return }
            setFrame(win, target)
        }
        if outcome != .minimize, Prefs.activateAfterSnap { focus(win) }
        trimSavedFrames()
        Prefs.countSwoosh()
    }

    /// Double tap: unsnap a snapped window, otherwise centre it.
    func unsnapOrCenter(_ win: AXUIElement) {
        guard let f = win.frame else { return }
        if detect(win) != nil {
            apply(.restore, to: win)
            return
        }
        let area = Screens.visibleArea(screen(of: f))
        let w = min(f.width, area.width), h = min(f.height, area.height)
        setFrame(win, CGRect(x: area.midX - w / 2, y: area.midY - h / 2, width: w, height: h).integral)
        if Prefs.activateAfterSnap { focus(win) }
        Prefs.countSwoosh()
    }

    func close(_ win: AXUIElement) {
        if let button = win.element("AXCloseButton") { button.perform("AXPress") }
        Prefs.countSwoosh()
    }

    func quitApp(_ win: AXUIElement) {
        guard let pid = win.pid else { return }
        NSRunningApplication(processIdentifier: pid)?.terminate()
        Prefs.countSwoosh()
    }

    func toggleFullScreen(_ win: AXUIElement) {
        let isFull = win.bool("AXFullScreen") ?? false
        if !win.set("AXFullScreen", isFull ? kCFBooleanFalse : kCFBooleanTrue) {
            win.element("AXFullScreenButton")?.perform("AXPress")
        }
        Prefs.countSwoosh()
    }

    private func setFrame(_ win: AXUIElement, _ rect: CGRect) {
        // Some apps animate AX-driven resizes when "enhanced UI" is on (set by
        // VoiceOver-like clients); switch it off for the move, then restore.
        let app = win.pid.map { AXUIElementCreateApplication($0) }
        let enhanced = app?.bool("AXEnhancedUserInterface") ?? false
        if enhanced { app?.set("AXEnhancedUserInterface", kCFBooleanFalse) }
        win.setFrame(rect)
        if enhanced { app?.set("AXEnhancedUserInterface", kCFBooleanTrue) }
    }

    private func focus(_ win: AXUIElement) {
        win.perform("AXRaise")
        if let pid = win.pid { NSRunningApplication(processIdentifier: pid)?.activate() }
    }

    private func trimSavedFrames() {
        if savedFrames.count > 200 {
            savedFrames = savedFrames.filter { isAlive($0.key) }
        }
    }
}
