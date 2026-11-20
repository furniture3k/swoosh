import AppKit
import SwooshCore

/// The live tooltip next to the pointer: where the gesture started, what the
/// fingers did and what will happen, e.g. [title bar] [← ↑] › [▘ quarter] Top Left.
final class GestureHUD {
    private let panel: NSPanel
    private let effect = NSVisualEffectView()
    private let stack = NSStackView()
    private var visible = false
    private var hideWork: DispatchWorkItem?

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        panel.appearance = NSAppearance(named: .vibrantDark)

        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 11
        effect.layer?.masksToBounds = true

        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 9, bottom: 6, right: 11)
        stack.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            stack.topAnchor.constraint(equalTo: effect.topAnchor),
            stack.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        panel.contentView = effect
    }

    /// Shows or updates the tooltip. `point` is the pointer in Quartz coordinates.
    func show(origin: OriginGlyph, gestures: [GestureGlyph], action: ActionGlyph?, title: String,
              at point: CGPoint, hideAfter: TimeInterval? = nil) {
        guard Prefs.showTooltip else { return }
        hideWork?.cancel()

        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        stack.addArrangedSubview(icon(GestureIcons.origin(origin), alpha: 0.6))
        for g in gestures.suffix(4) { stack.addArrangedSubview(icon(GestureIcons.gesture(g))) }
        if let action {
            let chevron = NSTextField(labelWithString: "›")
            chevron.font = .systemFont(ofSize: 15, weight: .medium)
            chevron.textColor = .tertiaryLabelColor
            stack.addArrangedSubview(chevron)
            let actionIcon = icon(GestureIcons.action(action))
            actionIcon.contentTintColor = .controlAccentColor
            stack.addArrangedSubview(actionIcon)
        }
        if !title.isEmpty {
            let label = NSTextField(labelWithString: title)
            label.font = .systemFont(ofSize: 13, weight: .semibold)
            label.textColor = .labelColor
            stack.addArrangedSubview(label)
        }

        let size = stack.fittingSize
        // Below-right of the pointer, kept on the pointer's screen.
        let cocoa = NSPoint(x: point.x, y: Screens.primaryHeight - point.y)
        let screen = NSScreen.screens.first { $0.frame.contains(cocoa) } ?? NSScreen.main
        var origin = NSPoint(x: cocoa.x + 16, y: cocoa.y - 22 - size.height)
        if let vf = screen?.visibleFrame {
            origin.x = min(max(origin.x, vf.minX + 4), vf.maxX - size.width - 4)
            if origin.y < vf.minY + 4 { origin.y = cocoa.y + 22 }
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        if !visible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { $0.duration = 0.08; panel.animator().alphaValue = 1 }
            visible = true
        }
        if let hideAfter {
            let work = DispatchWorkItem { [weak self] in self?.hide() }
            hideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + hideAfter, execute: work)
        }
    }

    func hide() {
        hideWork?.cancel()
        hideWork = nil
        guard visible else { return }
        visible = false
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.15; panel.animator().alphaValue = 0 },
                                             completionHandler: { [weak self] in
            guard let self, !self.visible else { return }
            self.panel.orderOut(nil)
        })
    }

    private func icon(_ image: NSImage, alpha: CGFloat = 1) -> NSImageView {
        let v = NSImageView(image: image)
        v.contentTintColor = NSColor.labelColor.withAlphaComponent(alpha)
        v.setContentHuggingPriority(.required, for: .horizontal)
        return v
    }
}
