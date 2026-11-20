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
        #expect(Grammar.next(from: .centerThird, step: .up, grid: .sixths) == .layout(.topCenterSixth))
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
                     .bottomLeftSixth, .bottomCenterSixth, .bottomRightSixth: return grid == .sixths
                default: return true
                }
            }
            #expect(Set(expected).isSubset(of: reached), "unreachable in \(grid): \(Set(expected).subtracting(reached))")
        }
    }
}

// MARK: - Swipe session

@Suite("Swipe session")
struct SwipeSessionTests {
    @Test("A single downward swipe on an unsnapped window is one minimize step")
    func singleDown() {
        var s = SwipeSession(origin: nil, threshold: 40)
        for _ in 0..<20 { s.feed(dx: 0, dy: 12) } // one long swipe
        #expect(s.steps == [.down])
        #expect(s.outcome == .minimize)
    }

    @Test("A single downward swipe on a maximized window minimizes (regression)")
    func downFromMaximized() {
        var s = SwipeSession(origin: .maximize, threshold: 40)
        for _ in 0..<10 { s.feed(dx: 0, dy: 10) }
        #expect(s.outcome == .minimize)
    }

    @Test func belowThresholdDoesNothing() {
        var s = SwipeSession(origin: nil, threshold: 50)
        s.feed(dx: 20, dy: 5)
        s.feed(dx: 20, dy: -5)
        #expect(s.steps.isEmpty)
        #expect(s.outcome == .none)
    }

    @Test func turningRegistersSecondStep() {
        var s = SwipeSession(origin: nil, threshold: 40)
        s.feed(dx: -50, dy: 0)
        s.feed(dx: 0, dy: 50)
        #expect(s.steps == [.left, .down])
        #expect(s.outcome == .layout(.bottomLeft))
    }

    @Test("Up then sideways reaches the top quarters (both orders work)")
    func bothOrders() {
        var up = SwipeSession(origin: nil, threshold: 40)
        up.feed(dx: 0, dy: -50)
        up.feed(dx: 50, dy: 0)
        #expect(up.outcome == .layout(.topRight))

        var down = SwipeSession(origin: nil, threshold: 40)
        down.feed(dx: 0, dy: 50)
        down.feed(dx: -50, dy: 0)
        #expect(down.outcome == .layout(.bottomLeft))
    }

    @Test func swipeBackUpUndoesMinimize() {
        var s = SwipeSession(origin: .leftHalf, threshold: 40)
        s.step(.down)           // bottom-left quarter
        s.step(.down)           // bottom half
        s.step(.down)           // minimize
        #expect(s.outcome == .minimize)
        s.step(.up)
        #expect(s.outcome == .layout(.bottomHalf))
    }

    @Test func diagonalPicksDominantAxis() {
        var s = SwipeSession(origin: nil, threshold: 40)
        s.feed(dx: 30, dy: 45)
        #expect(s.steps == [.down])
    }

    @Test func screenAndMenubarModes() {
        var screen = SwipeSession(mode: .screenMove, origin: nil, threshold: 40)
        screen.feed(dx: 60, dy: 0)
        #expect(screen.outcome == .moveScreen(.right))

        var menu = SwipeSession(mode: .menubar, origin: nil, threshold: 40)
        menu.feed(dx: 0, dy: 60)
        #expect(menu.outcome == .minimizeAll)
        menu.feed(dx: 0, dy: -60)
        #expect(menu.outcome == .unminimizeAll)
    }

    @Test func thresholdHasFloor() {
        let s = SwipeSession(origin: nil, threshold: 0)
        #expect(s.threshold == 10)
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
