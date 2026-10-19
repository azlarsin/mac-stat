# Changelog

## Unreleased

- Added a `mac-stat` command to query and change settings from Terminal or SSH, including Keep Awake, popover visibility, menu bar items, and item order.
- Added JSON output, error exit codes, and a per-user CLI installer. Commands update the running app through a local Unix socket and persist through the normal settings logic.
- Added an Install Command Line Tool button in Settings, with installation feedback in English, Simplified Chinese, and Traditional Chinese.

## [1.6] — 2026-10-19

- Added a separate, persistent Keep Awake on Battery setting, disabled by default.
- Keep Awake now follows the AC and battery settings automatically when the power source changes.
- Added an independent, persistent Keep Awake with Lid Closed setting, disabled by default, that follows the AC and battery choices.
- Lid-closed mode now controls clamshell sleep through IOKit and restores normal behavior when disabled or when the main app exits unexpectedly.
- Added English, Simplified Chinese, and Traditional Chinese localization across settings, statistics, menus, status text, and error messages.

## [1.5] — 2026-09-07

- Added the battery charging speed, in watts, as configurable popover and menu bar items.
- CPU performance now falls back to macOS thermal pressure and Low Power Mode on Apple Silicon when a numerical speed limit is unavailable.

## [1.4] — 2026-07-23

- About panel: replaced the non-clickable `NSAlert` with a custom panel. The GitHub link is now `https://github.com/azlarsin/mac-stat` and opens in the browser when clicked.
- Added a persistent setting that runs `caffeinate -s` to keep the Mac awake on AC power.
- CPU throttle now displays `--` instead of an incorrect `100%` when thermal data is unavailable.

## [1.3] — 2026

- Battery menubar icon now tracks the real 0–100% charge fill.

## [1.2] — 2026

- Fixed the Select All menubar bug.
- Guaranteed a universal (arm64 + x86_64) binary in releases.

## [1.1] — 2026

- First signed, notarized, and stapled release via `release.sh`.

## [1.0] — 2026

- Initial release.
