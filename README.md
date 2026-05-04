# OnScreenGamepad

An always-on-top macOS menu bar utility that combines:

- a non-activating on-screen gamepad overlay that sends **real, low-level CGEvent key presses**
- a built-in profile editor window for editing layouts, labels, colors, and key mappings

The merged `OnScreenGamepad` app is the supported product. The old standalone `GamepadConfigurator` project is retained only as an archived fallback and should not be used for normal development.

## Features

- **Always-on-top overlay** — floats above every app including full-screen games
- **Low-level key injection** via `CGEvent` → delivered directly to the focused process
- **Zero activation steal** — pressing buttons never brings the gamepad to front or steals focus
- **Built-in profile editor** — open `Open Editor…` from the menu bar app to edit profiles in a standard AppKit window
- **Profile switching** — switch the active overlay profile from the menu bar
- **Draggable** — click and drag anywhere on the pad to reposition
- **Profile-backed layout** — overlay button layout, opacity, size, labels, and key bindings are persisted in `profiles.json`
- **All spaces** — follows you across Mission Control spaces
- **Full-screen compatible** — stays visible in `NSWindowCollectionBehavior.fullScreenAuxiliary` mode

## Setup & Build

### Requirements
- macOS 13.0 Ventura or later
- Xcode 15+

### Steps

1. **Open project**
   ```
   open OnScreenGamepad.xcodeproj
   ```

2. **Set your Team** in Xcode → Target → Signing & Capabilities → Team

3. **Build & Run** (`⌘R`)

4. On first launch, macOS will ask for **Accessibility permission**.  
   Go to **System Settings → Privacy & Security → Accessibility** and enable `OnScreenGamepad`.

5. Relaunch the app. Use the 🎮 menu bar item to:
   - show or hide the overlay
   - switch profiles
  - open `Open Editor…`

### Important: App Sandbox must be OFF

`CGEvent` injection to other processes requires the sandbox to be disabled.  
This is already set in `OnScreenGamepad.entitlements`. Don't re-enable it or key injection will silently stop working.

This means the app **cannot be submitted to the Mac App Store**. For personal use this is fine.

## Default Button Map

| Gamepad Button | Key Sent |
|---|---|
| D-Pad ↑ ↓ ← → | Arrow keys |
| A | Z |
| B | X |
| X | A |
| Y | S |
| L / R | Q / W |
| ZL / ZR | E / R |
| START | Return |
| SELECT | Space |
| LS / RS | C / V |

## Architecture

```
main.swift
AppDelegate.swift                    App entry, menu bar item, overlay/editor coordination
GamepadWindow.swift                  Non-activating overlay panel
GamepadContentView.swift             Overlay layout and drag behavior
GamepadButtonView.swift              Per-button mouse handling and key lifecycle
KeyInjector.swift                    Low-level CGEvent posting and held-key tracking
EditorWindowController.swift         Standard editor window owner
EditorViewController.swift           Profile sidebar and editor split view
GamepadShared/Profile.swift          Profile and button config models
GamepadShared/ProfileStore.swift     Shared persistence and active profile state
GamepadShared/KeyMapping.swift       Stable gamepad button identities
```

## How Key Injection Works

```swift
// KeyInjector.swift — the core of it all
let src = CGEventSource(stateID: .hidSystemState)
let evt = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true)
evt.post(tap: .cgAnnotatedSessionEventTap)
```

`CGEventSource(stateID: .hidSystemState)` makes the event look like it came from real hardware.  
`.cgAnnotatedSessionEventTap` delivers it to whatever process currently has key focus — the gamepad window never needs to be active.

## Troubleshooting

| Problem | Fix |
|---|---|
| Keys not sending | Check Accessibility permission in System Settings |
| Window not on top in a game | Some games use exclusive fullscreen — switch to Windowed or Borderless |
| Buttons feel laggy | Normal if the target app has input throttling; the injection itself is synchronous |
| Window disappeared | Click the 🎮 icon in the menu bar to bring it back |
| Need to edit layout or bindings | Open `Edit Profiles…` from the 🎮 menu bar menu |

## Customization Ideas

- **Analog stick simulation** — add `NSPanGestureRecognizer` to a circular area and map direction to WASD
- **Turbo / auto-repeat** — add a `Timer` in `KeyInjector` that re-fires `press()` while a button is held
- **Profile sub-profiles / layering** — extend `ProfileStore` and the editor window
- **Resize** — change `GamepadWindow.defaultSize` and adjust `layoutButtons()` coordinates proportionally
