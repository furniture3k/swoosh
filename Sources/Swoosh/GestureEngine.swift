import AppKit
import ApplicationServices
import SwooshCore

/// Intercepts trackpad scroll / pinch / smart-zoom events through a CGEventTap.
/// When a gesture starts over a window's title bar (or the menu bar) it is
/// swallowed, so the app never sees it, and turned into window actions.
final class GestureEngine {
    private let wm: WindowManager
    let overlay = Overlay()
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

    private struct Swipe {
        var session: SwipeSession
        let window: AXUIElement?
        let screen: NSScreen?
    }

    private struct Pinch {
        let window: AXUIElement
        var total: CGFloat = 0
        var label = ""
    }

    private var swipe: Swipe?
    private var pinch: Pinch?
    private var swallowMomentum = false
    /// The window most recently acted on keeps receiving gestures (even away
    /// from its title bar) for a moment, while the pointer stays put, so swipes
    /// can be chained after the window moves out from under the pointer.
    private var chained: (window: AXUIElement, anchor: CGPoint, until: TimeInterval)?

    init(windowManager: WindowManager) { wm = windowManager }

    var isRunning: Bool { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

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
        tap = nil; source = nil; swipe = nil; pinch = nil; chained = nil
        overlay.hide()
    }

    // MARK: Dispatch

    private func handle(rawType: UInt32, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        switch rawType {
        case EventType.tapDisabledByTimeout, EventType.tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            // Whatever was in flight is lost; don't leave a stale preview behind.
            swipe = nil; pinch = nil
            overlay.hide()
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

    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    private func targetWindow(at point: CGPoint, allowFullScreen: Bool = false) -> AXUIElement? {
        if let c = chained, TitlebarPolicy.chainApplies(pointer: point, anchor: c.anchor, now: now, until: c.until),
           wm.isAlive(c.window) {
            return c.window
        }
        chained = nil
        return wm.titlebarWindow(at: point, allowFullScreen: allowFullScreen)
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
            return false
        case Phase.began:
            swallowMomentum = false
            guard swipe == nil, pinch == nil else { return swipe != nil }
            return beginSwipe(event)
        case Phase.changed:
            guard swipe != nil else { return false }
            accumulate(event)
            return true
        case Phase.ended, Phase.cancelled:
            guard let s = swipe else { return false }
            swipe = nil
            swallowMomentum = true
            overlay.hide()
            if phase == Phase.ended { finish(s, at: event.location) }
            return true
        default:
            return swipe != nil
        }
    }

    private func beginSwipe(_ event: CGEvent) -> Bool {
        let point = event.location
        let threshold = Prefs.sensitivity
        if let win = targetWindow(at: point) {
            let screenMove = event.flags.contains(.maskControl)
            let session = SwipeSession(mode: screenMove ? .screenMove : .window,
                                       origin: screenMove ? nil : wm.state(of: win),
                                       grid: Prefs.grid, threshold: threshold)
            swipe = Swipe(session: session, window: win, screen: nil)
            return true
        }
        if Prefs.menubarGestures, let screen = Screens.menuBarScreen(at: point) {
            swipe = Swipe(session: SwipeSession(mode: .menubar, origin: nil, threshold: threshold),
                          window: nil, screen: screen)
            return true
        }
        return false
    }

    private func accumulate(_ event: CGEvent) {
        guard var s = swipe, let ns = NSEvent(cgEvent: event) else { return }
        // Normalise so +x = fingers right, +y = fingers down, whatever the
        // natural-scrolling setting.
        let sign: CGFloat = ns.isDirectionInvertedFromDevice ? 1 : -1
        let before = s.session.outcome
        s.session.feed(dx: ns.scrollingDeltaX * sign, dy: ns.scrollingDeltaY * sign)
        swipe = s
        if s.session.outcome != before { showPreview(for: s) }
    }

    private func showPreview(for s: Swipe) {
        haptic()
        let outcome = s.session.outcome
        if let screen = s.screen {
            guard outcome != .none else { overlay.hide(); return }
            overlay.show(Screens.visibleArea(screen), title: outcome.title)
        } else if let frame = wm.previewFrame(outcome, for: s.window) {
            overlay.show(frame, title: outcome.title)
        } else if case .moveScreen = outcome, let f = s.window?.frame {
            overlay.show(f, title: "No Screen There")
        } else {
            overlay.hide()
        }
    }

    private func finish(_ s: Swipe, at point: CGPoint) {
        let outcome = s.session.outcome
        if let screen = s.screen {
            switch outcome {
            case .minimizeAll: wm.minimizeAll(on: screen)
            case .unminimizeAll: wm.unminimizeAll(on: screen)
            default: break
            }
            return
        }
        guard let win = s.window else { return }
        if outcome == .none {
            // Nothing happened, but keep the chain alive for a retry.
            if chained != nil { chain(win, at: point) }
            return
        }
        wm.apply(outcome, to: win)
        if outcome == .minimize { chained = nil } else { chain(win, at: point) }
    }

    // MARK: Pinch

    private func handleMagnify(_ event: CGEvent) -> Bool {
        guard let ns = NSEvent(cgEvent: event) else { return false }
        if ns.phase.contains(.began) {
            guard swipe == nil, let win = targetWindow(at: event.location, allowFullScreen: true) else { return false }
            pinch = Pinch(window: win)
            return true
        }
        guard var p = pinch else { return false }
        if ns.phase.contains(.changed) {
            p.total += ns.magnification
            let label = pinchLabel(p, flags: event.flags)
            if label != p.label {
                p.label = label
                if label.isEmpty { overlay.hide() } else if let f = p.window.frame {
                    haptic()
                    overlay.show(f, title: label)
                }
            }
            pinch = p
        } else if ns.phase.contains(.ended) || ns.phase.contains(.cancelled) {
            pinch = nil
            overlay.hide()
            guard ns.phase.contains(.ended) else { return true }
            if p.total <= -pinchThreshold {
                if event.flags.contains(.maskAlternate) { wm.quitApp(p.window) } else { wm.close(p.window) }
                chained = nil
            } else if p.total >= pinchThreshold {
                wm.toggleFullScreen(p.window)
                chained = nil
            }
        }
        return true
    }

    private let pinchThreshold: CGFloat = 0.25

    private func pinchLabel(_ p: Pinch, flags: CGEventFlags) -> String {
        if p.total <= -pinchThreshold { return flags.contains(.maskAlternate) ? "Quit App" : "Close Window" }
        if p.total >= pinchThreshold { return wm.isFullScreen(p.window) ? "Exit Full Screen" : "Enter Full Screen" }
        return ""
    }

    // MARK: Double tap (Smart Zoom)

    private func handleSmartMagnify(_ event: CGEvent) -> Bool {
        guard swipe == nil, pinch == nil, let win = wm.titlebarWindow(at: event.location) else { return false }
        haptic()
        wm.unsnapOrCenter(win)
        chain(win, at: event.location)
        return true
    }

    // MARK: Keyboard

    /// One snap step on the frontmost window, chaining like repeated swipes.
    func keyboardStep(_ dir: Direction, moveScreen: Bool) {
        guard Prefs.enabled, let win = wm.frontmostWindow() else { NSSound.beep(); return }
        var session = SwipeSession(mode: moveScreen ? .screenMove : .window,
                                   origin: moveScreen ? nil : wm.state(of: win), grid: Prefs.grid)
        session.step(dir)
        let outcome = session.outcome
        guard outcome != .none else { return }
        if let f = wm.previewFrame(outcome, for: win), outcome != .minimize { overlay.flash(f, title: outcome.title) }
        wm.apply(outcome, to: win)
    }

    func keyboardCenter() {
        guard Prefs.enabled, let win = wm.frontmostWindow() else { NSSound.beep(); return }
        wm.unsnapOrCenter(win)
    }

    private func haptic() {
        guard Prefs.haptics else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
}
