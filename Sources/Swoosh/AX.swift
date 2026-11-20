import AppKit
import ApplicationServices

/// Thin helpers over the Accessibility C API.
extension AXUIElement {
    static let systemWide: AXUIElement = {
        let el = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(el, 0.25)
        return el
    }()

    /// Element under a point in global (top-left origin) coordinates.
    static func element(at point: CGPoint) -> AXUIElement? {
        var el: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &el) == .success else {
            return nil
        }
        return el
    }

    func raw(_ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, name as CFString, &value) == .success else { return nil }
        return value
    }

    func element(_ name: String) -> AXUIElement? {
        guard let v = raw(name), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    func string(_ name: String) -> String? { raw(name) as? String }
    func bool(_ name: String) -> Bool? { (raw(name) as? NSNumber)?.boolValue }

    var role: String? { string("AXRole") }
    var subrole: String? { string("AXSubrole") }
    var parent: AXUIElement? { element("AXParent") }

    var pid: pid_t? {
        var p: pid_t = 0
        return AXUIElementGetPid(self, &p) == .success ? p : nil
    }

    private func axValue(_ name: String) -> AXValue? {
        guard let v = raw(name), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        return (v as! AXValue)
    }

    var position: CGPoint? {
        guard let v = axValue("AXPosition") else { return nil }
        var p = CGPoint.zero
        return AXValueGetValue(v, .cgPoint, &p) ? p : nil
    }

    var size: CGSize? {
        guard let v = axValue("AXSize") else { return nil }
        var s = CGSize.zero
        return AXValueGetValue(v, .cgSize, &s) ? s : nil
    }

    /// Frame in global top-left-origin coordinates.
    var frame: CGRect? {
        guard let p = position, let s = size else { return nil }
        return CGRect(origin: p, size: s)
    }

    @discardableResult
    func set(_ name: String, _ value: CFTypeRef) -> Bool {
        AXUIElementSetAttributeValue(self, name as CFString, value) == .success
    }

    func setPosition(_ point: CGPoint) {
        var p = point
        if let v = AXValueCreate(.cgPoint, &p) { set("AXPosition", v) }
    }

    func setSize(_ size: CGSize) {
        var s = size
        if let v = AXValueCreate(.cgSize, &s) { set("AXSize", v) }
    }

    /// Size → position → size: the second resize corrects for windows that were
    /// clamped by the screen edge while still at their old position.
    func setFrame(_ rect: CGRect) {
        setSize(rect.size)
        setPosition(rect.origin)
        setSize(rect.size)
    }

    @discardableResult
    func perform(_ action: String) -> Bool {
        AXUIElementPerformAction(self, action as CFString) == .success
    }

    /// Walks up to the containing AXWindow.
    func windowAncestor() -> AXUIElement? {
        if role == "AXWindow" { return self }
        if let w = element("AXWindow") { return w }
        var current: AXUIElement? = parent
        for _ in 0..<40 {
            guard let c = current else { return nil }
            if c.role == "AXWindow" { return c }
            current = c.parent
        }
        return nil
    }

    /// Roles from self upward, stopping before `ancestor`.
    func roles(upTo ancestor: AXUIElement) -> [String] {
        var out: [String] = []
        var current: AXUIElement? = self
        for _ in 0..<40 {
            guard let c = current, !CFEqual(c, ancestor) else { break }
            if let r = c.role { out.append(r) }
            current = c.parent
        }
        return out
    }

    /// Windows of an application element.
    var windows: [AXUIElement] {
        guard let arr = raw("AXWindows") as? [AnyObject] else { return [] }
        return arr.compactMap { item in
            CFGetTypeID(item) == AXUIElementGetTypeID() ? (item as! AXUIElement) : nil
        }
    }
}
