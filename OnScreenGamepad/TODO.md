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

## Features

- [ ] Add a built-in drop-down menu for switching profiles.
- [ ] Add transparency controls to that same menu instead of a separate transparency menu.
- [ ] Support layered profiles so a profile can contain sub-profiles.
- [ ] Add buttons on the gamepad to quickly swap between sub-profiles.
- [ ] Change button presses so button presses last 33 ms.
- [ ] Add an option for buttons to toggle into a held-down state on press.
- [ ] Fade the gamepad to 100% transparency after a configurable period of inactivity.
- [x] Merge the old `GamepadConfigurator` workflow into `OnScreenGamepad`.
- [ ] Decide when to fully delete the archived standalone `GamepadConfigurator` fallback.

## Configurator

- [ ] Remove size section because we can resize the gamepad manually.

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
