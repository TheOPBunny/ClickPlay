# AGENTS.md

## Project Overview
OnScreenGamepad is a macOS AppKit status-bar utility that displays an always-on-top on-screen gamepad. Users click and hold buttons with the mouse, and the app injects keyboard events into other apps and games using `CGEvent`.

This is currently a functional prototype. Prefer improving the existing architecture over introducing major framework changes.

## Architecture
- `OnScreenGamepad/main.swift`: App entry point.
- `OnScreenGamepad/AppDelegate.swift`: app lifecycle, status bar item and menu, Accessibility permission flow, gamepad launch/show/hide, profile switching.
- `OnScreenGamepad/GamepadWindow.swift`: borderless non-activating overlay panel and toggle pill window.
- `OnScreenGamepad/GamepadContentView.swift`: translucent HUD container, drag-to-move behavior, button layout from active profile.
- `OnScreenGamepad/GamepadButtonView.swift`: per-button mouse handling, pressed state, visual updates, key injection trigger.
- `OnScreenGamepad/KeyInjector.swift`: low-level keyboard event posting and held-key tracking.
- `OnScreenGamepad/KeyMapping.swift`: logical button identities.
- `OnScreenGamepad/Profile.swift`: profile and button config models, default layout, color helpers.
- `OnScreenGamepad/ProfileStore.swift`: profile persistence and active profile management.

## Non-Negotiable Constraints
- The app must remain usable while another app or game stays focused.
- Do not accidentally make the gamepad window key or main.
- Do not break click-and-hold behavior for buttons.
- Do not break release behavior when dragging off a button.
- `CGEvent` injection requires Accessibility permission.
- App Sandbox must remain disabled for the current injection approach to work.
- This is an AppKit app. Do not introduce SwiftUI unless explicitly requested.

## Key Injector Stability Boundary
- `KeyInjector` behavior is a compatibility boundary for this project.
- You may expand the key injection system, but do not change how the current injector functions without explicit user approval.
- Preserve the current press, hold, and release semantics.
- Preserve the current duplicate-key-down protection for already held keys.
- Preserve the current expectation that mouse interaction on a button maps directly to key down and key up events.
- If a requested change would alter current injection behavior, stop and call out the behavior change clearly before implementing it.

## Behavior Expectations
- The overlay should stay above normal app windows and be available across Spaces and full-screen where possible.
- Mouse interaction on buttons should map cleanly to key down and key up.
- Held keys must not repeat duplicate key-down events while already held.
- Hiding and showing the gamepad should not lose internal state unexpectedly.
- Dragging the gamepad should work only from empty background, not from button presses.
- Profile changes should reload the UI without requiring app restart.

## Data and Persistence
- Profiles are stored at `~/Library/Application Support/OnScreenGamepad/profiles.json`.
- Preserve backward compatibility for saved profiles unless a migration is intentionally added.
- Keep `GamepadButton.rawValue` stable unless there is a deliberate migration plan, because profile button configs are keyed by those values.

## Code Change Guidelines
- Prefer small, targeted edits over refactors.
- Preserve the current separation of responsibilities between lifecycle, windowing, rendering, injection, and persistence.
- Avoid changing public behavior outside the requested task.
- Keep debug logging unless removing or reducing it is part of the task.
- Use AppKit-native patterns already present in the codebase.
- Do active development on the `dev` branch.
- Make regular, incremental commits on `dev` as work progresses.
- Keep `main` as the stable branch unless the user explicitly asks for a merge or release step.

## Validation
After making changes, validate the relevant behaviors:
- Project builds successfully.
- App launches from the status bar.
- Accessibility permission flow still works.
- Buttons press, hold, and release correctly.
- Dragging the mouse off a pressed button releases the key.
- Gamepad window drag behavior still works.
- Toggle pill hide and show works.
- Profile switching reloads the layout correctly.

## Development Setup
- For reliable Accessibility/TCC behavior during development, use a stable signed app identity.
- Set a real Team in Xcode signing settings.
- Use a stable bundle identifier instead of the placeholder identifier.
- Do not rely on ad hoc/manual signing if you want Accessibility permission to persist across rebuilds.
- Prefer running the same signed app path between launches when validating `CGEvent` injection behavior.

## Notes for Agents
- Assume this is a prototype that will evolve, so clarity and maintainability matter.
- If changing input behavior, be conservative and reason through edge cases like lost mouse-up, duplicate press, and stale held keys.
- If changing profile shape or stored values, call that out explicitly.
- If a requested change conflicts with overlay, focus, or input constraints, explain the tradeoff before proceeding.
