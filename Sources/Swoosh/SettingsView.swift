import ServiceManagement
import SwiftUI
import SwooshCore

enum SettingsTab: Int {
    case general, gestures, keyboard, setup, excluded
}

/// Selected tab, shared so the app can open Settings on a specific tab.
final class SettingsRouter: ObservableObject {
    static let shared = SettingsRouter()
    @Published var tab: SettingsTab = .general
}

struct SettingsView: View {
    @ObservedObject private var router = SettingsRouter.shared

    var body: some View {
        TabView(selection: $router.tab) {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }.tag(SettingsTab.general)
            GestureSettings().tabItem { Label("Gestures", systemImage: "hand.draw") }.tag(SettingsTab.gestures)
            KeyboardSettings().tabItem { Label("Keyboard", systemImage: "keyboard") }.tag(SettingsTab.keyboard)
            SetupSettings().tabItem { Label("Setup", systemImage: "checklist") }.tag(SettingsTab.setup)
            ExclusionSettings().tabItem { Label("Excluded Apps", systemImage: "nosign") }.tag(SettingsTab.excluded)
        }
        .frame(width: 560, height: 540)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @AppStorage(Prefs.Key.enabled) private var enabled = true
    @AppStorage(Prefs.Key.sensitivity) private var sensitivity = 45.0
    @AppStorage(Prefs.Key.gap) private var gap = 0.0
    @AppStorage(Prefs.Key.matchSystemMargins) private var matchSystemMargins = false
    @AppStorage(Prefs.Key.titlebarHeight) private var titlebarHeight = 40.0
    @AppStorage(Prefs.Key.haptics) private var haptics = true
    @AppStorage(Prefs.Key.showPreview) private var showPreview = true
    @AppStorage(Prefs.Key.chainTimeout) private var chainTimeout = 1.0
    @AppStorage(Prefs.Key.activateAfterSnap) private var activateAfterSnap = true
    @AppStorage(Prefs.Key.stageManagerOffset) private var stageOffset = 120.0
    @AppStorage(Prefs.Key.swooshCount) private var count = 0
    @ObservedObject private var login = LoginItem.shared

    var body: some View {
        Form {
            Section {
                Toggle("Enable Swoosh", isOn: $enabled)
                Toggle("Launch at login", isOn: Binding(get: { login.enabled }, set: { login.set($0) }))
                if let error = login.error {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
            Section("Feel") {
                LabeledContent("Swipe distance") {
                    HStack(spacing: 8) {
                        Text("Short").font(.caption).foregroundStyle(.secondary)
                        Slider(value: $sensitivity, in: 15...120).frame(width: 180)
                        Text("Long").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Toggle("Haptic feedback", isOn: $haptics)
                Toggle("Show snap preview", isOn: $showPreview)
                Toggle("Bring window to front after snapping", isOn: $activateAfterSnap)
                Picker("Follow-up swipes keep the same window for", selection: $chainTimeout) {
                    Text("Off").tag(0.0)
                    Text("0.6 seconds").tag(0.6)
                    Text("1 second").tag(1.0)
                    Text("1.5 seconds").tag(1.5)
                }
            }
            Section("Layout") {
                Toggle("Match macOS tiling margins", isOn: $matchSystemMargins)
                ValueStepper(title: "Gap between windows", value: $gap, range: 0...40, step: 2)
                    .disabled(matchSystemMargins)
                ValueStepper(title: "Title bar hot zone", value: $titlebarHeight, range: 20...120, step: 4)
                ValueStepper(title: "Stage Manager strip width", value: $stageOffset, range: 0...300, step: 10)
                Text("Snapped windows leave the Stage Manager strip free while Stage Manager is on and its recent apps are visible.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("Windows swooshed", value: "\(count)")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Gestures

private struct GestureSettings: View {
    @AppStorage(Prefs.Key.grid) private var gridRaw = SwooshCore.Grid.halves.rawValue
    @AppStorage(Prefs.Key.upFillsAlmost) private var almost = false
    @AppStorage(Prefs.Key.pinchGestures) private var pinch = true
    @AppStorage(Prefs.Key.doubleTapGesture) private var doubleTap = true
    @AppStorage(Prefs.Key.menubarGestures) private var menubar = true
    @AppStorage(Prefs.Key.dockGestures) private var dock = true
    @AppStorage(Prefs.Key.showTooltip) private var tooltip = true

    private var grid: SwooshCore.Grid { SwooshCore.Grid(stored: gridRaw) }

    var body: some View {
        Form {
            Section {
                Text("Swipe with two fingers on a window's title bar, a Dock icon or the menu bar. A tooltip shows what the gesture will do, and a preview shows where the window will land. Swipe again straight away to combine swipes.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle("Show gesture tooltip", isOn: $tooltip)
            }
            Section("Snapping") {
                Picker("Grid", selection: $gridRaw) {
                    ForEach(SwooshCore.Grid.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                Toggle("Swipe up fills almost the whole desktop", isOn: $almost)
                if grid == .halves {
                    IconRow([.swipe(.left)], .layout(.leftHalf), "Swipe left or right", "Left or right half")
                    IconRow([.swipe(.left), .swipe(.up)], .layout(.topLeft), "Sideways and up or down", "Quarter, in either order")
                } else {
                    IconRow([.swipe(.left)], .layout(.leftThird), "Swipe left or right", "Third, again for two thirds")
                    IconRow([.hold, .swipe(.right)], .layout(.centerThird), "Hold, then sideways", "Middle third (or swipe ← →)")
                    if grid == .thirds {
                        IconRow([.swipe(.left), .swipe(.up)], .layout(.topLeftSixth), "Sideways and up or down", "Sixth")
                    } else {
                        IconRow([.swipe(.left), .swipe(.up)], .layout(.ninth(col: 0, row: 0)), "Sideways and up or down", "Corner ninth")
                        IconRow([.swipe(.left), .swipe(.up), .swipe(.down)], .layout(.ninth(col: 0, row: 1)), "Sideways, up and down", "Middle-row ninth")
                    }
                }
                IconRow([.swipe(.up)], .layout(almost ? .almostMaximize : .maximize), "Swipe up", almost ? "Almost fill the desktop" : "Fill the desktop")
                IconRow([.swipe(.up), .swipe(.up)], .layout(.topHalf), "Swipe up twice", grid == .halves ? "Top half" : "Top half (upper sixth on a third)")
                IconRow([.swipe(.down), .swipe(.down)], .layout(.bottomHalf), "Swipe down twice", grid == .halves ? "Bottom half" : "Bottom half (lower sixth on a third)")
                IconRow([.doubleTap], .restore, "Double tap", "Unsnap or center", enabled: doubleTap)
            }
            Section("Windows") {
                IconRow([.swipe(.down)], .minimize, "Swipe down", "Minimize")
                IconRow([.hold, .swipe(.up)], .fullScreen, "Hold, then swipe up", "Enter or exit full screen")
                IconRow([.pinchIn], .close, "Pinch in", "Close window (⌥: quit app)", enabled: pinch)
                IconRow([.pinchOut], .fullScreen, "Pinch out", "Enter or exit full screen", enabled: pinch)
                IconRow([.swipe(.right)], .moveScreen(.right), "⌃ + swipe", "Move to the screen in that direction")
                Toggle("Pinch gestures", isOn: $pinch)
                Toggle("Double tap gesture", isOn: $doubleTap)
            }
            Section("Dock") {
                Toggle("Gestures on Dock icons", isOn: $dock)
                Group {
                    IconRow([.swipe(.up)], .unminimize, "Swipe up", "Restore the last minimized window (⇧: all)", origin: .dock)
                    IconRow([.swipe(.down)], .minimize, "Swipe down", "Minimize the front window (⇧: all)", origin: .dock)
                    IconRow([.swipe(.left), .swipe(.right)], .cycle, "Swipe left or right", "Switch between the app's windows", origin: .dock)
                    IconRow([.pinchIn], .quit, "Pinch in", "Quit the app", origin: .dock)
                    IconRow([.pinchOut], .newWindow, "Pinch out", "Open a new window", origin: .dock)
                    IconRow([.doubleTap], .hide, "Double tap", "Hide the app (⇧: hide others)", origin: .dock)
                }
                .disabled(!dock)
                Text("After restoring or switching to a window, swipe again without moving the pointer to snap it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Menu bar") {
                Toggle("Gestures on the menu bar", isOn: $menubar)
                Group {
                    IconRow([.swipe(.down)], .minimizeAll, "Swipe down", "Minimize all windows on that screen", origin: .menubar)
                    IconRow([.swipe(.up)], .unminimizeAll, "Swipe up", "Restore them", origin: .menubar)
                }
                .disabled(!menubar)
            }
        }
        .formStyle(.grouped)
    }
}

/// One gesture: origin + finger icons, name, result icon and description.
private struct IconRow: View {
    let gestures: [GestureGlyph]
    let action: ActionGlyph
    let name: String
    let result: String
    var origin: OriginGlyph = .titlebar
    var enabled = true
    @Environment(\.isEnabled) private var envEnabled

    init(_ gestures: [GestureGlyph], _ action: ActionGlyph, _ name: String, _ result: String,
         origin: OriginGlyph = .titlebar, enabled: Bool = true) {
        self.gestures = gestures; self.action = action; self.name = name; self.result = result
        self.origin = origin; self.enabled = enabled
    }

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 3) {
                Image(nsImage: GestureIcons.origin(origin, size: 16)).foregroundStyle(.tertiary)
                ForEach(Array(gestures.enumerated()), id: \.offset) { _, g in
                    Image(nsImage: GestureIcons.gesture(g, size: 18))
                }
            }
            .frame(width: 92, alignment: .leading)
            Text(name)
            Spacer(minLength: 8)
            Text(result).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
            Image(nsImage: GestureIcons.action(action, size: 20)).foregroundStyle(Color.accentColor)
        }
        .opacity(enabled && envEnabled ? 1 : 0.45)
    }
}

private struct ValueStepper: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                Text("\(Int(value)) pt").monospacedDigit().foregroundStyle(.secondary)
                Stepper("", value: $value, in: range, step: step).labelsHidden()
            }
        }
    }
}

private struct GestureRow: View {
    let gesture: String, result: String
    init(_ gesture: String, _ result: String) { self.gesture = gesture; self.result = result }
    var body: some View {
        LabeledContent {
            Text(result).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
        } label: {
            Text(gesture).fontWeight(.medium)
        }
    }
}

// MARK: - Keyboard

private struct KeyboardSettings: View {
    @AppStorage(Prefs.Key.hotkeys) private var scheme = HotkeyScheme.arrows.rawValue

    private var current: HotkeyScheme { HotkeyScheme(rawValue: scheme) ?? .off }

    var body: some View {
        Form {
            Section {
                Picker("Shortcut keys", selection: $scheme) {
                    ForEach(HotkeyScheme.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                }
                Text("Shortcuts act on the frontmost window and follow the same steps as swipes, so pressing ⌃⌥← twice gives you the left third.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if current != .off {
                let l = current.labels
                Section("Shortcuts") {
                    GestureRow("⌃⌥\(l[.left]!)  ⌃⌥\(l[.right]!)", "Left / right half, then thirds")
                    GestureRow("⌃⌥\(l[.up]!)", "Maximize")
                    GestureRow("⌃⌥\(l[.down]!)", "Minimize, or a quarter from a half")
                    GestureRow("⌃⌥C", "Unsnap or center")
                    GestureRow("⌃⌥⌘ + direction", "Move to the next screen")
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Setup

final class SetupStatus: ObservableObject {
    static let shared = SetupStatus()
    @Published var accessibility = SystemState.accessibilityGranted
    @Published var pinch = SystemState.trackpadSetting(.pinch)
    @Published var smartZoom = SystemState.trackpadSetting(.smartZoom)
    private var timer: Timer?

    func startPolling() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func stopPolling() { timer?.invalidate(); timer = nil }

    func refresh() {
        accessibility = SystemState.accessibilityGranted
        pinch = SystemState.trackpadSetting(.pinch)
        smartZoom = SystemState.trackpadSetting(.smartZoom)
    }
}

private struct SetupSettings: View {
    @ObservedObject private var status = SetupStatus.shared

    var body: some View {
        Form {
            Section {
                Text("Swoosh reads trackpad gestures and moves windows for you. Make sure these are set up:")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section {
                CheckRow(ok: status.accessibility, title: "Accessibility access",
                         detail: "Lets Swoosh read gestures and move windows.",
                         action: ("Open Privacy Settings", SystemState.openAccessibilitySettings))
                CheckRow(ok: status.pinch, title: "Trackpad › Zoom in or out",
                         detail: "Needed for pinch to close and full screen.",
                         action: ("Open Trackpad Settings", SystemState.openTrackpadSettings))
                CheckRow(ok: status.smartZoom, title: "Trackpad › Smart zoom",
                         detail: "Needed for double tap to unsnap or center.",
                         action: ("Open Trackpad Settings", SystemState.openTrackpadSettings))
            }
            Section("Good to know") {
                Group {
                    Text("Quit other window managers that use the same gestures (such as Swish) so they don't both respond.")
                    Text("After installing a new build, macOS may treat it as a new app. If gestures stop working, switch Swoosh off and on again under Accessibility.")
                }
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .onAppear { status.startPolling() }
        .onDisappear { status.stopPolling() }
    }
}

private struct CheckRow: View {
    let ok: Bool
    let title: String
    let detail: String
    let action: (String, () -> Void)

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(ok ? .green : .orange)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !ok { Button(action.0, action: action.1) }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Excluded apps

private struct ExclusionSettings: View {
    @AppStorage(Prefs.Key.excludedApps) private var excluded = Prefs.defaultExcluded

    var body: some View {
        Form {
            Section {
                Text("Swoosh ignores windows from these apps. Enter one bundle identifier per line.")
                    .font(.callout).foregroundStyle(.secondary)
                TextEditor(text: $excluded)
                    .font(.system(.callout, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
                    .frame(minHeight: 220)
                HStack {
                    Menu("Add Running App") {
                        ForEach(runningApps(), id: \.bundleIdentifier) { app in
                            Button(app.localizedName ?? app.bundleIdentifier ?? "?") { add(app.bundleIdentifier) }
                        }
                    }
                    .fixedSize()
                    Spacer()
                    Button("Reset to Defaults") { excluded = Prefs.defaultExcluded }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func runningApps() -> [NSRunningApplication] {
        let ours = Bundle.main.bundleIdentifier
        let current = Prefs.excludedApps
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil && $0.bundleIdentifier != ours
                && !current.contains($0.bundleIdentifier!) }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    private func add(_ id: String?) {
        guard let id, !Prefs.excludedApps.contains(id) else { return }
        let trimmed = excluded.trimmingCharacters(in: .whitespacesAndNewlines)
        excluded = trimmed.isEmpty ? id : trimmed + "\n" + id
    }
}

// MARK: - Launch at login

final class LoginItem: ObservableObject {
    static let shared = LoginItem()
    @Published private(set) var enabled = SMAppService.mainApp.status == .enabled
    @Published private(set) var error: String?

    func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            error = nil
        } catch {
            self.error = "Couldn't change the login item: \(error.localizedDescription)"
        }
        enabled = SMAppService.mainApp.status == .enabled
    }
}

// MARK: - Debug rendering

/// `Swoosh --render-settings <dir>` writes a PNG of every settings tab, for
/// reviewing the UI without screen-recording permission.
enum SettingsRenderer {
    static func render(to dir: String) {
        let tabs: [(String, AnyView)] = [
            ("general", AnyView(GeneralSettings())),
            ("gestures", AnyView(GestureSettings())),
            ("keyboard", AnyView(KeyboardSettings())),
            ("setup", AnyView(SetupSettings())),
            ("excluded", AnyView(ExclusionSettings())),
            ("icon-sheet", AnyView(IconSheet())),
            ("menubar-icons", AnyView(HStack(spacing: 16) {
                Image(nsImage: StatusIcon.image(active: true))
                Image(nsImage: StatusIcon.image(active: false))
            }.padding(8).scaleEffect(4).frame(width: 300, height: 120))),
        ]
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            for (name, view) in tabs {
                let host = NSHostingView(rootView: view.frame(width: 560, height: 500)
                    .background(Color(nsColor: .windowBackgroundColor)))
                host.frame = NSRect(x: 0, y: 0, width: 560, height: 500)
                let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                window.appearance = NSAppearance(named: appearance)
                window.contentView = host
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.3))
                guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
                host.cacheDisplay(in: host.bounds, to: rep)
                let suffix = appearance == .darkAqua ? "-dark" : ""
                try? rep.representation(using: .png, properties: [:])?
                    .write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name)\(suffix).png"))
            }
        }
    }
}

/// Every icon at large size, for reviewing the set.
private struct IconSheet: View {
    var body: some View {
        let gestures: [GestureGlyph] = [.swipe(.left), .swipe(.right), .swipe(.up), .swipe(.down), .pinchIn, .pinchOut, .doubleTap, .hold]
        let actions: [ActionGlyph] = [.layout(.leftHalf), .layout(.topRight), .layout(.centerThird), .layout(.bottomLeftSixth),
                                      .layout(.ninth(col: 1, row: 1)), .layout(.maximize), .minimize, .unminimize,
                                      .minimizeAll, .unminimizeAll, .close, .quit, .fullScreen, .restore,
                                      .moveScreen(.right), .hide, .cycle, .newWindow]
        let origins: [OriginGlyph] = [.titlebar, .dock, .menubar, .keyboard]
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) { ForEach(Array(origins.enumerated()), id: \.offset) { Image(nsImage: GestureIcons.origin($0.element, size: 40)) } }
            HStack(spacing: 14) { ForEach(Array(gestures.enumerated()), id: \.offset) { Image(nsImage: GestureIcons.gesture($0.element, size: 40)) } }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(48)), count: 9), spacing: 12) {
                ForEach(Array(actions.enumerated()), id: \.offset) { Image(nsImage: GestureIcons.action($0.element, size: 40)).foregroundStyle(Color.accentColor) }
            }
        }
        .padding(20)
    }
}
