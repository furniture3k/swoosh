import AppKit
import ApplicationServices
import SwooshCore

/// Intercepts trackpad scroll / pinch / smart-zoom events through a CGEventTap.
/// Gestures that start over a window's title bar, a Dock icon or the menu bar
/// are swallowed (the app underneath never sees them) and turned into actions.
final class GestureEngine {
    private let wm: WindowManager
    let overlay = Overlay()
    let hud = GestureHUD()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    // Raw CGEventType values; the gesture ones are not in the Swift enum.
    private enum EventType {
        static let scrollWheel: UInt32 = 22
        static let magnify: UInt32 = 30
        static let smartMagnify: UInt32 = 32
        static let tapDisabledByTimeout: UInt32 = 0xFFFF_FFFE
        static let tapDisabledByUserInput: UInt32 = 0xFFFF_FFFF
    }

    // CGScrollPhase / CGMomentumScrollPhase values.
    private enum Phase {
        static let began: Int64 = 1, changed: Int64 = 2, ended: Int64 = 4, cancelled: Int64 = 8, mayBegin: Int64 = 128
        static let momentumEnd: Int64 = 3
    }

    private enum Target {
        case window(AXUIElement)
        case menubar(NSScreen)
        case dock(NSRunningApplication)

        var window: AXUIElement? { if case .window(let w) = self { return w } else { return nil } }
        var glyph: OriginGlyph {
            switch self {
            case .window: return .titlebar
            case .menubar: return .menubar
            case .dock: return .dock
            }
        }
    }

    private struct Gesture {
        let target: Target
        var session: SwipeSession
        let anchor: CGPoint
        var strokeActive = true
        /// What has already been applied (window gestures act on each lift and
        /// re-resolve if a follow-up stroke arrives).
        var applied: Outcome = .none
    }

    /// How long after lifting the fingers a new stroke still belongs to the
    /// same gesture (double swipes, "both orders" quarters across strokes).
    private let followUpWindow: TimeInterval = 0.35
    /// Fingers resting this long before moving count as "tap and hold".
    private let holdDuration: TimeInterval = 0.3

    private var gesture: Gesture?
    private var finalizeWork: DispatchWorkItem?
    private var mayBegin: (time: TimeInterval, point: CGPoint)?
    private var pinch: (target: Target, total: CGFloat, label: String)?
    private var swallowMomentum = false
    /// The window most recently acted on keeps receiving gestures (even away
    /// from its title bar) for a moment while the pointer stays put.
    private var chained: (window: AXUIElement, anchor: CGPoint, until: TimeInterval)?

    init(windowManager: WindowManager) { wm = windowManager }

    var isRunning: Bool { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }
    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    @discardableResult
    func start() -> Bool {
        if tap != nil { return true }
        let mask: CGEventMask = (1 << EventType.scrollWheel) | (1 << EventType.magnify) | (1 << EventType.smartMagnify)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            let engine = Unmanaged<GestureEngine>.fromOpaque(refcon!).takeUnretainedValue()
            return engine.handle(rawType: unsafeBitCast(type, to: UInt32.self), event: event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                          options: .defaultTap, eventsOfInterest: mask,
                                          callback: callback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            NSLog("Swoosh: could not create event tap (Accessibility permission missing?)")
            return false
        }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        NSLog("Swoosh: event tap running")
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil
        reset()
    }

    private func reset() {
        finalizeWork?.cancel()
        gesture = nil; pinch = nil; chained = nil
        overlay.hide(); hud.hide()
    }

    // MARK: Dispatch

    private func handle(rawType: UInt32, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        switch rawType {
        case EventType.tapDisabledByTimeout, EventType.tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            // Whatever was in flight is lost; don't leave stale UI behind.
            if gesture?.strokeActive == true { gesture = nil; overlay.hide(); hud.hide() }
            pinch = nil
            return pass
        default: break
        }
        guard Prefs.enabled else { return pass }

        let consumed: Bool
        switch rawType {
        case EventType.scrollWheel: consumed = handleScroll(event)
        case EventType.magnify: consumed = Prefs.pinchGestures && handleMagnify(event)
        case EventType.smartMagnify: consumed = Prefs.doubleTapGesture && handleSmartMagnify(event)
        default: consumed = false
        }
        return consumed ? nil : pass
    }

    /// What a gesture starting at `point` acts on.
    private func target(at point: CGPoint, hold: Bool) -> Target? {
        if let c = chained, TitlebarPolicy.chainApplies(pointer: point, anchor: c.anchor, now: now, until: c.until),
           wm.isAlive(c.window) {
            return .window(c.window)
        }
        chained = nil
        if let w = wm.titlebarWindow(at: point, allowFullScreen: hold) { return .window(w) }
        if Prefs.dockGestures, let app = wm.dockApp(at: point) { return .dock(app) }
        if Prefs.menubarGestures, let screen = Screens.menuBarScreen(at: point) { return .menubar(screen) }
        return nil
    }

    private func chain(_ win: AXUIElement, at point: CGPoint) {
        let t = Prefs.chainTimeout
        chained = t > 0 ? (win, point, now + t) : nil
    }

    // MARK: Swipes (two-finger scroll)

    private func handleScroll(_ event: CGEvent) -> Bool {
        guard event.getIntegerValueField(.scrollWheelEventIsContinuous) == 1 else { return false }
        let phase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
        let momentum = event.getIntegerValueField(.scrollWheelEventMomentumPhase)

        if momentum != 0 {
            let swallow = swallowMomentum
            if momentum == Phase.momentumEnd { swallowMomentum = false }
            return swallow
        }

        switch phase {
        case Phase.mayBegin:
            // Fingers resting without moving: the start of a possible tap-and-hold.
            mayBegin = (now, event.location)
            return gesture != nil
        case Phase.began:
            swallowMomentum = false
            defer { mayBegin = nil }
            return begin(event)
        case Phase.changed:
            guard gesture?.strokeActive == true else { return false }
            accumulate(event)
            return true
        case Phase.ended, Phase.cancelled:
            guard var g = gesture, g.strokeActive else { return false }
            g.strokeActive = false
            gesture = g
            swallowMomentum = true
            if phase == Phase.ended { strokeEnded(at: event.location) } else { cancelGesture() }
            return true
        default:
            return gesture?.strokeActive == true
        }
    }

    private func begin(_ event: CGEvent) -> Bool {
        let point = event.location
        // A follow-up stroke of the gesture that just ended.
        if var g = gesture {
            if !g.strokeActive, hypot(point.x - g.anchor.x, point.y - g.anchor.y) <= 40 {
                finalizeWork?.cancel()
                g.session.beginStroke()
                g.strokeActive = true
                gesture = g
                return true
            }
            if g.strokeActive { return true }
            finalize()
        }
        guard pinch == nil else { return false }

        let hold = mayBegin.map { now - $0.time >= holdDuration && hypot($0.point.x - point.x, $0.point.y - point.y) < 30 } ?? false
        guard let target = target(at: point, hold: hold) else { return false }

        let threshold = Prefs.sensitivity
        let session: SwipeSession
        switch target {
        case .window(let win):
            if event.flags.contains(.maskControl) {
                session = SwipeSession(mode: .screenMove, threshold: threshold)
            } else {
                let ctx = GestureContext(origin: wm.state(of: win), grid: Prefs.grid,
                                         upFillsAlmost: Prefs.upFillsAlmost, hold: hold,
                                         isFullScreen: wm.isFullScreen(win), screens: wm.screenDirections(for: win))
                session = SwipeSession(mode: .window, context: ctx, threshold: threshold)
            }
        case .dock:
            session = SwipeSession(mode: .dock(secondary: event.flags.contains(.maskShift)), threshold: threshold)
        case .menubar:
            session = SwipeSession(mode: .menubar, threshold: threshold)
        }
        gesture = Gesture(target: target, session: session, anchor: point)
        if hold { haptic() }
        return true
    }

    private func accumulate(_ event: CGEvent) {
        guard var g = gesture, let ns = NSEvent(cgEvent: event) else { return }
        // Normalise so +x = fingers right, +y = fingers down, whatever the
        // natural-scrolling setting.
        let sign: CGFloat = ns.isDirectionInvertedFromDevice ? 1 : -1
        let step = g.session.feed(dx: ns.scrollingDeltaX * sign, dy: ns.scrollingDeltaY * sign)
        gesture = g
        if step != nil {
            haptic()
            showFeedback(for: g, at: event.location)
        }
    }

    /// Preview overlay + tooltip for the gesture so far.
    private func showFeedback(for g: Gesture, at point: CGPoint) {
        var glyphs: [GestureGlyph] = g.session.context.hold ? [.hold] : []
        glyphs += g.session.steps.map { .swipe($0) }

        switch g.target {
        case .window(let win):
            let outcome = g.session.outcome
            var title = outcome.title
            if case .moveScreen = outcome, wm.previewFrame(outcome, for: win) == nil { title = "No Screen There" }
            hud.show(origin: .titlebar, gestures: glyphs, action: ActionGlyph(outcome), title: title, at: point)
            if let frame = wm.previewFrame(outcome, for: win) { overlay.show(frame, title: "") } else { overlay.hide() }
        case .menubar(let screen):
            let outcome = g.session.outcome
            hud.show(origin: .menubar, gestures: glyphs, action: ActionGlyph(outcome), title: outcome.title, at: point)
            if outcome != .none { overlay.show(Screens.visibleArea(screen), title: "") }
        case .dock(let app):
            let action = g.session.dockAction
            let name = app.localizedName.map { " · \($0)" } ?? ""
            hud.show(origin: .dock, gestures: glyphs, action: ActionGlyph(action), title: action.title + name, at: point)
        }
    }

    private func strokeEnded(at point: CGPoint) {
        guard var g = gesture else { return }
        switch g.target {
        case .window(let win):
            let outcome = g.session.outcome
            if g.session.endsOnLift {
                // Minimize / full screen: act now and end the gesture, no waiting.
                finalize()
                return
            }
            if outcome != .none, outcome != g.applied {
                overlay.hide()
                wm.apply(outcome, to: win)
                g.applied = outcome
                gesture = g
            } else {
                overlay.hide()
            }
            scheduleFinalize()
        case .dock(let app):
            let action = g.session.dockAction
            if let win = wm.perform(action, on: app) { chain(win, at: point) }
            finalize()
        case .menubar(let screen):
            switch g.session.outcome {
            case .minimizeAll: wm.minimizeAll(on: screen)
            case .unminimizeAll: wm.unminimizeAll(on: screen)
            default: break
            }
            finalize()
        }
    }

    private func scheduleFinalize() {
        finalizeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.finalize() }
        finalizeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + followUpWindow, execute: work)
    }

    /// Ends the gesture: applies anything still pending and arms chaining.
    private func finalize() {
        finalizeWork?.cancel()
        finalizeWork = nil
        guard let g = gesture else { return }
        gesture = nil
        overlay.hide()
        hud.hide()
        guard case .window(let win) = g.target else { return }
        let outcome = g.session.outcome
        if outcome != .none, outcome != g.applied { wm.apply(outcome, to: win) }
        switch outcome {
        case .minimize, .toggleFullScreen, .none: chained = nil
        default: chain(win, at: g.anchor)
        }
    }

    private func cancelGesture() {
        finalizeWork?.cancel()
        gesture = nil
        overlay.hide()
        hud.hide()
    }

    // MARK: Pinch

    private func handleMagnify(_ event: CGEvent) -> Bool {
        guard let ns = NSEvent(cgEvent: event) else { return false }
        if ns.phase.contains(.began) {
            guard gesture?.strokeActive != true, let t = target(at: event.location, hold: true) else { return false }
            if case .menubar = t { return false }
            if gesture != nil { finalize() }
            pinch = (t, 0, "")
            return true
        }
        guard var p = pinch else { return false }
        if ns.phase.contains(.changed) {
            p.total += ns.magnification
            let (label, action) = pinchResult(p.target, p.total, flags: event.flags)
            if label != p.label {
                p.label = label
                if label.isEmpty {
                    hud.hide(); overlay.hide()
                } else {
                    haptic()
                    hud.show(origin: p.target.glyph, gestures: [p.total < 0 ? .pinchIn : .pinchOut],
                             action: action, title: label, at: event.location)
                    if let f = p.target.window?.frame { overlay.show(f, title: "") }
                }
            }
            pinch = p
        } else if ns.phase.contains(.ended) || ns.phase.contains(.cancelled) {
            pinch = nil
            overlay.hide()
            hud.hide()
            guard ns.phase.contains(.ended) else { return true }
            let inward = p.total <= -pinchThreshold, outward = p.total >= pinchThreshold
            guard inward || outward else { return true }
            switch p.target {
            case .window(let win):
                if inward {
                    if event.flags.contains(.maskAlternate) { wm.quitApp(win) } else { wm.close(win) }
                } else {
                    wm.toggleFullScreen(win)
                }
                chained = nil
            case .dock(let app):
                wm.perform(inward ? .quit : .newWindow, on: app)
            case .menubar:
                break
            }
        }
        return true
    }

    private let pinchThreshold: CGFloat = 0.25

    private func pinchResult(_ t: Target, _ total: CGFloat, flags: CGEventFlags) -> (String, ActionGlyph?) {
        let inward = total <= -pinchThreshold, outward = total >= pinchThreshold
        switch t {
        case .window(let win):
            if inward { return flags.contains(.maskAlternate) ? ("Quit App", .quit) : ("Close Window", .close) }
            if outward { return (wm.isFullScreen(win) ? "Exit Full Screen" : "Enter Full Screen", .fullScreen) }
        case .dock(let app):
            let name = app.localizedName.map { " · \($0)" } ?? ""
            if inward { return ("Quit App" + name, .quit) }
            if outward { return ("New Window" + name, .newWindow) }
        case .menubar:
            break
        }
        return ("", nil)
    }

    // MARK: Double tap (Smart Zoom)

    private func handleSmartMagnify(_ event: CGEvent) -> Bool {
        guard gesture?.strokeActive != true, pinch == nil else { return false }
        let point = event.location
        if let win = wm.titlebarWindow(at: point) {
            haptic()
            let snapped = wm.state(of: win) != nil
            hud.show(origin: .titlebar, gestures: [.doubleTap], action: snapped ? .restore : .center,
                     title: snapped ? "Unsnap" : "Center", at: point, hideAfter: 0.7)
            wm.unsnapOrCenter(win)
            chain(win, at: point)
            return true
        }
        if Prefs.dockGestures, let app = wm.dockApp(at: point) {
            haptic()
            let action = DockAction.hide(others: event.flags.contains(.maskShift))
            hud.show(origin: .dock, gestures: [.doubleTap], action: .hide, title: action.title, at: point, hideAfter: 0.7)
            wm.perform(action, on: app)
            return true
        }
        return false
    }

    // MARK: Keyboard

    /// One snap step on the frontmost window, chaining like repeated presses.
    func keyboardStep(_ dir: Direction, moveScreen: Bool) {
        guard Prefs.enabled, let win = wm.frontmostWindow() else { NSSound.beep(); return }
        let outcome = moveScreen ? .moveScreen(dir) : Grammar.next(from: wm.state(of: win), step: dir, grid: Prefs.grid)
        guard outcome != .none else { return }
        if let f = wm.previewFrame(outcome, for: win), outcome != .minimize { overlay.flash(f, title: "") }
        hud.show(origin: .keyboard, gestures: [.swipe(dir)], action: ActionGlyph(outcome), title: outcome.title,
                 at: NSEvent.mouseLocation.quartz, hideAfter: 0.7)
        wm.apply(outcome, to: win)
    }

    func keyboardCenter() {
        guard Prefs.enabled, let win = wm.frontmostWindow() else { NSSound.beep(); return }
        hud.show(origin: .keyboard, gestures: [], action: .center, title: "Center", at: NSEvent.mouseLocation.quartz, hideAfter: 0.7)
        wm.unsnapOrCenter(win)
    }

    private func haptic() {
        guard Prefs.haptics else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
}

private extension NSPoint {
    /// Cocoa screen point → Quartz (top-left) point.
    var quartz: CGPoint { CGPoint(x: x, y: Screens.primaryHeight - y) }
}
