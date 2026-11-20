import Carbon.HIToolbox
import Foundation
import SwooshCore

/// Global keyboard shortcuts via the Carbon hot key API (no extra permission).
///   ⌃⌥ + direction key   snap step (chains like swipes)
///   ⌃⌥⌘ + direction key  move window to the neighbouring screen
///   ⌃⌥ + C               unsnap / center
final class Hotkeys {
    private var refs: [EventHotKeyRef] = []
    private var actions: [UInt32: () -> Void] = [:]
    private var handler: EventHandlerRef?
    private let engine: GestureEngine
    private static let signature: OSType = 0x5357_4F4F // 'SWOO'

    init(engine: GestureEngine) {
        self.engine = engine
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr else { return status }
            let me = Unmanaged<Hotkeys>.fromOpaque(userData).takeUnretainedValue()
            me.actions[id.id]?()
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    /// (Re)registers shortcuts for the current scheme.
    func apply(_ scheme: HotkeyScheme) {
        refs.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
        actions.removeAll()
        guard scheme != .off else { return }

        let snapMods = UInt32(controlKey | optionKey)
        let screenMods = UInt32(controlKey | optionKey | cmdKey)
        for (code, dir) in scheme.keyCodes {
            register(code, snapMods) { [weak self] in self?.engine.keyboardStep(dir, moveScreen: false) }
            register(code, screenMods) { [weak self] in self?.engine.keyboardStep(dir, moveScreen: true) }
        }
        register(UInt32(kVK_ANSI_C), snapMods) { [weak self] in self?.engine.keyboardCenter() }
    }

    private func register(_ code: UInt32, _ mods: UInt32, _ action: @escaping () -> Void) {
        let id = UInt32(actions.count + 1)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(code, mods, EventHotKeyID(signature: Hotkeys.signature, id: id),
                                         GetEventDispatcherTarget(), 0, &ref)
        guard status == noErr, let ref else {
            NSLog("Swoosh: shortcut \(code)/\(mods) unavailable (\(status))")
            return
        }
        refs.append(ref)
        actions[id] = action
    }
}
