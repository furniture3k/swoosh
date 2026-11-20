# Swoosh

Trackpad gestures for window management on macOS. Two-finger swipe, pinch or
double tap on a window's title bar to snap, maximize, minimize, close or move it.
Written from scratch based on how Swish works (see
[docs/REVERSE_ENGINEERING.md](docs/REVERSE_ENGINEERING.md)).

## Build and run

```sh
./build.sh --run          # builds build/Swoosh.app and opens it
./build.sh --install      # copies it to /Applications
```

Requires macOS 13+ and the Swift toolchain (Command Line Tools is enough).
On first launch, grant **Accessibility** access when prompted. The app is
ad-hoc signed, so macOS treats each rebuild as a new app: turn the permission
off and on again after rebuilding, or set `SWOOSH_SIGN_IDENTITY` to a real
signing identity.

Pinch needs *Zoom in or out* turned on, and double tap needs *Smart zoom*, under
System Settings › Trackpad › Scroll & Zoom.

**Quit Swish before using Swoosh.** Both apps capture the same gestures.

## Gestures (pointer over a title bar)

| Gesture | Result |
|---|---|
| Swipe ← / → | Left / right half |
| Swipe again the same way | Third → two thirds → half |
| Half, then ↑ / ↓ | Quarter |
| Third, then ↑ / ↓ | Sixth |
| Swipe ↑ | Maximize (again: almost maximize) |
| Swipe ↓ | Minimize, or restore if maximized |
| Pinch in / ⌥ pinch in | Close window / quit app |
| Pinch out | Toggle full screen |
| Double tap | Unsnap or center |
| ⌃ + swipe | Move to the screen in that direction |

To chain steps, change direction mid-swipe or swipe again within about a second.
For that second the window keeps receiving gestures even after it has moved away
from the pointer.

## Code map

- `GestureEngine.swift`: the event tap, swipe and pinch state machines
- `Layout.swift`: snap rectangles and the swipe grammar
- `WindowManager.swift`: title-bar hit testing and Accessibility window actions
- `Overlay.swift`: the snap preview
- `AX.swift`, `Screens.swift`: Accessibility helpers and coordinate conversion
- `SettingsView.swift`, `main.swift`: settings window and menu-bar app
