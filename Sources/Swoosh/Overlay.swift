import AppKit

/// Translucent preview of where a window will land, shown while a gesture is
/// in progress.
final class Overlay {
    private let window: NSWindow
    private let box = NSView()
    private let label = NSTextField(labelWithString: "")
    private let pill = NSVisualEffectView()
    private var visible = false

    init() {
        window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]

        box.wantsLayer = true
        box.layer?.cornerRadius = 12
        box.layer?.borderWidth = 2
        box.autoresizingMask = [.width, .height]

        pill.material = .hudWindow
        pill.blendingMode = .behindWindow
        pill.state = .active
        pill.wantsLayer = true
        pill.layer?.cornerRadius = 10
        pill.translatesAutoresizingMaskIntoConstraints = false

        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        window.contentView = content
        box.frame = content.bounds
        content.addSubview(box)
        content.addSubview(pill)
        pill.addSubview(label)
        NSLayoutConstraint.activate([
            pill.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            pill.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 14),
            label.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -14),
            label.topAnchor.constraint(equalTo: pill.topAnchor, constant: 7),
            label.bottomAnchor.constraint(equalTo: pill.bottomAnchor, constant: -7),
        ])
    }

    /// `quartzFrame` uses global top-left coordinates.
    func show(_ quartzFrame: CGRect, title: String) {
        guard Prefs.showPreview else { return }
        let accent = NSColor.controlAccentColor
        box.layer?.backgroundColor = accent.withAlphaComponent(0.18).cgColor
        box.layer?.borderColor = accent.withAlphaComponent(0.8).cgColor
        label.stringValue = title
        pill.isHidden = title.isEmpty

        let frame = Screens.flip(quartzFrame).insetBy(dx: 4, dy: 4)
        if visible {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.12
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(frame, display: true)
            }
        } else {
            window.setFrame(frame, display: true)
            window.alphaValue = 0
            window.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.1
                window.animator().alphaValue = 1
            }
            visible = true
        }
    }

    private var flashWork: DispatchWorkItem?

    /// Briefly shows the target frame (feedback for keyboard shortcuts).
    func flash(_ quartzFrame: CGRect, title: String) {
        show(quartzFrame, title: title)
        flashWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        flashWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    func hide() {
        flashWork?.cancel()
        flashWork = nil
        guard visible else { return }
        visible = false
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, !self.visible else { return }
            self.window.orderOut(nil)
        })
    }
}
