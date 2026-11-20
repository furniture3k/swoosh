# Swoosh

<img src="docs/icon.png" width="96" align="right" alt="Swoosh icon">

Trackpad gestures and keyboard shortcuts for window management on macOS.
Yes, the icon is a parody. Yes, it has googly eyes.
Swipe, pinch or double tap on a window's title bar to snap, maximize, minimize,
close or move it. Written from scratch based on how Swish works (see
[docs/REVERSE_ENGINEERING.md](docs/REVERSE_ENGINEERING.md)).

## Install

1. Download the latest `Swoosh-x.y.z.dmg` from the
   [Releases](../../releases/latest) page.
2. Open it and drag **Swoosh** onto **Applications**.
3. Open Swoosh from Applications. Its icon appears in the menu bar, and the
   Setup tab walks you through allowing Accessibility access.

Swoosh isn't notarized by Apple, so the first time you open it macOS says it
can't verify the developer. Click **Done**, then go to System Settings ›
Privacy & Security, scroll down and click **Open Anyway** next to the Swoosh
message. You only need to do this once.

Requires macOS 13 or later.

## Releasing

```sh
Scripts/make-dmg.sh       # test, build and package dist/Swoosh-<version>.dmg
```

To publish a release on GitHub, bump `CFBundleShortVersionString` in
`Resources/Info.plist`, commit, then push a tag:

```sh
git tag v1.0.0 && git push origin v1.0.0
```

The Release workflow builds the DMG and attaches it to a GitHub release. With a
paid Apple Developer account you can sign with a "Developer ID Application"
certificate and run `NOTARY_PROFILE=<profile> Scripts/make-dmg.sh` to notarize
it, which removes the "can't verify the developer" warning.

## Build, test and run

```sh
./build.sh --run          # runs the tests, builds build/Swoosh.app and opens it
./build.sh --install      # also copies it to /Applications
swift test                # tests only
```

Requires macOS 13+ and the Swift toolchain (Command Line Tools is enough).
On first launch, Swoosh opens its **Setup** tab, which checks:

- **Accessibility** access
- *Zoom in or out*, needed for pinch
- *Smart zoom*, needed for double tap

`build.sh` signs with your Apple Development certificate when one is
installed, so the Accessibility permission survives rebuilds. Without one it
falls back to ad-hoc signing, and you'll need to re-allow access after each
build.

**Quit Swish before using Swoosh.** Both apps capture the same gestures.

## Gestures

Window gestures show a preview of where the window will land. You can also
turn on a tooltip with gesture icons under Settings › Gestures.

### Title bar

Each gesture starts fresh, like Swish. For example, a swipe up maximizes even
if the window is currently a half. Several swipes in quick succession count as
one gesture.

| Gesture | 2×2 grid (default) | 3×2 / 3×3 grid |
|---|---|---|
| Swipe ← / → | Left / right half (again: next screen) | Third, again for two thirds |
| Sideways + up/down (either order) | Quarter | Sixth / corner ninth |
| Hold, then sideways (or ← →) | n/a | Middle third |
| Swipe ↑ | Fill the desktop (or "almost") | Same |
| Swipe ↑ twice | Top half | Upper sixth on a third |
| Hold, then swipe ↓ | Bottom half | Lower sixth on a third |
| Swipe ↓ | Minimize, instantly | Same |
| Hold, then swipe ↑ | Enter or exit full screen | Same |
| Pinch in / ⌥ pinch in | Close window / quit app | Same |
| Pinch out | Enter or exit full screen | Same |
| Double tap | Unsnap or center | Same |
| ⌃ + swipe | Move to the screen in that direction | Same |

"Hold" means resting two fingers on the trackpad for a moment before swiping.

### Dock icons (pointer over an app in the Dock)

| Gesture | Result |
|---|---|
| Swipe ↑ | Restore the last minimized window (⇧: all), ready to snap |
| Swipe ↓ | Minimize the front window (⇧: all) |
| Swipe ← / → | Switch between the app's windows |
| Pinch in / out | Quit the app / open a new window |
| Double tap | Hide the app (⇧: hide other apps) |

After restoring or switching to a window, swipe again without moving the
pointer to snap it, for example swipe ↑ then ← for the left half.

### Menu bar

Swipe ↓ to minimize every window on that screen, and ↑ to restore them.

## Keyboard shortcuts

Set the keys under Settings › Keyboard: Arrow keys (the default), WASD, IJKL or Off.

| Shortcut | Result |
|---|---|
| ⌃⌥ + direction | One snap step on the frontmost window (chains like swipes) |
| ⌃⌥⌘ + direction | Move to the screen in that direction |
| ⌃⌥C | Unsnap or center |

## Other settings

- Gap between windows, or "Match macOS tiling margins"
- Space reserved for the Stage Manager strip, used automatically when Stage Manager is on
- Swipe distance, haptics, preview, title-bar hot zone, chaining time
- Launch at login and excluded apps
- Hide the menu bar icon (Settings › General, or the menu's "Hide Menu Bar
  Icon"). To get back to Settings while it's hidden, open Swoosh again from
  Applications or Spotlight.

## Code map

- `Sources/SwooshCore`: pure logic, fully unit tested
  - `Layout.swift`: snap rectangles and the swipe grammar
  - `SwipeSession.swift`: turns scroll deltas into steps and outcomes
  - `Geometry.swift`: screen maths (detection, mapping, restore, Stage Manager)
  - `Resolver.swift`: Swish's gesture rules (grids, double swipes, hold, Dock actions)
  - `Policy.swift`: title-bar hit policy, chaining, hotkey layouts, trackpad checks
- `Sources/Swoosh`: the AppKit app
  - `GestureEngine.swift`: CGEventTap for scroll, pinch and smart zoom
  - `WindowManager.swift`: Accessibility window actions
  - `Hotkeys.swift`: global shortcuts (Carbon)
  - `GestureIcons.swift`, `GestureHUD.swift`: icon set and live tooltip
  - `Overlay.swift`, `StatusIcon.swift`, `SettingsView.swift`, `main.swift`: UI
- `Tests/SwooshCoreTests`: Swift Testing suite
- `Scripts/make-icon.swift`: renders `Resources/AppIcon.icns`

To review the settings UI without Screen Recording permission, run
`build/Swoosh.app/Contents/MacOS/Swoosh --render-settings <dir>`. It writes a
PNG of every tab in light and dark mode.

## License

MIT. See [LICENSE](LICENSE).
