# Click Play Documentation

Click Play is a macOS mouse-driven gamepad and control overlay for keyboard-driven games and workflows. It gives users a customizable on-screen control surface while keeping the target app or game focused.

## Table of Contents

- [About Project](#about-project)
- [Features](#features)
- [Codebase](#codebase)
- [Planned Features](#planned-features)
- [FAQ](#faq)
- [About Me](#about-me)

## About Project

Click Play runs as a macOS status-bar app. Its main experience is an always-on-top, non-activating overlay that can sit above games or other apps without taking keyboard focus away from them.

Users build profiles made of buttons, joystick controls, layers, templates, colors, labels, and bindings. Those controls can inject keyboard events, trigger supported system events, switch layers, or behave as toggle/turbo controls.

The app is currently a functional prototype that is growing into a richer editor-backed control system. It uses AppKit for lifecycle, status-bar, windowing, editor, and overlay behavior, with SwiftUI used where it fits well for onboarding and update-check screens.

Click Play uses `CGEvent` for keyboard injection. That means macOS Accessibility permission is required, and the App Sandbox must remain disabled for the current input approach.

## Features

### Always-On-Top Overlay

The gamepad is displayed in a borderless overlay panel above normal app windows. It is designed to remain usable while another app or game stays focused.

### Non-Activating Window Behavior

The overlay is intentionally non-activating: interacting with Click Play should not make the overlay the key or main window. This is central to using it over games and other focused apps.

### Accessibility Permission Flow

On first launch, Click Play checks whether Accessibility permission has been granted. If permission is missing, the onboarding flow guides the user toward granting it before launching the gamepad.

### Status Bar Menu

The status-bar item provides entry points for showing or hiding the gamepad, opening the editor, checking for updates, switching profiles, and opening Accessibility settings.

### Profiles

Profiles store complete gamepad layouts. A profile includes pad dimensions, background styling, opacity, compatibility mode, button ordering, button configs, groups, and nested layers.

Profiles are saved locally in:

```text
~/Library/Application Support/Click Play/profiles.json
```

### Layers

Layers are nested profiles inside a top-level profile. They let a layout switch between related control surfaces without leaving the parent profile.

### Built-In Editor

The Click Play Editor is used to create, arrange, configure, duplicate, delete, and save profiles, layers, buttons, groups, and templates. It has a profile sidebar, live preview canvas, and inspector panel.

### Templates

Templates allow users to save reusable profiles, layers, or button groups. Built-in templates provide starter layouts, while user templates are persisted separately from live profiles.

Templates are saved locally in:

```text
~/Library/Application Support/Click Play/templates.json
```

### Button Customization

Buttons can be positioned, resized, labeled, enabled or disabled, colored, styled, and assigned different shapes. Button labels can have custom size, bold/italic state, and color.

### Key Recording

The editor includes a key recorder for capturing keyboard bindings. It supports ordinary keys, modifier chords, modifier-only bindings, and multi-key binding lists.

### Multi-Key Bindings

Controls can use multiple key bindings. Multi-key activation can be sequential or simultaneous depending on the configuration.

### Right-Click Inputs

Controls can define separate right-click bindings and interaction modes. If no right-click binding is set, a control can fall back to its primary left-click binding.

### Momentary Press/Hold/Release

Click-and-hold is a foundational input primitive, not the whole product identity. For momentary controls, mouse down maps to key down and mouse up or drag-off maps to key up. This release behavior protects against stale held keys.

### Toggle-Hold Mode

Toggle-hold controls let a click toggle an input between held and released states. The visual state reflects that active mode.

### Turbo Mode

Turbo controls repeatedly activate an input while active. This is useful for games or workflows that benefit from repeated taps.

### Joystick Controls

Joystick-style controls map directional movement to directional key bindings. Joysticks support capture-style and click-drag interaction modes.

### Joystick Axis and Scroll Behavior

Joystick controls include axis-lock options, hold durations, unlock behavior, scroll-wheel handling, and optional scroll-triggered input actions.

### System Events

Buttons can trigger supported system events, including brightness, volume, media, Launchpad, and Mission Control actions.

### Sub-Profile Switches

Special layer-switch controls can activate a nested layer from the overlay. These are persisted as generated `subProfileSwitch:` button identities.

### Opacity and Fade

Profiles can control overlay opacity. A global fade timeout can fade the overlay after inactivity, with menu options such as never, 3 seconds, 5 seconds, 10 seconds, and 30 seconds.

### Grouping, Snapping, and Alignment

The editor supports button grouping, group color changes, snapping, alignment commands, distribution commands, equal sizing, and marquee selection.

### Preview Canvas

The editor preview canvas renders the gamepad layout and supports selecting, dragging, resizing, group manipulation, alignment guides, and centered/legacy coordinate behavior.

### Local Persistence

Profiles and templates are stored in the user's Application Support directory. The storage helper also performs a one-time compatibility copy from the legacy `OnScreenGamepad` support directory when current files do not exist.

### First-Run Onboarding

The first-run SwiftUI onboarding flow introduces Click Play, shows bundled intro videos, and then moves the user to the Accessibility permission step.

### Update Checks

Click Play can check GitHub Releases for the latest version. Automatic checks are throttled, and manual checks can be opened from the status-bar menu.

### Caveats

Some games that capture the mouse may not work well with Click Play. Input latency can vary by game and system. Because keyboard injection uses `CGEvent`, Accessibility permission is required and App Sandbox must remain disabled for the current implementation.

## Codebase

### Project Layout

- `ClickPlay/`: main macOS app source, AppKit windows/controllers/views, SwiftUI onboarding/update views, entitlements, Info.plist, and app icon metadata.
- `ClickPlayShared/`: shared profile, template, persistence, and button identity models.
- `Media.xcassets/`: onboarding videos and menu bar/logo assets.
- `img/`: README and documentation image assets.
- `Click Play.xcodeproj/`: Xcode project, workspace metadata, and shared scheme.
- `README.md`: concise public landing page and quick-start guide.
- `LICENSE`: Apache License 2.0.
- `AGENTS.md`: contributor and agent instructions for safe development.

### How to Build

Open `Click Play.xcodeproj` in Xcode and build the `Click Play` scheme, or run:

```sh
xcodebuild -project "Click Play.xcodeproj" -scheme "Click Play" -configuration Debug build
```

Project facts:

- App target and scheme: `Click Play`
- Build configurations: `Debug`, `Release`
- macOS deployment target: `13.0`
- Bundle identifier: `com.TheOPBunny.ClickPlay`
- Signing: Apple Development signing is configured in the project
- Sandbox: App Sandbox must stay disabled for the current `CGEvent` injection approach

For reliable Accessibility/TCC behavior during development, use a stable signed app identity and run the same signed app path between launches.

### File Guide

#### `ClickPlay/main.swift`

The AppKit entry point. It creates the `AppDelegate`, assigns it to `NSApplication.shared.delegate`, and starts `NSApplicationMain`.

#### `ClickPlay/AppDelegate.swift`

Coordinates app lifetime, menu setup, status-bar behavior, Accessibility permission flow, onboarding, update checks, gamepad launch/show/hide, profile switching, editor launch, and editor command forwarding.

#### `ClickPlay/GamepadWindow.swift`

Defines the borderless non-activating `NSPanel` that hosts the gamepad. It owns overlay visibility, resize constraints, minimize state, opacity, inactivity fade behavior, global mouse monitoring, and profile reloads.

#### `ClickPlay/GamepadContentView.swift`

Hosts the translucent HUD, header controls, menu button, minimize/hide controls, background tint/blur, empty-space dragging, profile-based button layout, and joystick capture visibility behavior.

#### `ClickPlay/GamepadButtonView.swift`

Draws and handles one live overlay control. It manages mouse events, hover/pressed visuals, keyboard actions, system events, sub-profile switches, right-click input, joystick capture, axis lock, scroll actions, toggle-hold, turbo, sequential bindings, simultaneous bindings, and release cleanup.

#### `ClickPlay/KeyInjector.swift`

Serializes low-level keyboard injection through `CGEvent`. It tracks logical bindings and physical key ownership so duplicate key-downs are avoided and overlapping controls do not release each other's keys too early.

#### `ClickPlay/EditorWindowController.swift`

Owns the editor `NSWindow`, persists its frame, handles close/save confirmation, activates the editor app when shown, and forwards menu/status-bar commands into the editor controller.

#### `ClickPlay/EditorViewController.swift`

Builds the editor shell with a profile sidebar and button editor. It manages split-view layout, sidebar collapse persistence, profile selection, editor refreshes, save confirmation, and high-level add/remove/template commands.

#### `ClickPlay/ProfileListViewController.swift`

Controls the profile/layer sidebar. It supports selection, inline rename, drag/drop ordering, context menus, copy/paste, duplicate, delete, undo/redo, creating profiles/layers from templates, saving templates, and managing templates.

#### `ClickPlay/ButtonEditorViewController.swift`

Implements the main profile layout editor. It owns the preview canvas, inspector panel, editable profile copy, selected buttons/groups, clipboard, snapping, alignment/distribution/equalize commands, undo, dirty-state prompts, workspace sizing, and save behavior.

#### `ClickPlay/ButtonDetailPanel.swift`

Implements the inspector UI for profile settings, selected buttons, selected groups, key bindings, right-click input, joystick settings, system events, label style, shape, color, size, and delete actions.

#### `ClickPlay/GamepadPreviewView.swift`

Renders the editor canvas and handles direct manipulation. It draws buttons, groups, selection handles, alignment guides, and marquee selection, and reports normalized geometry changes back to the editor.

#### `ClickPlay/KeyRecorderButton.swift`

Reusable AppKit key recorder used by the inspector. It captures key-down and modifier-change events, records multiple bindings, supports modifier-only bindings, and displays the captured binding list.

#### `ClickPlay/FirstRunOnboardingView.swift`

SwiftUI onboarding flow shown before Accessibility permission is granted. It displays intro screens, loops bundled videos, and exposes actions for learning more or requesting permission.

#### `ClickPlay/UpdateChecker.swift`

Fetches the latest GitHub Release, parses version tags, compares them against the app version, and throttles automatic update checks through `UserDefaults`.

#### `ClickPlay/UpdateCheckView.swift`

SwiftUI update-check UI and view model. It displays checking, update available, up-to-date, and failure states, with actions to retry, dismiss, or open the release page.

#### `ClickPlay/SidebarToggleButton.swift`

Small reusable AppKit button that draws a native-looking split-view sidebar glyph for left or right sidebars.

#### `ClickPlay/DebugLog.swift`

Debug and latency logging helpers used throughout the app to keep diagnostic logging consistent.

#### `ClickPlay/Info.plist`

App metadata plist. It uses build settings such as the bundle identifier and app category values from the Xcode project.

#### `ClickPlay/ClickPlay.entitlements`

Entitlements file for the app target. The current injection approach requires App Sandbox to remain disabled.

#### `ClickPlay/ClickPlay.icon/`

Icon metadata and SVG source used by the app icon tooling.

#### `ClickPlayShared/KeyMapping.swift`

Defines `GamepadButton`, the stable button identity used as profile storage keys. It includes legacy/template buttons, generated button IDs, and generated sub-profile switch IDs.

#### `ClickPlayShared/Profile.swift`

Defines the persisted profile model and related types: button config, button actions, interaction modes, joystick config, system events, groups, sizing, coordinates, defaults, color helpers, profile normalization, and default templates.

#### `ClickPlayShared/ProfileStore.swift`

Owns profile and template persistence. It loads/saves JSON files, migrates from the legacy support directory when needed, resolves active profiles/layers, provides built-in templates, and exposes profile/layer/template mutation APIs.

#### `Media.xcassets`

Asset catalog containing first-run intro videos and image assets such as menu bar and logo variants.

#### `img/ClickPlay.png`

README and documentation image for the Click Play logo/preview.

#### `Click Play.xcodeproj`

Xcode project files, workspace metadata, and shared scheme for the `Click Play` app target.

## Planned Features

- Continue investigating and reducing input latency where possible.
- Add richer demo media and more complete user-facing docs as the project matures.
- Improve release packaging, signing, and first-launch polish.
- Expand profile, layer, template, and preset workflows.
- Add more built-in templates for common game/control styles.
- Explore future platform work, including possible Windows support.

## FAQ

### What is Click Play for?

Click Play is for games and workflows where a mouse-accessible overlay can stand in for keyboard controls. It is especially useful when you want custom on-screen controls while another app remains focused.

### Why does Click Play need Accessibility permission?

macOS requires Accessibility permission for apps that send input events to other apps. Click Play uses this permission to post keyboard events with `CGEvent`.

### Why must App Sandbox stay disabled?

The current keyboard injection approach relies on behavior that is not compatible with App Sandbox. Sandbox support would require a different input strategy.

### Where are profiles stored?

Profiles are stored at:

```text
~/Library/Application Support/Click Play/profiles.json
```

### Where are templates stored?

Templates are stored at:

```text
~/Library/Application Support/Click Play/templates.json
```

### What is the difference between a profile and a layer?

A profile is a top-level layout. A layer is a nested layout inside a profile that can be switched to from the overlay.

### What is the difference between a template and a profile?

A profile is an active saved layout. A template is reusable saved content that can create new profiles, layers, or groups.

### Why do some games not work well?

Games that aggressively capture the mouse or block synthetic input may not cooperate with Click Play. Fast-paced games can also expose latency or simultaneous-input limits.

### Is click-and-hold the main feature?

No. Click-and-hold is an important input safety primitive because it ensures controls press and release cleanly. Click Play as a whole is a customizable control-surface app with profiles, layers, joystick controls, templates, styling, editor tools, and system events.

### How do I build the app locally?

Use Xcode with the `Click Play` scheme, or run:

```sh
xcodebuild -project "Click Play.xcodeproj" -scheme "Click Play" -configuration Debug build
```

Use stable signing and a stable app path if you want Accessibility permission to persist across rebuilds.

### Does Click Play have tests?

There is currently no separate test target in the project. For now, validation is mostly build checks plus manual verification of overlay, input, editor, profile, template, joystick, and permission behavior.

## About Me

TODO: Add maintainer bio, project motivation, links, and preferred contact/support information.
