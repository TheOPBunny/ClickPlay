# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

### Added

- Added Virtual Cursor Mode, a per-profile option for controlling the overlay while the physical pointer stays in place. [See more...](docs/index.md#virtual-cursor-mode)
- Added up to five nested joystick layers that can be switched with joystick click and scroll actions. [See more...](docs/index.md#nested-joystick-layers)
- Added an on-screen HUD that shows joystick bindings and active actions during capture. [See more...](docs/index.md#joystick-capture-hud)
- Added configurable turbo rates from 1 to 30 clicks per second for buttons, right-click actions, and joystick inputs. [See more...](docs/index.md#turbo-mode)

### Changed

- Profile settings are now grouped in a toolbar popover in the editor. [See more...](docs/index.md#profile-settings)

## [1.4.0] - 2026-05-25

### Added

- Added Dwell Action buttons for mouse clicks, double click, mouse holds, and scrolling. [See more...](docs/index.md#dwell-actions)
- Added Dwell Action inspector settings for action type, timer duration, movement tolerance, and icon size.

### Changed

- The inspector now shows clearer unit labels for dwell timing, movement tolerance, and button position fields.

## [1.3.0] - 2026-05-24

### Added

- The gamepad overlay can now show a pointer location ring for games that hide the mouse, saved per profile. [See more...](docs/index.md#show-pointer-location)

### Changed

- Button hover outlines now update more responsively, including while the system is under load.

## [1.2.0] - 2026-05-23

### Added

- The editor canvas now supports zooming in and out from the toolbar and View menu.
- The editor remembers the last canvas zoom level across launches.

### Changed

- Canvas movement and sizing now stay aligned to whole-pixel positions while editing controls.

## [1.1.0] - 2026-05-19

### Added

- Click Play now shows the update window when it finds a new version.
- You can now skip an update version if you do not want to be reminded about it again.

### Changed

- The update window has simpler buttons after a check finishes.
