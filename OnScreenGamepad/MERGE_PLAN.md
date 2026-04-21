# OnScreenGamepad + GamepadConfigurator Merge Plan

## Goal

Merge `GamepadConfigurator` into `OnScreenGamepad` as part of a single macOS app bundle while keeping the runtime overlay window and the configurator/editor window as separate surfaces.

The target end state is:

- One app bundle and one signing/distribution pipeline.
- One shared model and persistence layer.
- One status bar utility that can open:
  - the non-activating on-screen gamepad overlay
  - a normal configurator/editor window
- No change to current `KeyInjector` press/hold/release semantics unless explicitly approved later.

## Non-Negotiable Constraints

- Preserve the current non-activating overlay behavior.
- Do not make the gamepad overlay key or main.
- Do not break button click-and-hold behavior.
- Do not break release-on-drag-off behavior.
- Do not change `KeyInjector` semantics during the merge.
- Keep profile persistence backward compatible with the current `profiles.json`.
- Avoid mixing editor-specific window behavior into the overlay code path.

## Recommended End-State Architecture

### App Surfaces

- `Overlay Runtime`
  - Status bar item
  - Accessibility permission flow
  - `GamepadWindow`
  - `GamepadContentView`
  - `GamepadButtonView`
  - `KeyInjector`

- `Editor Window`
  - Standard titled, closable, resizable AppKit window
  - Profile list
  - Button layout preview/editor
  - Button detail panel
  - Save/apply workflow

### Shared Core

- `Profile`
- `ButtonConfig`
- `ProfileStore`
- `GamepadButton`
- color helpers and profile migration/validation helpers

### Coordination Model

- The editor updates `ProfileStore`.
- `ProfileStore` continues posting `profilesDidChange`.
- The overlay listens for profile changes and reloads itself.
- The editor does not directly manipulate runtime overlay state.

This keeps the runtime and editor coupled through shared data, not through direct UI dependencies.

## Proposed Project Structure

This does not need to be the exact folder layout, but it should be close to this separation:

```text
OnScreenGamepad/
  Shared/
    Profile.swift
    ProfileStore.swift
    KeyMapping.swift
    Color+Hex.swift
  Runtime/
    AppDelegate.swift
    KeyInjector.swift
    GamepadWindow.swift
    GamepadContentView.swift
    GamepadButtonView.swift
  Editor/
    ConfiguratorWindowController.swift
    ConfiguratorViewController.swift
    ProfileListViewController.swift
    ButtonEditorViewController.swift
    GamepadPreviewView.swift
    ButtonDetailPanel.swift
    KeyRecorderButton.swift
  main.swift
```

The important point is separation by responsibility, not exact filenames.

## Migration Strategy

Implement this in phases. Do not try to collapse everything in one edit.

### Phase 1: Extract Shared Domain Code

Objective:
Remove duplicate model/persistence code first without changing product behavior.

Tasks:

- Compare `Profile.swift`, `ProfileStore.swift`, and `KeyMapping.swift` between both apps.
- Choose `OnScreenGamepad` as the source of truth, then reconcile any missing configurator-only behavior.
- Move shared files into a common location or shared target membership.
- Ensure both app targets build against the same shared files temporarily.

Success criteria:

- Both apps build.
- Both apps load and save the same profile data through the same implementation.
- No profile format change is introduced yet.

Notes:

- `OnScreenGamepad/ProfileStore.swift` already has `updateActiveProfileSize(width:height:)`, which should remain available after consolidation.
- Any future schema expansion should be done once in shared code, not in duplicated per-app copies.

### Phase 2: Import Editor UI Into OnScreenGamepad

Objective:
Bring configurator UI classes into the `OnScreenGamepad` codebase without changing overlay behavior.

Tasks:

- Copy or move configurator UI classes into the `OnScreenGamepad` project:
  - `ConfiguratorViewController`
  - supporting editor views/controllers
- Keep them isolated from runtime classes except through shared models/store.
- Add an editor window controller or equivalent owner object inside `OnScreenGamepad`.
- Confirm the editor window can open independently of the overlay.

Success criteria:

- `OnScreenGamepad` can open a normal editor window.
- The editor can load, edit, and save profiles.
- The overlay still behaves exactly as before.

Notes:

- The editor should remain a standard AppKit window.
- Do not reuse `GamepadWindow` for editing.

### Phase 3: Add Editor Entry Points To The Status Bar App

Objective:
Make the merged app usable as a single product.

Tasks:

- Add menu items such as:
  - `Edit Profiles…`
  - `Show Gamepad`
  - `Hide Gamepad`
  - `Profiles`
  - `Grant Accessibility Permission`
  - `Quit`
- Implement editor window opening/reuse logic so repeated menu actions focus the existing editor window instead of creating duplicates unless intentionally desired.
- Decide how app activation should work when opening the editor.

Success criteria:

- The editor window opens from the status bar menu.
- Opening the editor does not break overlay focus/input behavior.
- Closing the editor does not terminate the status bar utility.

### Phase 4: Resolve Activation Policy Cleanly

Objective:
Make the merged app feel like a real menu bar utility with a standard editor window.

Open question:

`OnScreenGamepad` currently sets `NSApp.setActivationPolicy(.accessory)`. That is appropriate for the menu bar utility, but the integrated editor may need foreground activation behavior.

Options to evaluate:

1. Stay `.accessory` permanently and explicitly activate when showing the editor window.
2. Temporarily switch activation policy when the editor opens.
3. Move to `.regular` and keep status bar behavior, if that does not create UX regressions.

Recommended approach to try first:

- Keep `.accessory`.
- When opening the editor window:
  - create/show the window
  - call `NSApp.activate(ignoringOtherApps: true)`
  - validate that the overlay remains non-activating and functional

Success criteria:

- Editor window comes forward reliably.
- Overlay remains usable while another app/game stays focused during runtime use.
- No unexpected Dock/menu-bar behavior appears unless explicitly chosen.

### Phase 5: Remove The Standalone Configurator App

Objective:
Finish the product merge after the integrated editor is stable.

Tasks:

- Remove `GamepadConfigurator` target from active development once confidence is high.
- Preserve the old target temporarily if needed as a fallback during transition.
- Update documentation and development workflow to point contributors to the merged app only.

Success criteria:

- One app is the supported product.
- No shared-code duplication remains.
- Build/sign/run flow is simpler than before.

Status:

- `OnScreenGamepad` is now the supported app.
- The standalone `GamepadConfigurator` project is no longer the active development path.
- The old project is currently retained only as an archived fallback until final deletion is explicitly chosen.

## Immediate Implementation Checklist

- [ ] Diff shared files across both apps and reconcile differences.
- [ ] Create a shared source area for models and persistence.
- [ ] Build both targets against shared files.
- [x] Move configurator UI classes into `OnScreenGamepad`.
- [x] Add an `Edit Profiles…` menu item to the status bar menu.
- [x] Create a dedicated editor window controller/owner in `OnScreenGamepad`.
- [x] Verify profile edits hot-reload the overlay through `profilesDidChange`.
- [x] Validate activation policy behavior with the integrated editor.
- [x] Remove the standalone configurator app from active development.

## Technical Decisions To Keep Explicit

These should be decided deliberately rather than drifting during implementation:

- Should the editor window be singleton-style or allow multiple windows?
- Should profile changes auto-save continuously or keep the current explicit save/apply behavior?
- Should profile switching in the editor immediately switch the live overlay, or only after save/apply?
- Should editor-only features remain inaccessible unless Accessibility permission is granted?
  - Likely no, because profile editing itself does not require injection.
- Should the merged app remain menu-bar-only, or eventually expose a Dock icon when the editor is open?

## Known Risks

- Activation policy conflicts between accessory-app behavior and normal editor UX.
- Accidental coupling where editor code starts depending on overlay classes.
- Input regressions if merge work leaks into `GamepadButtonView` or `KeyInjector`.
- Profile schema drift if future features are added before shared code is consolidated.
- Window lifecycle bugs such as multiple editor windows, orphaned controllers, or unwanted app termination behavior.

## Validation Plan

Validate after each phase, not just at the end.

### Runtime Validation

- Overlay launches from the status bar.
- Accessibility permission flow still works.
- Overlay remains non-activating.
- Button press, hold, and release behavior remains correct.
- Dragging off a pressed button still releases the key.
- Minimize/hide/show behavior still works.
- Resizing still updates the active profile correctly.

### Editor Validation

- Editor window opens reliably from the merged app.
- Profile list loads correctly.
- Editing button label, color, key, position, and size works.
- Saving persists to the existing `profiles.json`.
- Reopening the editor reflects saved state.

### Integration Validation

- Editing and saving a profile updates the live overlay.
- Switching active profile updates both menu state and overlay state.
- Closing the editor does not close the overlay or quit the app.
- Opening the editor does not interfere with runtime injection behavior.

## Recommendation

Proceed with the merge, but treat it as:

- one product
- one shared domain layer
- two separate windows
- strict isolation between editor UI and runtime overlay/input behavior

That approach matches the current coupling in the codebase while preserving the fragile parts of the runtime app.
