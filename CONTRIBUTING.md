# Contributing to Click Play

Contributions of any size are welcome — bug reports, documentation fixes, feature suggestions, and pull requests all help.

## Ways to contribute

- **Report bugs or crashes**, including cases where Click Play behaves unexpectedly with a particular game or workflow.
- **Suggest improvements** to the overlay, editor, profiles, templates, onboarding/accessibility flow, documentation, or update experience.
- **Improve documentation** — examples, setup notes, and troubleshooting guidance are just as valuable as code.
- **Submit pull requests** that fix bugs, improve reliability, or add well-scoped features.

When opening an issue, include a clear title, appropriate labels, and a detailed description. For bug reports, add steps to reproduce, the app version, and the macOS version.

## Before you start

For anything beyond a small, isolated fix, open an issue or discussion first so we can align on intended behavior before you invest time in implementation. This matters most for changes that touch keyboard injection, overlay focus behavior, profile persistence, templates, or editor save/navigation flows.

### Core constraints

Click Play has several constraints that must be preserved across all changes:

- The overlay must remain usable while another app or game retains focus.
- The overlay must be non-activating — it must not become the key or main window during normal interaction.
- Button press, hold, release, and drag-off-release behavior must remain reliable.
- Keyboard injection uses `CGEvent`, requires macOS Accessibility permission, and currently requires App Sandbox to remain disabled.
- Saved profiles and templates must remain backward compatible unless a migration is intentional and documented.

## Development setup

1. Clone the repository.
2. Open `Click Play.xcodeproj` in Xcode.
3. Select the shared scheme and build and run the macOS app.
4. Grant Accessibility permission when prompted by macOS.
5. For reliable local testing, use a stable signed app identity, bundle identifier, and app path so Accessibility/TCC permissions persist across rebuilds. Without this, macOS will invalidate permissions on each rebuild.

There are no automated tests. Changes should be verified manually using the checklist below.

### Storage locations

Profiles: `~/Library/Application Support/Click Play/profiles.json`  
Templates: `~/Library/Application Support/Click Play/templates.json`

Keep backup copies of these files before testing persistence changes if you have layouts you care about.

### Branch naming

No strict convention is enforced, but `fix/short-description` and `feat/short-description` are preferred for clarity.

## Code guidelines

- Prefer small, targeted changes over broad refactors.
- Preserve the existing separation between app lifecycle, overlay/window behavior, rendering, editor logic, key injection, and persistence.
- Use Swift and SwiftUI where practical, while preserving AppKit-owned behavior for non-activating windows, editor integration, and overlay rendering.
- Keep `GamepadButton.rawValue`, generated button IDs, and `subProfileSwitch:` IDs stable unless there is a deliberate compatibility plan.
- Do not change `KeyInjector` press/hold/release semantics, duplicate-key protection, or held-key ownership without clearly documenting the behavioral impact.
- Keep existing debug logging unless a change specifically adjusts logging behavior.
- Avoid unrelated formatting churn.

## Pull request checklist

All pull requests should at minimum confirm:

- [ ] The project builds successfully in Xcode.
- [ ] The app launches from the menu bar.
- [ ] The Accessibility permission flow still works.

Verify the following when your change could affect them:

**Overlay and input**
- [ ] The overlay remains non-activating and does not steal focus from the target app or game.
- [ ] Buttons press, hold, release, and drag-off-release correctly.
- [ ] Toggle-hold, turbo, multi-key, right-click, system event, sub-profile switch, and joystick behavior still work.

**Window management**
- [ ] Hide/show, minimize/restore, resize, opacity, fade, profile switching, and layer switching still work.

**Editor**
- [ ] Save prompts, undo/redo, sidebar selection, template management, grouping, snapping, and inspector edits still work.

**Persistence**
- [ ] Profile and template data remains backward compatible.

**Documentation**
- [ ] Documentation is updated when user-facing behavior changes.

Documentation-only changes do not require a full app build unless they describe behavior that should be verified against the app.

## Commit and PR style

- Keep each pull request focused on one change.
- Write a short summary of what changed and why.
- Note anything that could affect input safety, window focus, saved data, or compatibility.
- Include screenshots or short recordings for visible UI changes.
- Include manual test notes for input, overlay, editor, or persistence changes.

## AI-assisted contributions

AI-assisted contributions are welcome. Contributors are responsible for understanding, testing, and standing behind the code or documentation they submit — review it as carefully as you would anything you wrote yourself.

## License

By contributing to Click Play, you agree that your contributions will be licensed under the project's [Apache License 2.0](LICENSE).
