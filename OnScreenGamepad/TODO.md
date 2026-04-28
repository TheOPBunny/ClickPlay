# TODO

## Bugs

- [x] Fix jittery window dragging and make movement feel smooth and stable.
- [x] Add window resizing support for the gamepad overlay.
- [x] Make the toggle pill draggable when the gamepad is minimized into pill mode.
- [x] Investigate why Accessibility permission is prompted on every startup even after permission is granted.

Notes:
This was caused by unstable development signing rather than the app's Accessibility permission logic.

Fix:
Use a real Team, a stable bundle identifier, and a normal development signing identity instead of ad hoc/manual signing.
Run the app from a stable signed app path and grant Accessibility permission to that signed app once.

## Gamepad

- [x] Add a built-in drop-down menu for switching profiles.
- [x] Add transparency controls to that same menu instead of a separate transparency menu.
- [ ] Support layered profiles so a profile can contain sub-profiles.
- [ ] Add buttons on the gamepad to quickly swap between sub-profiles.
- [x] Add a per-profile "Compatibility Mode" that makes momentary button presses last 33 ms.
- [x] Add an option for buttons to toggle into a held-down state on press.
- [x] Fade the gamepad to 100% transparency after a configurable period of inactivity.
- [x] Use system corner dragging to resize.
- [x] Merge the old `GamepadConfigurator` workflow into `OnScreenGamepad`.
- [ ] Decide when to fully delete the archived standalone `GamepadConfigurator` fallback.

## Configurator

- [x] Remove size section because we can resize the gamepad manually.
- [x] Add an option to add a button.
- [x] Use system corner dragging to resize buttons, or allow entering dimensions in `px x px`.
- [x] Refactor configurator preview into a custom canvas editor model.
- [x] Add undo and redo support for button edits.
- [x] Add cut, copy, and paste support for buttons.
- [x] Add multi-select for buttons using drag selection or `Cmd`-click.
- [x] Add snapping and alignment guides.
- [x] Add the ability to group, align, and equalize a selected group of buttons.
- [x] Add a circle button shape.
- [x] Make the editing window larger and scale it with the application window size.
- [o] Allow side panels to collapse and be resized horizontally.
  - Fix the empty editor space by fitting the preview canvas horizontally when it runs out of visible content.
- [x] Update `KeyRecorder` so left-click starts listening for keys and another left-click stops listening.
- [x] Allow a button to be assigned multiple keys, for example `[xxaaa]` or `[abab]`.
- [x] If a button has multiple keys, add an option to activate them sequentially or simultaneously.
- [x] Add a "sticky" option so pressing a button keeps it held down until pressed again.
- [ ] Add a visual cue for buttons being toggle held.
- [x] Add a "turbo" option so pressing a button repeatedly sends its key until pressed again.
- [x] Center text on buttons.
- [ ] Investigate whether macOS Accessibility dwell actions can be activated.
- [x] If a label is empty, use the key as the label.
- [x] Add label styling controls for text size, bold, and italic.
- [ ] Fix button label vertical centering, especially in circle/oval buttons. Likely fix: stop centering by `NSAttributedString.size()` height alone and compute the text baseline from `NSFont.ascender`, `descender`, and `capHeight` in both the live button label view and configurator preview drawing.
- [ ] Add an option for right-click to activate a button, or to activate a different recorded key.
- [ ] Add full user template support: save current profile as a template, create profiles from saved templates, and manage saved templates.

Implemented:
- Button interaction mode control in the configurator with `Momentary` and `Toggle Hold`.
- Per-profile `Compatibility Mode` toggle in the configurator.
- Freeform `1000 × 1000` editor workspace with centered-origin support for new profiles.
- Live gamepad resize now updates runtime display size without changing editor button layout.

## Joystick Concept

- [ ] Design and prototype a virtual joystick mode.

Requirements:
- Pressing the joystick button should capture the mouse.
- The joystick should support 8-direction input.
- Moving the mouse toward a direction should activate that input.
- Releasing the joystick should return the mouse to the joystick deadzone.
- Right-click should release mouse capture.

## Miscellaneous

- [ ] Create and add an app icon.
- [ ] Pick a better product name.

## Notes

- Preserve current `KeyInjector` behavior as a compatibility boundary.
- New input features may extend the injection system, but they should not change the current press, hold, and release semantics without explicit approval.
