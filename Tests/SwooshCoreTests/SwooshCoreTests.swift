import CoreGraphics
import Testing
@testable import SwooshCore

private let area = CGRect(x: 0, y: 25, width: 1440, height: 875)

// MARK: - Grammar

@Suite("Swipe grammar")
struct GrammarTests {
    @Test("Swipe down minimizes immediately from unsnapped and maximized windows (regression)")
    func downMinimizes() {
        #expect(Grammar.next(from: nil, step: .down) == .minimize)
        #expect(Grammar.next(from: .maximize, step: .down) == .minimize)
        #expect(Grammar.next(from: .almostMaximize, step: .down) == .minimize)
    }

    @Test func basicSnaps() {
        #expect(Grammar.next(from: nil, step: .left) == .layout(.leftHalf))
        #expect(Grammar.next(from: nil, step: .right) == .layout(.rightHalf))
        #expect(Grammar.next(from: nil, step: .up) == .layout(.maximize))
    }

    @Test func halvesToThirdsCycle() {
        var s: Layout? = nil
        var seen: [Layout] = []
        for _ in 0..<4 {
            guard case .layout(let l) = Grammar.next(from: s, step: .left) else { Issue.record("no layout"); return }
            s = l
            seen.append(l)
        }
        #expect(seen == [.leftHalf, .leftThird, .leftTwoThirds, .leftHalf])
    }

    @Test func quartersFromHalves() {
        #expect(Grammar.next(from: .leftHalf, step: .up) == .layout(.topLeft))
        #expect(Grammar.next(from: .rightHalf, step: .down) == .layout(.bottomRight))
    }

    @Test func sixthsAndNinthsFromThirds() {
        #expect(Grammar.next(from: .centerThird, step: .up, grid: .thirds) == .layout(.topCenterSixth))
        #expect(Grammar.next(from: .centerThird, step: .up, grid: .ninths) == .layout(.ninth(col: 1, row: 0)))
        #expect(Grammar.next(from: .rightThird, step: .down, grid: .ninths) == .layout(.ninth(col: 2, row: 2)))
    }

    @Test func ninthsWalkGrid() {
        #expect(Grammar.next(from: .ninth(col: 0, row: 0), step: .down) == .layout(.ninth(col: 0, row: 1)))
        #expect(Grammar.next(from: .ninth(col: 0, row: 1), step: .right) == .layout(.ninth(col: 1, row: 1)))
        #expect(Grammar.next(from: .ninth(col: 0, row: 0), step: .up) == .layout(.leftThird))
        #expect(Grammar.next(from: .ninth(col: 0, row: 1), step: .left) == .none)
    }

    @Test("Every state has a defined result for every direction and never leaves the grid")
    func totality() {
        for state in Layout.allCases {
            for dir in Direction.allCases {
                for grid in Grid.allCases {
                    let o = Grammar.next(from: state, step: dir, grid: grid)
                    if case .layout(let l) = o { #expect(Layout.allCases.contains(l)) }
                    #expect(o != .restore, "grammar should not shrink a window via restore")
                }
            }
        }
    }

    @Test("Every layout is reachable by swipes from an unsnapped window")
    func reachability() {
        for grid in Grid.allCases {
            var reached: Set<Layout> = []
            var frontier: [Layout?] = [nil]
            var visited: Set<String> = []
            while let s = frontier.popLast() {
                let key = s.map { "\($0)" } ?? "nil"
                if visited.contains(key) { continue }
                visited.insert(key)
                for d in Direction.allCases {
                    if case .layout(let l) = Grammar.next(from: s, step: d, grid: grid) {
                        reached.insert(l)
                        frontier.append(l)
                    }
                }
            }
            let expected = Layout.allCases.filter { l in
                switch l {
                case .ninth: return grid == .ninths
                case .topLeftSixth, .topCenterSixth, .topRightSixth,
                     .bottomLeftSixth, .bottomCenterSixth, .bottomRightSixth: return grid != .ninths
                default: return true
                }
            }
            #expect(Set(expected).isSubset(of: reached), "unreachable in \(grid): \(Set(expected).subtracting(reached))")
        }
    }
}

// MARK: - Swish gesture rules

private func resolve(_ steps: [Direction], origin: Layout? = nil, grid: Grid = .halves, hold: Bool = false,
                     almost: Bool = false, fullScreen: Bool = false, screens: Set<Direction> = []) -> Outcome {
    Resolver.resolve(steps, GestureContext(origin: origin, grid: grid, upFillsAlmost: almost, hold: hold,
                                           isFullScreen: fullScreen, screens: screens))
}

@Suite("Swish gesture rules")
struct ResolverTests {
    @Test("Half, then a new swipe up, fills the screen (regression: went to a corner)")
    func halfThenUpMaximizes() {
        #expect(resolve([.up], origin: .leftHalf) == .layout(.maximize))
        #expect(resolve([.up], origin: .topLeft) == .layout(.maximize))
        #expect(resolve([.up], origin: .rightThird, grid: .thirds) == .layout(.maximize))
    }

    @Test("Swipe down once minimizes from any state")
    func downMinimizes() {
        for origin in [nil, .maximize, .leftHalf, .topRight, .almostMaximize] as [Layout?] {
            #expect(resolve([.down], origin: origin) == .minimize)
        }
    }

    @Test func halves() {
        #expect(resolve([.left]) == .layout(.leftHalf))
        #expect(resolve([.right], origin: .leftHalf) == .layout(.rightHalf))
        #expect(resolve([.left, .left]) == .layout(.leftHalf))
    }

    @Test("Quarters: horizontal and vertical in one gesture, both orders")
    func quartersBothOrders() {
        #expect(resolve([.left, .up]) == .layout(.topLeft))
        #expect(resolve([.up, .left]) == .layout(.topLeft))
        #expect(resolve([.right, .down]) == .layout(.bottomRight))
        #expect(resolve([.down, .right]) == .layout(.bottomRight))
    }

    @Test("Swipe up twice: top half. Hold, then swipe down: bottom half")
    func verticalHalves() {
        #expect(resolve([.up, .up]) == .layout(.topHalf))
        #expect(resolve([.down], hold: true) == .layout(.bottomHalf))
        #expect(resolve([.down], origin: .leftThird, grid: .thirds, hold: true) == .layout(.bottomLeftSixth))
    }

    @Test func almostMaximizeSetting() {
        #expect(resolve([.up], almost: true) == .layout(.almostMaximize))
    }

    @Test("Tap and hold, then swipe up: full screen")
    func holdUpFullScreen() {
        #expect(resolve([.up], hold: true) == .toggleFullScreen)
        #expect(resolve([.down], fullScreen: true) == .toggleFullScreen)
        #expect(resolve([.left], fullScreen: true) == .none)
    }

    @Test("Swiping toward the side a half already occupies moves it to the next screen")
    func halfToNextScreen() {
        #expect(resolve([.left], origin: .leftHalf, screens: [.left]) == .layoutOnScreen(.rightHalf, .left))
        #expect(resolve([.left], origin: .leftHalf, screens: [.right]) == .layout(.leftHalf))
    }

    @Test("3×2: thirds toggle with two thirds; hold or both sides gives the middle third")
    func thirds() {
        #expect(resolve([.left], grid: .thirds) == .layout(.leftThird))
        #expect(resolve([.left], origin: .leftThird, grid: .thirds) == .layout(.leftTwoThirds))
        #expect(resolve([.left], origin: .leftTwoThirds, grid: .thirds) == .layout(.leftThird))
        #expect(resolve([.left, .left], grid: .thirds) == .layout(.leftTwoThirds))
        #expect(resolve([.right], grid: .thirds, hold: true) == .layout(.centerThird))
        #expect(resolve([.left, .right], grid: .thirds) == .layout(.centerThird))
    }

    @Test("3×2: sixths from combined swipes, or double swipe on a third")
    func sixths() {
        #expect(resolve([.left, .up], grid: .thirds) == .layout(.topLeftSixth))
        #expect(resolve([.down, .right], grid: .thirds) == .layout(.bottomRightSixth))
        #expect(resolve([.up, .up], origin: .centerThird, grid: .thirds) == .layout(.topCenterSixth))
        #expect(resolve([.up], origin: .centerThird, grid: .thirds) == .layout(.maximize))
        #expect(resolve([.down], origin: .centerThird, grid: .thirds) == .minimize)
    }

    @Test("3×3: every ninth is reachable")
    func ninths() {
        var reached: Set<Layout> = []
        let sides: [[Direction]] = [[.left], [.right], [.left, .right]]
        let rows: [[Direction]] = [[.up], [.down], [.up, .down]]
        for h in sides { for v in rows { if case .layout(let l) = resolve(h + v, grid: .ninths) { reached.insert(l) } } }
        for c in 0..<3 { for r in 0..<3 { #expect(reached.contains(.ninth(col: c, row: r)), "missing \(c),\(r)") } }
    }

    @Test("Minimize ends the gesture immediately (regression: minimize was delayed)")
    func minimizeIsImmediate() {
        #expect(Resolver.endsGesture(.minimize))
        #expect(Resolver.endsGesture(.toggleFullScreen))
        #expect(!Resolver.endsGesture(.layout(.maximize)))
        var s = SwipeSession(origin: nil, threshold: 40)
        s.feed(dx: 0, dy: 60)
        #expect(s.endsOnLift)
    }

    @Test func dockActions() {
        #expect(DockAction.swipe(.up, secondary: false) == .unminimize(all: false))
        #expect(DockAction.swipe(.up, secondary: true) == .unminimize(all: true))
        #expect(DockAction.swipe(.down, secondary: false) == .minimize(all: false))
        #expect(DockAction.swipe(.right, secondary: false) == .cycle(forward: true))
    }

    @Test func gridMigration() {
        #expect(Grid(stored: "sixths") == .thirds)
        #expect(Grid(stored: nil) == .halves)
        #expect(Grid(stored: "ninths") == .ninths)
        #expect(Grid(stored: "junk") == .halves)
    }
}

// MARK: - Swipe session

@Suite("Swipe session")
struct SwipeSessionTests {
    @Test("One long swipe down is one step: minimize")
    func singleDown() {
        var s = SwipeSession(origin: nil, threshold: 40)
        for _ in 0..<20 { s.feed(dx: 0, dy: 12) }
        #expect(s.steps == [.down])
        #expect(s.outcome == .minimize)
    }

    @Test func belowThresholdDoesNothing() {
        var s = SwipeSession(origin: nil, threshold: 50)
        s.feed(dx: 20, dy: 5)
        s.feed(dx: 20, dy: -5)
        #expect(s.steps.isEmpty)
        #expect(s.outcome == .none)
    }

    @Test("Turning mid-swipe adds a step: quarter")
    func turning() {
        var s = SwipeSession(origin: nil, threshold: 40)
        s.feed(dx: -50, dy: 0)
        s.feed(dx: 0, dy: 50)
        #expect(s.steps == [.left, .down])
        #expect(s.outcome == .layout(.bottomLeft))
    }

    @Test("A second stroke in the same direction counts (double swipe)")
    func doubleSwipeAcrossStrokes() {
        var s = SwipeSession(origin: nil, threshold: 40)
        s.feed(dx: 0, dy: -60)
        #expect(s.outcome == .layout(.maximize))
        s.beginStroke()
        s.feed(dx: 0, dy: -60)
        #expect(s.steps == [.up, .up])
        #expect(s.outcome == .layout(.topHalf))
        #expect(s.strokes == 2)
    }

    @Test func diagonalPicksDominantAxis() {
        var s = SwipeSession(origin: nil, threshold: 40)
        s.feed(dx: 30, dy: 45)
        #expect(s.steps == [.down])
    }

    @Test func otherModes() {
        var screen = SwipeSession(mode: .screenMove, threshold: 40)
        screen.feed(dx: 60, dy: 0)
        #expect(screen.outcome == .moveScreen(.right))

        var menu = SwipeSession(mode: .menubar, threshold: 40)
        menu.feed(dx: 0, dy: 60)
        #expect(menu.outcome == .minimizeAll)
        menu.feed(dx: 0, dy: -60)
        #expect(menu.outcome == .unminimizeAll)

        var dock = SwipeSession(mode: .dock(secondary: false), threshold: 40)
        dock.feed(dx: 0, dy: -60)
        #expect(dock.dockAction == .unminimize(all: false))
        #expect(dock.outcome == .none)
    }

    @Test func thresholdHasFloor() {
        #expect(SwipeSession(origin: nil, threshold: 0).threshold == 10)
    }
}

// MARK: - Geometry

@Suite("Geometry")
struct GeometryTests {
    @Test func halvesTileExactlyWithoutGap() {
        let l = Layout.leftHalf.rect(in: area, gap: 0)
        let r = Layout.rightHalf.rect(in: area, gap: 0)
        #expect(l.maxX == r.minX)
        #expect(l.minX == area.minX && r.maxX == area.maxX)
        #expect(l.height == area.height)
    }

    @Test func gapIsUniform() {
        let g: CGFloat = 10
        let l = Layout.leftHalf.rect(in: area, gap: g)
        let r = Layout.rightHalf.rect(in: area, gap: g)
        #expect(abs(l.minX - area.minX - g) <= 1)
        #expect(abs((r.minX - l.maxX) - g) <= 1)
        #expect(abs(area.maxX - r.maxX - g) <= 1)
    }

    @Test func detectRoundTrips() {
        for gap in [CGFloat(0), 8] {
            for l in Layout.allCases {
                #expect(Geometry.detect(frame: l.rect(in: area, gap: gap), area: area, gap: gap) == l, "\(l) gap \(gap)")
            }
        }
        #expect(Geometry.detect(frame: CGRect(x: 100, y: 100, width: 700, height: 500), area: area, gap: 0) == nil)
    }

    @Test func flipIsInvolution() {
        let r = CGRect(x: 10, y: 20, width: 300, height: 200)
        #expect(Geometry.flip(Geometry.flip(r, primaryHeight: 900), primaryHeight: 900) == r)
        #expect(Geometry.flip(r, primaryHeight: 900).minY == 680)
    }

    @Test func neighborScreens() {
        let main = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let right = CGRect(x: 1440, y: -100, width: 1920, height: 1080)
        let above = CGRect(x: 0, y: -1080, width: 1920, height: 1080)
        let screens = [main, right, above]
        #expect(Geometry.neighbor(of: main, in: screens, .right) == 1)
        #expect(Geometry.neighbor(of: main, in: screens, .up) == 2)
        #expect(Geometry.neighbor(of: main, in: screens, .left) == nil)
        #expect(Geometry.neighbor(of: right, in: screens, .left) == 0)
    }

    @Test func mapKeepsProportionAndStaysInside() {
        let a = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let b = CGRect(x: 1000, y: 0, width: 2000, height: 1600)
        let m = Geometry.map(CGRect(x: 500, y: 0, width: 500, height: 800), from: a, to: b)
        #expect(m == CGRect(x: 2000, y: 0, width: 1000, height: 1600))
        let big = Geometry.map(CGRect(x: 900, y: 700, width: 900, height: 900), from: a, to: a)
        #expect(a.contains(big))
    }

    @Test func restoreFrame() {
        let saved = CGRect(x: 200, y: 200, width: 800, height: 600)
        #expect(Geometry.restoreFrame(saved: saved, area: area) == saved)
        let offscreen = CGRect(x: 5000, y: 200, width: 800, height: 600)
        let r = Geometry.restoreFrame(saved: offscreen, area: area)
        #expect(area.contains(r) && r.size == offscreen.size)
        let dflt = Geometry.restoreFrame(saved: nil, area: area)
        #expect(area.contains(dflt))
    }

    @Test func stageManagerInset() {
        let w = Geometry.workArea(visible: area, stageManagerInset: 120)
        #expect(w.minX == 120 && w.maxX == area.maxX)
        let capped = Geometry.workArea(visible: area, stageManagerInset: 5000)
        #expect(capped.width >= area.width * 2 / 3 - 1)
    }

    @Test func menuBarStrip() {
        let full = CGRect(x: 0, y: 0, width: 1440, height: 900)
        #expect(Geometry.menuBarStrip(full: full, visible: area).height == 25)
        #expect(Geometry.menuBarStrip(full: full, visible: full).isNull)
    }

    @Test func bestIndexHandlesOffscreen() {
        let rects = [CGRect(x: 0, y: 0, width: 100, height: 100), CGRect(x: 100, y: 0, width: 100, height: 100)]
        #expect(Geometry.bestIndex(for: CGRect(x: 120, y: 10, width: 50, height: 50), in: rects) == 1)
        #expect(Geometry.bestIndex(for: CGRect(x: 900, y: 10, width: 10, height: 10), in: rects) == 1)
    }
}

// MARK: - Policy

@Suite("Title bar policy")
struct PolicyTests {
    @Test func titleBarZone() {
        #expect(TitlebarPolicy.accepts(offsetY: 10, windowHeight: 600, baseHeight: 40, ancestorRoles: ["AXStaticText"], hitIsWindow: false))
        #expect(!TitlebarPolicy.accepts(offsetY: 200, windowHeight: 600, baseHeight: 40, ancestorRoles: ["AXGroup"], hitIsWindow: false))
        #expect(!TitlebarPolicy.accepts(offsetY: -5, windowHeight: 600, baseHeight: 40, ancestorRoles: [], hitIsWindow: true))
    }

    @Test func toolbarExtendsZone() {
        #expect(TitlebarPolicy.accepts(offsetY: 80, windowHeight: 600, baseHeight: 40, ancestorRoles: ["AXButton", "AXToolbar"], hitIsWindow: false))
        #expect(!TitlebarPolicy.accepts(offsetY: 80, windowHeight: 600, baseHeight: 40, ancestorRoles: ["AXButton", "AXGroup"], hitIsWindow: false))
    }

    @Test("Sliders and scroll bars in the title area keep their own scrolling")
    func slidersBlocked() {
        #expect(!TitlebarPolicy.accepts(offsetY: 20, windowHeight: 600, baseHeight: 40, ancestorRoles: ["AXValueIndicator", "AXSlider", "AXToolbar"], hitIsWindow: false))
        #expect(!TitlebarPolicy.accepts(offsetY: 20, windowHeight: 600, baseHeight: 40, ancestorRoles: ["AXRadioButton", "AXScrollArea"], hitIsWindow: false))
    }

    @Test("Web apps that nest everything in a scroll area still get title bar gestures")
    func deepScrollAreaAllowed() {
        #expect(TitlebarPolicy.accepts(offsetY: 20, windowHeight: 600, baseHeight: 40,
                                       ancestorRoles: ["AXStaticText", "AXGroup", "AXGroup", "AXWebArea", "AXScrollArea"], hitIsWindow: false))
    }

    @Test func chainRequiresStillPointer() {
        let anchor = CGPoint(x: 100, y: 100)
        #expect(TitlebarPolicy.chainApplies(pointer: CGPoint(x: 110, y: 105), anchor: anchor, now: 1, until: 2))
        #expect(!TitlebarPolicy.chainApplies(pointer: CGPoint(x: 400, y: 100), anchor: anchor, now: 1, until: 2))
        #expect(!TitlebarPolicy.chainApplies(pointer: anchor, anchor: anchor, now: 3, until: 2))
    }
}

@Suite("Settings helpers")
struct SettingsTests {
    @Test func hotkeySchemes() {
        #expect(HotkeyScheme.off.keyCodes.isEmpty)
        for scheme in HotkeyScheme.allCases where scheme != .off {
            #expect(Set(scheme.keyCodes.map(\.direction)) == Set(Direction.allCases))
            #expect(Set(scheme.keyCodes.map(\.code)).count == 4)
        }
    }

    @Test func trackpadRequirement() {
        #expect(TrackpadRequirement.pinch.isEnabled(in: [nil, nil]))
        #expect(!TrackpadRequirement.pinch.isEnabled(in: [["TrackpadPinch": 0], ["TrackpadPinch": false]]))
        #expect(TrackpadRequirement.smartZoom.isEnabled(in: [["TrackpadTwoFingerDoubleTapGesture": 0], ["TrackpadTwoFingerDoubleTapGesture": 1]]))
    }
}
