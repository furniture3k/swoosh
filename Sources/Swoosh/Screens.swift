import AppKit
import SwooshCore

/// NSScreen helpers in global top-left (Quartz / AX) coordinates.
enum Screens {
    static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    static func flip(_ r: CGRect) -> CGRect { Geometry.flip(r, primaryHeight: primaryHeight) }
    static func fullArea(_ screen: NSScreen) -> CGRect { flip(screen.frame) }
    static func visibleArea(_ screen: NSScreen) -> CGRect { flip(screen.visibleFrame) }

    /// Area windows snap into: the visible frame minus the Stage Manager strip.
    static func workArea(_ screen: NSScreen) -> CGRect {
        let visible = visibleArea(screen)
        guard SystemState.stageManagerStripVisible else { return visible }
        return Geometry.workArea(visible: visible, stageManagerInset: Prefs.stageManagerOffset)
    }

    static func screen(for rect: CGRect) -> NSScreen {
        let screens = NSScreen.screens
        guard let i = Geometry.bestIndex(for: rect, in: screens.map(fullArea)) else {
            return NSScreen.main ?? screens[0]
        }
        return screens[i]
    }

    static func screen(containing point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { fullArea($0).contains(point) }
    }

    static func neighbor(of screen: NSScreen, _ direction: Direction) -> NSScreen? {
        let screens = NSScreen.screens
        return Geometry.neighbor(of: fullArea(screen), in: screens.map(fullArea), direction).map { screens[$0] }
    }

    /// The menu bar strip of the screen under `point`, if the point is in it.
    static func menuBarScreen(at point: CGPoint) -> NSScreen? {
        guard let s = screen(containing: point) else { return nil }
        let strip = Geometry.menuBarStrip(full: fullArea(s), visible: visibleArea(s))
        return !strip.isNull && strip.contains(point) ? s : nil
    }
}
