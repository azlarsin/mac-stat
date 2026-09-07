# Changelog

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
