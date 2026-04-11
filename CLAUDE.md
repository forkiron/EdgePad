# EdgePad — Claude Code project context

This file is loaded automatically by Claude Code at session start. It gives the assistant everything it needs to work on EdgePad without re-reading the whole codebase.

---

## What this project is

EdgePad is a macOS menu-bar utility that turns the edges of the MacBook trackpad into system controls: volume (left), brightness (right), video scrub (top), horizontal scroll (bottom). A Reading profile swaps brightness for vertical scroll on the right edge.

Full product spec: [docs/PRD.md](docs/PRD.md)
Architecture: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
Roadmap: [docs/ROADMAP.md](docs/ROADMAP.md)

## Quick reference

- **Platform**: macOS 13.0 Ventura+
- **Language**: Swift 6.0
- **UI**: AppKit for menu bar + overlay, SwiftUI for settings window
- **Architecture**: Single main-actor executable, no XPC helpers
- **Dependency manager**: Swift Package Manager
- **License**: MIT

## Key dependency

[`Kyome22/OpenMultitouchSupport`](https://github.com/Kyome22/OpenMultitouchSupport) (MIT, Swift 6 compatible). Provides `OMSManager.shared()` with an `AsyncStream<[OMSTouchData]>` of raw touch frames. **Do not attempt to replicate its dlopen bindings — use the library.**

## Project structure

```
EdgePad/
├── Package.swift              # SPM manifest
├── Sources/                   # All Swift source
│   ├── main.swift             # Entry point (NSApplication.run)
│   ├── AppDelegate.swift      # Wires everything together
│   ├── MultitouchCapture.swift   # Wraps OpenMultitouchSupport
│   ├── EdgeDetector.swift     # 4-edge classifier + drag state machine
│   ├── EdgeProfile.swift      # Profile types + Media/Reading presets
│   ├── VolumeController.swift    # CoreAudio volume read/write
│   ├── BrightnessController.swift # DisplayServices brightness read/write
│   ├── MediaController.swift  # Arrow-key scrub
│   ├── ScrollController.swift # CGEvent scroll posting
│   └── OverlayWindow.swift    # HUD window + custom NSView draw
├── Resources/
│   └── Info.plist
├── docs/
│   ├── PRD.md
│   ├── ARCHITECTURE.md
│   ├── ROADMAP.md
│   └── specs/                 # Per-feature specs
├── build.sh                   # SPM build + .app bundling + ad-hoc sign
├── README.md
└── CLAUDE.md                  # (this file)
```

## Coding standards

### Swift
- Swift 6 strict concurrency on
- `@MainActor` on anything touching AppKit/UI
- Prefer value types (`struct`) for data models
- `final class` for reference types
- `guard` for early exits
- No force unwraps outside of tests
- `os_log` with subsystem `com.thomaslenh.EdgePad` for all logging
- No `print(...)` in shipped code

### AppKit + SwiftUI split
- **AppKit**: menu bar (`NSStatusItem`), overlay window (`NSWindow` + custom `NSView`)
- **SwiftUI**: settings window, `@Observable` state, `NSHostingView` wrapped into an `NSWindow`

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
./build.sh run

# Tests
swift test
```

## What NOT to do

- **Do not** hand-roll `dlopen` bindings for `MultitouchSupport` — use `OpenMultitouchSupport`
- **Do not** introduce `Combine` or `RxSwift` — the app is simple enough for delegate/async-await
- **Do not** add `Electron`, `Tauri`, `Catalyst`, or any wrapped-web UI
- **Do not** add telemetry, analytics, or network calls without an explicit user opt-in
- **Do not** modify files in `.build/` — that's SPM's checkout directory
- **Do not** delete `docs/PRD.md` content to "simplify" — that's the spec we build against

## Common tasks

### Add a new edge action

1. Add the case to `EdgeAction` enum in `EdgeProfile.swift`
2. Create or extend a controller that implements the action
3. Wire the case in `AppDelegate.swift`'s `edgeDetector(_:didUpdate:)`
4. Update `EdgeProfile.media` / `EdgeProfile.reading` if the action should be in a default profile
5. Add a HUD `HUDKind` case in `OverlayWindow.swift` if it needs visual feedback

### Change an edge's sensitivity default

Edit `AppSettings.defaultSensitivity(for:)`. Persist in `UserDefaults`.

### Support a new video player for scrubbing

Arrow-key scrubbing works in most players automatically. If a player uses non-standard keys, extend `MediaController` to post player-specific keys based on the focused app's bundle ID.

## Testing philosophy

- `EdgeDetector` is pure logic — test it with synthetic `TouchSample` sequences
- Controllers that touch system APIs — smoke tests only, skip on CI
- No UI automation in v1.0

## Launch plan

See [docs/PRD.md#11-launch-strategy](docs/PRD.md#11-launch-strategy). Short version: Show HN + r/macapps + Product Hunt + Homebrew cask, all centered around a 2-second animated GIF of the top edge scrubbing a YouTube video.

## Memory imports

@import docs/PRD.md
@import docs/ARCHITECTURE.md
@import docs/ROADMAP.md
