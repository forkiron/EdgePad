# EdgePad — Claude Code project context

This file is loaded automatically by Claude Code at session start. It gives the assistant everything it needs to work on EdgePad without re-reading the whole codebase.

---

## What this project is

EdgePad is a macOS menu-bar utility that turns the edges of the MacBook trackpad into system controls.

Default (Auto) behavior:
- **Left edge** → volume (always)
- **Right edge** → brightness when watching media, vertical scroll otherwise
- **Top edge** → video scrub when watching media, otherwise no-op
- **Bottom edge** → horizontal scroll when not watching media, no-op otherwise (media takes priority over scroll, even on zoomed pages)

Manual profiles override Auto:
- **Media** — same as Auto with media context active
- **Reading** — right edge swaps to vertical scroll, bottom keeps horizontal scroll. Use for zoomed PDFs / Safari Reader / macOS Accessibility Zoom.

## Quick reference

- **Platform**: macOS 13.0 Ventura+ (developed on macOS 26)
- **Language**: Swift 6.0
- **UI**: AppKit for menu bar + overlay, SwiftUI for settings inside an `NSHostingView`
- **Architecture**: Single main-actor executable, no XPC helpers
- **Dependency manager**: Swift Package Manager (no external SPM deps)
- **License**: MIT

## Private frameworks (loaded via `dlopen` / `Bundle.load` at runtime)

| Framework | Purpose | Bound in |
|---|---|---|
| `MultitouchSupport.framework` | Raw per-finger trackpad coordinates | `MultitouchCapture.swift` |
| `DisplayServices.framework` | Read/write display brightness | `BrightnessController.swift` |
| `OSD.framework` (`OSDManager`) | Trigger the **real** macOS volume/brightness HUD | `NativeHUD.swift` |
| `MediaRemote.framework` | `MRMediaRemoteSendCommand` — skip-15 fallback for native media apps | `MediaRemote.swift` |
| `SkyLight.framework` | `SetsCursorInBackground` so cursor-hide works while we're a background accessory app | `AppDelegate.swift::enableBackgroundCursorHiding` |

**Important — multitouch device selection**: `MultitouchCapture.swift` enumerates devices via `MTDeviceCreateList` and starts only the ones with a real trackpad-sized sensor grid (≥10 rows). Do **not** call `MTDeviceCreateDefault()` — on Apple Silicon MacBooks it returns a 60×2 auxiliary sensor instead of the real trackpad and every coordinate is garbage. Do not pull in any third-party multitouch wrapper for the same reason.

**Important — MediaRemote on macOS 15.4+**: the read API (`MRMediaRemoteGetNowPlayingInfo`) is TCC-gated for non-Apple-signed processes and returns nil. Don't try to wire it up. The write API (`MRMediaRemoteSendCommand`) still works and is what we use for skip-15 in native music apps.

## Project structure

```
EdgePad/
├── Package.swift              # SPM manifest
├── Sources/                   # All Swift source
│   ├── main.swift             # Entry point (NSApplication.run)
│   ├── AppDelegate.swift      # Wires everything together; menu bar; cursor lock
│   ├── MultitouchCapture.swift   # Direct dlopen bindings to MultitouchSupport
│   ├── EdgeDetector.swift     # 4-edge classifier + drag state machine + intent / palm filters
│   ├── EdgeProfile.swift      # Profile types + Media/Reading presets
│   ├── ContextDetector.swift  # Auto-mode action resolution (per-edge, media-aware)
│   ├── ScrollDetector.swift   # AX-driven "is there scroll capability under cursor?" gate
│   ├── AudioActivity.swift    # CoreAudio "is anything making sound right now?" check
│   ├── AXScrubber.swift       # Find a video scrubber via AX (under cursor / focus walk-up)
│   ├── MediaRemote.swift      # Slim Swift binding to MRMediaRemoteSendCommand (write-only)
│   ├── VolumeController.swift    # CoreAudio volume read/write
│   ├── BrightnessController.swift # DisplayServices brightness read/write
│   ├── MediaController.swift  # Top-edge scrub: synthetic mouse drag → arrow keys → skip-15
│   ├── ScrollController.swift # CGEvent scroll posting
│   ├── NativeHUD.swift        # Triggers the real macOS HUD via OSDManager
│   ├── OverlayWindow.swift    # Custom HUD window for scrub feedback
│   └── SettingsPanel.swift    # SwiftUI menu views (sliders, mode picker)
├── Resources/
│   └── Info.plist
├── Tests/                     # EdgeDetector unit tests
├── scripts/codesign/          # Local signing helpers (not used in CI)
├── build.sh                   # SPM build + .app bundling + ad-hoc sign
├── README.md
├── CONTRIBUTING.md            # "Forks welcome, PRs not accepted"
├── LICENSE                    # MIT
└── CLAUDE.md                  # (this file)
```

## Top-edge scrub — three-mode cascade

Scrub uses the first method that works:

1. **Synthetic mouse drag** (`AXScrubber` + `MediaController.axSlider`): if AX finds a video scrubber under the cursor or up the focus chain, post `mouseDown → mouseDragged → mouseUp` at the slider's screen coordinates. The page sees a real user drag of its scrubber UI. Bypasses keyboard focus and per-site keybinding quirks. Cursor is hidden + disassociated; `MediaController.isDrivingCursor` tells AppDelegate to skip the per-frame warp during synthetic drag.

2. **Arrow keys** (`MediaController.arrowKeys`): velocity-amplified left/right arrow CGEvents to the focused app. Default fallback when no slider is visible. Works on YouTube, Vimeo, IINA, VLC, QuickTime — anything that binds Left/Right to seek.

3. **`MR.SendCommand` skip-15** (`MediaController.mediaSession`): used only when frontmost is in `AppDelegate.skipApps` (`com.apple.Music`, `com.apple.podcasts`, `com.apple.TV`, `com.spotify.client`). These ignore arrow keys but honor Now Playing transport commands.

Mode is picked once at drag-begin in `AppDelegate.edgeDetector(_:didBeginDragOn:_:)`. `MediaController.endScrub()` must be called from `didEndDragOn` — otherwise an open synthetic mouseDown leaks a "stuck button" into the focused page.

## Coding standards

### Swift
- Swift 6 strict concurrency on
- `@MainActor` on anything touching AppKit/UI
- Prefer value types (`struct`) for data models
- `final class` for reference types
- `guard` for early exits
- No force unwraps outside of tests
- `NSLog` with `[TAG]` prefixes for runtime logging (we run as a background accessory app and `print` doesn't reach Console.app reliably)
- No `print(...)` in shipped code

### AppKit + SwiftUI split
- **AppKit**: menu bar (`NSStatusItem`), overlay window (`NSWindow` + custom `NSView`), settings menu items
- **SwiftUI**: in-menu controls via `NSHostingView` wrapped into `NSMenuItem.view`

### File conventions
- One public type per file, filename matches type
- Group related types in the same file only when they're tightly coupled (≤ ~100 lines total)
- Doc comments on every public API (`///`)

## How to build and run

```bash
# Fast: SPM build only
swift build -c release

# Full: build + bundle into .app
./build.sh

# Build and launch
./build.sh dev

# Tests
swift test
```

First run requires Accessibility permission (System Settings → Privacy & Security → Accessibility). For local development with stable signing run `scripts/codesign/setup_local.sh` once.

## What NOT to do

- **Do not** add any third-party multitouch wrapper as an SPM dependency — they all call `MTDeviceCreateDefault()` which returns a useless auxiliary sensor on Apple Silicon. Bind the framework directly.
- **Do not** draw a custom volume/brightness HUD — call `NativeHUD.showVolume(_:)` / `NativeHUD.showBrightness(_:)`. We use Apple's real HUD, not a clone.
- **Do not** try to revive `MRMediaRemoteGetNowPlayingInfo` (read API). It's TCC-gated on macOS 15.4+ and returns nil for non-Apple-signed processes. Verified, documented, abandoned.
- **Do not** introduce `Combine` or `RxSwift` — the app is simple enough for delegate / async-await.
- **Do not** add `Electron`, `Tauri`, `Catalyst`, or any wrapped-web UI.
- **Do not** add telemetry, analytics, or network calls without an explicit user opt-in.
- **Do not** modify files in `.build/` — that's SPM's checkout directory.

## Common tasks

### Add a new edge action

1. Add the case to `EdgeAction` enum in `EdgeProfile.swift`
2. Create or extend a controller that implements the action
3. Wire the case in `AppDelegate.swift`'s `edgeDetector(_:didBeginDragOn:_:)` and `edgeDetector(_:didUpdate:)`
4. Update `EdgeProfile.media` / `EdgeProfile.reading` if the action should be in a default profile, and `ContextDetector.resolveAction(for:)` for Auto mode
5. Add a HUD `HUDKind` case in `OverlayWindow.swift` if it needs visual feedback (volume / brightness use `NativeHUD` instead)

### Tune scrub feel

`MediaController` exposes per-mode knobs: `arrowStepSize`, `skipStepSize`, `sliderTravelFraction`, `velocityScale`, `maxVelocityAmp`. The menu's Scrub slider edits `arrowStepSize` (= `stepSize` alias).

### Tune palm rejection

`EdgeDetector.palmSizeThreshold` (default 2.2 — fingertip ≈ 0.3–1.5, thumb ≈ 1.0–2.0, palm-rest ≈ 2.5+). Lower → stricter. Eccentricity-based rejection lives in `MultitouchCapture.swift::TouchSample`.

## Testing philosophy

- `EdgeDetector` is pure logic — test it with synthetic `TouchSample` sequences (`Tests/EdgeDetectorTests.swift`)
- Controllers that touch system APIs — manual smoke testing only, not in CI
- No UI automation
