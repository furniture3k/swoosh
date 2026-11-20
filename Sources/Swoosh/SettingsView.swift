import SwiftUI
import ServiceManagement

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            GestureGuide().tabItem { Label("Gestures", systemImage: "hand.draw") }
            ExclusionSettings().tabItem { Label("Excluded Apps", systemImage: "nosign") }
        }
        .frame(width: 520, height: 460)
    }
}

private struct GeneralSettings: View {
    @AppStorage(Prefs.Key.enabled) private var enabled = true
    @AppStorage(Prefs.Key.sensitivity) private var sensitivity = 45.0
    @AppStorage(Prefs.Key.gap) private var gap = 0.0
    @AppStorage(Prefs.Key.titlebarHeight) private var titlebarHeight = 40.0
    @AppStorage(Prefs.Key.haptics) private var haptics = true
    @AppStorage(Prefs.Key.showPreview) private var showPreview = true
    @AppStorage(Prefs.Key.chainTimeout) private var chainTimeout = 1.0
    @AppStorage(Prefs.Key.activateAfterSnap) private var activateAfterSnap = true
    @AppStorage(Prefs.Key.swooshCount) private var count = 0
    @ObservedObject private var login = LoginItem.shared

    var body: some View {
        Form {
            Section {
                Toggle("Enable gestures", isOn: $enabled)
                Toggle("Launch at login", isOn: Binding(get: { login.enabled }, set: { login.set($0) }))
            }
            Section("Feel") {
                LabeledContent("Swipe distance") {
                    Slider(value: $sensitivity, in: 15...120) { Text("") } minimumValueLabel: {
                        Text("Short")
                    } maximumValueLabel: { Text("Long") }
                }
                Toggle("Haptic feedback", isOn: $haptics)
                Toggle("Show snap preview", isOn: $showPreview)
                Toggle("Activate window after snapping", isOn: $activateAfterSnap)
                LabeledContent("Chain follow-up swipes for") {
                    Picker("", selection: $chainTimeout) {
                        Text("Off").tag(0.0)
                        Text("0.6 s").tag(0.6)
                        Text("1 s").tag(1.0)
                        Text("1.5 s").tag(1.5)
                    }.labelsHidden().frame(width: 90)
                }
            }
            Section("Layout") {
                LabeledContent("Gap between windows") {
                    Stepper("\(Int(gap)) pt", value: $gap, in: 0...40, step: 2)
                }
                LabeledContent("Title bar hot zone") {
                    Stepper("\(Int(titlebarHeight)) pt", value: $titlebarHeight, in: 20...120, step: 4)
                }
            }
            Text("\(count) swooshes so far").font(.footnote).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

private struct GestureGuide: View {
    private let rows: [(String, String)] = [
        ("Swipe ← / →", "Snap to left / right half"),
        ("Swipe ↑", "Maximize (again: almost maximize)"),
        ("Swipe ↓", "Minimize; restore if snapped"),
        ("Half, then swipe same way", "Third, then two thirds, then back to half"),
        ("Third, then swipe the other way", "Move through the thirds"),
        ("Half, then swipe ↑ / ↓", "Quarter"),
        ("Third, then swipe ↑ / ↓", "Sixth"),
        ("Quarter, then swipe toward its edge", "Grow into the half along that edge"),
        ("Pinch in", "Close window (⌥: quit app)"),
        ("Pinch out", "Toggle full screen"),
        ("Double tap (Smart Zoom)", "Unsnap / center window"),
        ("⌃ + swipe", "Move window to the screen in that direction"),
    ]

    var body: some View {
        Form {
            Section {
                Text("Do gestures with two fingers while the pointer is over a window's title bar or toolbar. Turn while swiping, or swipe again right away, to chain steps. A preview shows where the window will go, and it moves when you lift your fingers.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section {
                ForEach(rows, id: \.0) { row in
                    LabeledContent(row.0) { Text(row.1).foregroundStyle(.secondary) }
                }
            }
            Section("Requirements") {
                Text("Pinch needs “Zoom in or out” and double tap needs “Smart zoom”, both under System Settings › Trackpad › Scroll & Zoom.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ExclusionSettings: View {
    @AppStorage(Prefs.Key.excludedApps) private var excluded = Prefs.defaultExcluded

    var body: some View {
        Form {
            Section {
                Text("Swoosh ignores windows from these apps (bundle identifiers, separated by commas or new lines).")
                    .font(.callout).foregroundStyle(.secondary)
                TextEditor(text: $excluded)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 200)
                HStack {
                    Button("Add Frontmost App…") { addFrontmost() }
                    Spacer()
                    Button("Reset") { excluded = Prefs.defaultExcluded }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func addFrontmost() {
        let ours = Bundle.main.bundleIdentifier
        let app = NSWorkspace.shared.runningApplications.first {
            $0.activationPolicy == .regular && $0.bundleIdentifier != ours && $0.isActive
        } ?? NSWorkspace.shared.menuBarOwningApplication
        guard let id = app?.bundleIdentifier, id != ours, !Prefs.excludedApps.contains(id) else { return }
        excluded = excluded.isEmpty ? id : excluded + ", " + id
    }
}

final class LoginItem: ObservableObject {
    static let shared = LoginItem()
    @Published private(set) var enabled = SMAppService.mainApp.status == .enabled

    func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Swoosh: launch at login failed: \(error)")
        }
        enabled = SMAppService.mainApp.status == .enabled
    }
}
