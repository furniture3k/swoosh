import AppKit
import ApplicationServices

/// Intercepts trackpad scroll / pinch / smart-zoom events through a CGEventTap.
/// When a gesture starts over a window's title bar it is swallowed (the app never
/// sees it) and translated into window actions.
final class GestureEngine {
    private let wm: WindowManager
    private let overlay = Overlay()
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
        let window: AXUIElement
        let screenMove: Bool
        var accX: CGFloat = 0
        var accY: CGFloat = 0
        var lastStep: Direction?
        var state: Layout?
        var outcome: Outcome = .none
        var history: [(Outcome, Layout?)] = []
    }

    private struct Pinch {
        let window: AXUIElement
        var total: CGFloat = 0
        var label: String = ""
    }

    private var swipe: Swipe?
    private var pinch: Pinch?
    private var swallowMomentum = false
    /// The window most recently acted on keeps receiving gestures (even away from
    /// its title bar) for a short time, so swipes can be chained after it moves.
    private var chained: (window: AXUIElement, until: TimeInterval)?

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
        tap = nil; source = nil; swipe = nil; pinch = nil
        overlay.hide()
    }

    // MARK: Dispatch

    private func handle(rawType: UInt32, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        switch rawType {
        case EventType.tapDisabledByTimeout, EventType.tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        default: break
        }
        guard Prefs.enabled else { return pass }

        let consumed: Bool
        switch rawType {
        case EventType.scrollWheel: consumed = handleScroll(event)
        case EventType.magnify: consumed = handleMagnify(event)
        case EventType.smartMagnify: consumed = handleSmartMagnify(event)
        default: consumed = false
        }
        return consumed ? nil : pass
    }

    private func targetWindow(at point: CGPoint) -> AXUIElement? {
        if let c = chained, ProcessInfo.processInfo.systemUptime < c.until, wm.isAlive(c.window) {
            return c.window
        }
        chained = nil
        return wm.titlebarWindow(at: point)
    }

    private func chain(_ win: AXUIElement) {
        let t = Prefs.chainTimeout
        chained = t > 0 ? (win, ProcessInfo.processInfo.systemUptime + t) : nil
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
            guard swipe == nil, pinch == nil, let win = targetWindow(at: event.location) else { return false }
            let screenMove = event.flags.contains(.maskControl)
            swipe = Swipe(window: win, screenMove: screenMove, state: screenMove ? nil : wm.detect(win))
            return true
        case Phase.changed:
            guard swipe != nil else { return false }
            accumulate(event)
            return true
        case Phase.ended, Phase.cancelled:
            guard let s = swipe else { return false }
            swipe = nil
            swallowMomentum = true
            overlay.hide()
            if phase == Phase.ended, s.outcome != .none {
                wm.apply(s.outcome, to: s.window)
                if s.outcome != .minimize { chain(s.window) } else { chained = nil }
            }
            return true
        default:
            return swipe != nil
        }
    }

    private func accumulate(_ event: CGEvent) {
        guard var s = swipe, let ns = NSEvent(cgEvent: event) else { return }
        // Normalise so +x = fingers moving right, +y = fingers moving down,
        // regardless of the natural-scrolling setting.
        let sign: CGFloat = ns.isDirectionInvertedFromDevice ? 1 : -1
        s.accX += ns.scrollingDeltaX * sign
        s.accY += ns.scrollingDeltaY * sign

        let threshold = max(10, Prefs.sensitivity)
        if max(abs(s.accX), abs(s.accY)) >= threshold {
            let dir: Direction = abs(s.accX) > abs(s.accY)
                ? (s.accX > 0 ? .right : .left)
                : (s.accY > 0 ? .down : .up)
            s.accX = 0
            s.accY = 0
            // A long swipe in one direction counts once; a turn registers a new step.
            if dir != s.lastStep {
                s.lastStep = dir
                step(&s, dir)
            }
        }
        swipe = s
    }

    private func step(_ s: inout Swipe, _ dir: Direction) {
        let before = s.outcome
        if s.screenMove {
            s.outcome = .moveScreen(dir)
        } else if s.outcome == .minimize {
            // Swiping back up after a pending minimize undoes it.
            if dir == .up, let (o, st) = s.history.popLast() { s.outcome = o; s.state = st }
        } else {
            let next = Grammar.next(from: s.state, step: dir)
            if next != .none {
                s.history.append((s.outcome, s.state))
                s.outcome = next
                switch next {
                case .layout(let l): s.state = l
                case .restore: s.state = nil
                default: break
                }
            }
        }
        guard s.outcome != before else { return }
        haptic()
        if let frame = wm.previewFrame(s.outcome, for: s.window) {
            overlay.show(frame, title: s.outcome.title)
        } else {
            overlay.hide()
        }
    }

    // MARK: Pinch

    private func handleMagnify(_ event: CGEvent) -> Bool {
        guard let ns = NSEvent(cgEvent: event) else { return false }
        if ns.phase.contains(.began) {
            guard swipe == nil, let win = targetWindow(at: event.location) else { return false }
            pinch = Pinch(window: win)
            return true
        }
        guard var p = pinch else { return false }
        if ns.phase.contains(.changed) {
            p.total += ns.magnification
            let label = pinchLabel(p.total, flags: event.flags)
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

    private func pinchLabel(_ total: CGFloat, flags: CGEventFlags) -> String {
        if total <= -pinchThreshold { return flags.contains(.maskAlternate) ? "Quit App" : "Close Window" }
        if total >= pinchThreshold { return "Toggle Full Screen" }
        return ""
    }

    // MARK: Double tap (Smart Zoom)

    private func handleSmartMagnify(_ event: CGEvent) -> Bool {
        guard swipe == nil, pinch == nil, let win = wm.titlebarWindow(at: event.location) else { return false }
        haptic()
        wm.unsnapOrCenter(win)
        chain(win)
        return true
    }

    private func haptic() {
        guard Prefs.haptics else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
}
