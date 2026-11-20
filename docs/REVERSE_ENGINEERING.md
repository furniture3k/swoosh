# How Swish works: findings behind Swoosh

Target: `/Applications/Swish.app` v1.11 (build 71), `co.highlyopinionated.swish`,
a universal Mach-O (arm64 + x86_64) Swift/AppKit menu-bar app (`LSUIElement`).
SHA-256 of the main executable: `47ce2998…dcf8`.

## Method and limits

- REA `open_binary` bound the target, but no deep provider was usable. Hopper was
  denied Apple Events permission, and Ghidra and IDA aren't configured. So no
  decompiled code was examined.
- The evidence comes from the bundle layout, `Info.plist`, the imported-symbol table
  (`nm -u`), the linked libraries (`otool -L`), embedded strings and Objective-C
  metadata, and the app's own UserDefaults keys. The Swift symbols are stripped.
- Everything below is **inferred from static artifacts**. No runtime behaviour was
  observed or traced.

## Observations

| Area | Evidence | Inference |
|---|---|---|
| Gesture input | Imports `CGEventTapCreate`/`CGEventTapEnable`; strings `CGEventTap: initialized`; `IOHIDCheckAccess`. No MultitouchSupport import. | Gestures come from a session event tap that reads the system's scroll, magnify and smart-magnify events, not raw touches. |
| Required settings | "For Pinching to work, Zoom In Or Out needs to be enabled", "For Double Tap to work, Smart Zoom needs to be enabled", Force Click checks | Pinch = magnify events, double tap = smart-magnify events, tap-and-hold = Force Touch pressure. |
| Hot zone | `AXUIElementCopyElementAtPosition`; "Origin: Cursor not in frame of element", "Origin: Default height used", "Origin: Special height" | Gestures count only when they start over a window's title bar, with taller zones for some apps. |
| Window control | `AXUIElementSetAttributeValue`, `AXPosition`/`AXSize`, `AXMinimized`, `AXFullScreen`, `AXCloseButton`, `AXObserver*` | Windows are moved, resized, minimized and closed through Accessibility. Observers watch for user drags and resizes. |
| Snap actions | `ActionSnapHalves/Quarters/Thirds/Sixths/Ninths/Almost/Vertical/Unsnap`; prefs `actions = [snapMax, snapHalves, snapQuarters, snapThirds, snapSixths, snapNinths, snapAlmost, snapCenter, snapVertical, windowMinimize, windowFullscreen, windowQuit, tabClose, appCycle, appMinimize, appUnminimize, screensMove, spacesMove]` | The full action set. |
| Chaining | "Gesture: chained", `isChaining`, `screensChainGesture`, "…chains the window, which allows you to apply any window gesture afterwards" | After an action, follow-up gestures go to the same window. |
| Preview | `BezelWindow`, `BezelWindowController`, `CAKeyframeAnimation` | Animated overlay showing the target frame. |
| Feedback | `NSHapticFeedbackManager` | A haptic tick on each gesture step. |
| Modifiers | "General Modifier", "Secondary Modifier", "Tertiary Modifier", `RegisterEventHotKey` | Modifier keys switch gestures to alternate actions. |
| Spaces/Dock/Menu bar | `CGSCopyManagedDisplaySpaces`, `CopySymbolicHotKeys`, Mission Control shortcut checks, dock/menu-bar gesture stacks | Moves between Spaces by sending Mission Control shortcuts. Separate gesture sets for the Dock and menu bar. |
| Settings | `gridOffset`, `EnableTiledWindowMargins`, `sensitivitySlider`, `marginSelect`, `blacklist` (bundle IDs) | Gap, sensitivity and an excluded-app list. |
| Third-party | Paddle.framework (licensing), Sparkle (updates), `Defaults` and `KeyboardShortcuts` Swift packages, PromiseKit | Not reproduced. |

## What Swoosh implements (design choices are mine)

- A CGEventTap on scroll wheel (22), magnify (30) and smart magnify (32) events. Events are swallowed only when the gesture starts in a window's title-bar zone or targets a chained window.
- A swipe grammar (`Layout.swift → Grammar`) covering halves, thirds, two-thirds, quarters, sixths, maximize, almost maximize, restore and minimize.
- Pinch in closes the window (⌥ quits the app). Pinch out toggles full screen. Double tap unsnaps or centers the window. ⌃ + swipe moves the window to the next screen in that direction.
- A preview overlay, haptics, a configurable gap, swipe distance, title-bar zone height, chaining timeout and excluded apps, plus launch at login.

## Not implemented

Ninths, tabs (close or detach), app cycling and per-app minimize/hide, Dock and
menu-bar gestures, moving between Spaces, tap-and-hold (Force Touch), modifier
remapping, the onboarding flow, licensing and updates.
