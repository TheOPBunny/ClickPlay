# OnScreenGamepad

An always-on-top macOS on-screen gamepad that sends **real, low-level CGEvent key presses** to whatever app is currently focused — no clicks, no terminal tricks, just native key injection.

## Features

- **Always-on-top overlay** — floats above every app including full-screen games
- **Low-level key injection** via `CGEvent` → delivered directly to the focused process
- **Zero activation steal** — pressing buttons never brings the gamepad to front or steals focus
- **Draggable** — click and drag anywhere on the pad to reposition
- **Opacity control** — slider in the title strip, range 25%–100%
- **All spaces** — follows you across Mission Control spaces
- **Full-screen compatible** — stays visible in `NSWindowCollectionBehavior.fullScreenAuxiliary` mode
- **Easy remapping** — edit `KeyMapping.swift`, one key code per button

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

Edit `KeyMapping.swift` → `var keyCode: CGKeyCode` to change any mapping.  
All Carbon `kVK_*` constants are available. Full list: https://eastmanreference.com/complete-list-of-applescript-key-codes

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

5. Relaunch the app — the gamepad overlay will appear at the bottom-center of your screen.

### Important: App Sandbox must be OFF

`CGEvent` injection to other processes requires the sandbox to be disabled.  
This is already set in `OnScreenGamepad.entitlements`. Don't re-enable it or key injection will silently stop working.

This means the app **cannot be submitted to the Mac App Store**. For personal use this is fine.

## Architecture

```
AppDelegate.swift         App entry, checks Accessibility permission
├── GamepadWindow.swift   NSPanel subclass — always-on-top, non-activating, draggable
│   └── GamepadContentView.swift   Lays out all button views
│       └── GamepadButtonView.swift   Individual button — tracks mouse, drives press state
│           └── KeyInjector.swift   Posts CGEvents to .cgAnnotatedSessionEventTap
└── KeyMapping.swift      Maps GamepadButton enum → CGKeyCode (edit to remap)
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

## Customization Ideas

- **Analog stick simulation** — add `NSPanGestureRecognizer` to a circular area and map direction to WASD
- **Turbo / auto-repeat** — add a `Timer` in `KeyInjector` that re-fires `press()` while a button is held
- **Profiles** — multiple `KeyMapping` presets switchable from the control strip
- **Resize** — change `GamepadWindow.defaultSize` and adjust `layoutButtons()` coordinates proportionally
