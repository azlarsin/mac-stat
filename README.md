<p align="center">
  <img src="docs/icon.png" width="96" alt="MacStat">
</p>

<h1 align="center">MacStat</h1>

<p align="center">
  A no-frills macOS menubar monitor. Live stats, zero clutter.
</p>

<p align="center">
  <img src="docs/screenshots/menubar.png" alt="Menubar">
</p>

---

## What it shows

Pick exactly what appears in your menubar and popover — everything is toggleable and reorderable.

| | |
|---|---|
| **Temperature** | CPU · GPU · Battery |
| **CPU** | Usage % · Thermal state / speed limit · Low Power Mode |
| **Memory** | Used GB or % |
| **Fan** | RPM or % |
| **Network** | Download · Upload |
| **Disk** | Free space · Read / write speed |
| **Battery** | Charge % · Charging speed (W) |

Settings include three persistent Keep Awake checkboxes:

- **Keep Awake on AC Power** — prevent system sleep while plugged in.
- **Keep Awake on Battery** — prevent idle system sleep on battery (off by default).
- **Keep Awake with Lid Closed** — also prevent lid-close sleep on the selected power sources (off by default). For example, select AC Power and Lid Closed to keep running with the lid closed only while plugged in; also select Battery to allow it when unplugged.

The display can still turn off. Lid-closed mode uses IOKit's undocumented `kPMSetClamshellSleepState` interface ([Apple's implementation](https://github.com/apple-oss-distributions/xnu/blob/main/iokit/Kernel/RootDomainUserClient.cpp)), without administrator privileges or changing `pmset` preferences. A helper restores lid-close sleep when the option is disabled or MacStat exits, including an unexpected exit of the main app. If macOS rejects the interface, MacStat unchecks the lid option and shows an error. Physical lid behavior may vary with hardware and macOS versions.

The interface follows your macOS language preference and supports English, Simplified Chinese, and Traditional Chinese.

## Screenshots

<p align="center">
  <img src="docs/screenshots/popover.png" width="260" alt="Popover">
  &nbsp;&nbsp;
  <img src="docs/screenshots/settings.png" width="260" alt="Settings">
</p>

## Install

1. Download `MacStat.dmg` from [Releases](https://github.com/azlarsin/mac-stat/releases)
2. Open the DMG and drag **MacStat** to `/Applications`
3. Launch — it lives quietly in your menubar

> Installing to `/Applications` is required for **Launch at Login**.

**Requirements:** macOS 13 Ventura or later · Intel & Apple Silicon

## Build from source

```bash
xcodebuild \
  -project MacStat/MacStat.xcodeproj \
  -scheme MacStat \
  -configuration Debug \
  build \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO
```

## Author

[azlar](https://github.com/azlarsin)
