# AGENTS.md

## Project Overview
Click Play is a macOS Swift/AppKit status-bar app that provides a customizable mouse-driven gamepad and control overlay for keyboard-driven games and workflows. It lets users build on-screen control surfaces with profiles, layers, templates, joystick controls, system events, visual styling, and local persistence.

The overlay is always-on-top and non-activating so another app or game can remain focused while users interact with Click Play. Keyboard input is injected with `CGEvent`, which requires Accessibility permission and currently requires App Sandbox to remain disabled.

This is a functional prototype that is growing into a richer editor-backed control system. Prefer improving the existing architecture over introducing major framework changes.

## Architecture
- `main.swift`: AppKit entry point; creates and keeps the app delegate alive for `NSApplicationMain`.
- `AppDelegate.swift`: app lifecycle, main/status menus, Accessibility permission flow, onboarding launch, gamepad launch/show/hide, editor commands, profile/layer switching, update checks.
- `GamepadWindow.swift`: borderless non-activating overlay panel, resizing constraints, minimize/hide behavior, opacity and inactivity fade handling, profile reloads.
- `GamepadContentView.swift`: translucent HUD container, header controls, background drag-to-move behavior, active-profile button layout, joystick capture visibility coordination.
- `GamepadButtonView.swift`: per-button mouse handling, visual state, keyboard/system/sub-profile actions, joystick capture, press/toggle/turbo/multi-key state machines, key injection triggers.
- `KeyInjector.swift`: low-level `CGEvent` keyboard posting, modifier chord handling, held-key ownership tracking, duplicate key-down protection, release-all cleanup.
- `EditorWindowController.swift`: editor window ownership, frame persistence, close/save confirmation, forwarding menu/status commands to the editor.
- `EditorViewController.swift`: editor shell with profile sidebar, button canvas, inspector split layout, sidebar persistence, save/navigation coordination.
- `ProfileListViewController.swift`: profile/layer sidebar, selection, rename, drag/drop ordering, copy/paste/duplicate/delete, template manager, undo.
- `ButtonEditorViewController.swift`: full layout editor; preview canvas, inspector, selection, clipboard, grouping, snapping, alignment/distribution, undo, dirty-state handling.
- `ButtonDetailPanel.swift`: inspector controls for profile visuals, button/layer settings, key bindings, right-click inputs, joystick inputs, system events, groups.
- `GamepadPreviewView.swift`: editor canvas rendering and interaction for selecting, dragging, resizing, marquee selection, groups, and alignment guides.
- `KeyRecorderButton.swift`: reusable key recorder control for capturing single-key, multi-key, modifier, and shortcut bindings in the editor.
- `FirstRunOnboardingView.swift`: SwiftUI first-run flow with intro media and Accessibility permission prompt.
- `UpdateChecker.swift`: GitHub Releases update lookup, version parsing, automatic-check throttling.
- `UpdateCheckView.swift`: SwiftUI update-check UI and view model.
- `SidebarToggleButton.swift`: reusable native-looking split-view sidebar toggle button.
- `DebugLog.swift`: debug and latency logging helpers.
- `../ClickPlayShared/KeyMapping.swift`: stable logical button identities and generated/sub-profile button keys.
- `../ClickPlayShared/Profile.swift`: profile, button config, joystick config, action, layout, color, and compatibility models.
- `../ClickPlayShared/ProfileStore.swift`: profile/template persistence, active profile/layer resolution, built-in templates, legacy storage migration, mutation APIs.
- `Media.xcassets`: onboarding videos and menu bar/logo image assets.
- `ClickPlay/ClickPlay.entitlements`: app entitlements; sandboxing must remain disabled for the current injection approach.

## Non-Negotiable Constraints
- The app must remain usable while another app or game stays focused.
- Do not accidentally make the gamepad window key or main.
- Do not break foundational press, hold, release, or drag-off release behavior for controls.
- `CGEvent` injection requires Accessibility permission.
- App Sandbox must remain disabled for the current injection approach to work.
- This is a Swift macOS app with AppKit-owned lifecycle/windowing. Use Swift and SwiftUI for new features and UI changes when practical, while preserving AppKit where required for the status item, non-activating overlay, editor integration, or other existing window behavior.

## Input Behavior Boundary
- Click-and-hold is a protected input primitive, not the whole product identity.
- Mouse interaction on controls must map cleanly to input down/up, including reliable release when a pointer exits, a profile reload happens, the overlay hides, or the app terminates.
- Preserve current behavior for momentary, toggle-hold, turbo, sequential multi-key, simultaneous multi-key, right-click, joystick, system event, and sub-profile switch actions unless the requested change explicitly targets that behavior.
- If a change could leave stale held keys, duplicate key-downs, lost mouse-up events, or unexpected focus changes, stop and call out the risk before implementing.

## Key Injector Stability Boundary
- `KeyInjector` behavior is a compatibility boundary for this project.
- You may expand the key injection system, but do not change how the current injector functions without explicit user approval.
- Preserve the current press, hold, and release semantics.
- Preserve the current duplicate-key-down protection for already held keys.
- Preserve the current expectation that mouse interaction on a button maps directly to key down and key up events.
- If a requested change would alter current injection behavior, stop and call out the behavior change clearly before implementing it.

## Behavior Expectations
- The overlay should stay above normal app windows and be available across Spaces and full-screen where possible.
- The overlay should remain non-activating; interacting with it should not steal keyboard focus from the target app/game.
- Hiding, minimizing, resizing, fading, showing, or reloading the gamepad should not lose internal state unexpectedly or leave inputs held.
- Dragging the gamepad should work only from empty background/header regions, not from button presses.
- Profile and layer changes should reload the UI without requiring app restart.
- Editor save, dirty-state confirmation, undo/redo, sidebar selection, and profile navigation should protect unsaved work.
- Template creation, insertion, renaming, deletion, and built-in templates should preserve profile compatibility and avoid unsafe sub-profile switch references.
- Joystick capture should hide/release/restore cursor and inputs reliably, including axis-lock and scroll-wheel interactions.
- Opacity and fade settings should affect overlay presentation without changing input semantics.
- First-run onboarding and Accessibility permission flows should guide users without blocking already-authorized launches.
- Update checks should be non-blocking and should not prevent normal app use when unavailable or failed.

## Data and Persistence
- Profiles are stored at `~/Library/Application Support/Click Play/profiles.json`.
- Templates are stored at `~/Library/Application Support/Click Play/templates.json`.
- Storage lookup also performs a one-time compatibility copy from the legacy `~/Library/Application Support/OnScreenGamepad/` directory when current files do not exist.
- Preserve backward compatibility for saved profiles and templates unless a migration is intentionally added.
- Keep `GamepadButton.rawValue` stable unless there is a deliberate migration plan, because profile button configs are keyed by those values.
- Generated button IDs and `subProfileSwitch:` IDs are persisted data; do not rewrite them casually.

## Code Change Guidelines
- Prefer small, targeted edits over refactors.
- Preserve the current separation of responsibilities between lifecycle, windowing, rendering, editing, injection, and persistence.
- Avoid changing public behavior outside the requested task.
- Keep debug logging unless removing or reducing it is part of the task.
- Use Swift and SwiftUI for new feature/UI work when practical, and use AppKit-native patterns where they are already responsible for lifecycle, windowing, status menus, overlay behavior, or editor behavior.
- Default to native macOS and industry-standard UI/UX elements and interaction patterns unless the user explicitly requests something custom.
- Unless the user explicitly says otherwise, always do active development on the `dev` branch.
- If work begins on another branch by mistake, stop and resolve branch state before continuing.
- Make a commit after every discrete change unless the user explicitly says not to.
- Keep `main` as the stable branch unless the user explicitly asks for a merge or release step.
- When updating `CHANGELOG.md`, include only code changes and write entries in simple, human language.

## Validation
After making changes, validate the relevant behaviors:
- Project builds successfully.
- App launches from the status bar.
- Accessibility permission flow still works.
- Overlay remains non-activating and does not steal focus from the target app/game.
- Buttons press, hold, and release correctly.
- Dragging the mouse off a pressed button releases the key.
- Toggle-hold, turbo, multi-key, right-click, system event, sub-profile switch, and joystick controls still behave as expected when affected by the change.
- Gamepad window drag behavior still works.
- Hide/show, minimize/restore, resize, opacity, and fade behavior still work.
- Profile and layer switching reloads the layout correctly.
- Editor save/dirty-state prompts, profile/layer sidebar behavior, template management, grouping, snapping, and inspector edits still work when affected by the change.
- Profile/template persistence remains backward compatible.

For documentation-only changes, validate that the relevant instructions remain accurate and that all non-negotiable safety constraints are still represented; a build is not required unless source or project behavior changes.

## Development Setup
- For reliable Accessibility/TCC behavior during development, use a stable signed app identity.
- Set a real Team in Xcode signing settings.
- Use a stable bundle identifier instead of the placeholder identifier.
- Do not rely on ad hoc/manual signing if you want Accessibility permission to persist across rebuilds.
- Prefer running the same signed app path between launches when validating `CGEvent` injection behavior.

## Notes for Agents
- Assume this is a prototype that will evolve, so clarity and maintainability matter.
- Treat click-and-hold as a foundational input safety behavior while recognizing Click Play as a broader configurable control-surface app.
- If changing input behavior, be conservative and reason through edge cases like lost mouse-up, duplicate press, stale held keys, joystick capture release, and profile reload during active input.
- If changing profile shape, template shape, stored IDs, or stored values, call that out explicitly and preserve compatibility where possible.
- If a requested change conflicts with overlay, focus, injection, persistence, or editor constraints, explain the tradeoff before proceeding.
