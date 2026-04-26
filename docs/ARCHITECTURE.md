# Architecture

EdgePad is a single menu-bar executable. All components run in one process with one main-actor event loop. No XPC helpers, no background daemons, no launch agents. Simplicity is a feature.

---

## Layer diagram

```
┌──────────────────────────────────────────────────────────┐
│                      EdgePad.app                         │
│  ┌────────────────────────────────────────────────────┐  │
│  │                 AppDelegate (main)                 │  │
│  │  - NSStatusItem                                    │  │
│  │  - Profile state                                   │  │
│  │  - Settings persistence                            │  │
│  └────────────────┬───────────────────────────────────┘  │
│                   │                                      │
│  ┌────────────────▼───────────────────────────────────┐  │
│  │                 EdgeDetector                       │  │
│  │  classify(x, y) → (edge, axis)                     │  │
│  │  drag state machine: begin / update / end          │  │
│  └────────┬────────┬─────────┬────────┬────────┬──────┘  │
│           │        │         │        │        │        │
│  ┌────────▼──┐ ┌───▼──┐ ┌────▼───┐ ┌──▼────┐ ┌─▼──────┐  │
│  │  Volume   │ │Bright│ │ Media  │ │Scroll │ │Overlay │  │
│  │Controller │ │Contrl│ │ Scrub  │ │Contrl │ │ Window │  │
│  └────────┬──┘ └───┬──┘ └────┬───┘ └──┬────┘ └────────┘  │
│           │        │         │        │                 │
│           │        │         │        │                 │
│  ┌────────▼────────▼─────────▼────────▼──────────────┐   │
│  │             MultitouchCapture (service)          │   │
│  │   dlopen + dlsym on MultitouchSupport.framework  │   │
│  │   enumerates devices via MTDeviceCreateList      │   │
│  └────────────────────┬─────────────────────────────┘    │
└───────────────────────┼──────────────────────────────────┘
                        │
              ┌─────────▼──────────────────────┐
              │  /System/Library/PrivateFrame  │
              │  works/MultitouchSupport.frame │
              │  work (loaded at runtime)      │
              └────────────────────────────────┘
```

---

## Threading model

- **Main actor**: everything UI-facing (menu bar, overlay window, edge detector, controllers). Simple, no cross-actor data races.
- **Background**: `MultitouchSupport.framework` invokes our C callback on a private dispatch queue. We hop to main via `DispatchQueue.main.async` before touching any EdgePad state.

This is overkill-safe for a small app. Touch events come in at ~125 Hz max, which is nothing for the main queue.

---

## Data flow

1. The MT framework fires a touch frame on its private background queue.
2. `MultitouchCapture` hops to main and converts each `MTData` → lightweight `TouchSample`.
3. `EdgeDetector` classifies the sample and either ignores it (not an edge drag) or forwards an `EdgeDragEvent` to the active profile handler.
4. The profile handler routes the event to one of the controllers (`VolumeController`, `BrightnessController`, `MediaScrubController`, `ScrollController`).
5. The controller calls the appropriate system API and tells `OverlayWindow` what HUD to show.

---

## Key abstractions

### `TouchSample` (value type)
```swift
struct TouchSample {
    let x: Float           // normalized 0…1
    let y: Float           // normalized 0…1, 0 = bottom
    let pressure: Float    // 0…1 force-touch pressure
    let state: TouchState  // .starting / .touching / .ending / .other
    let timestamp: Double
}
```

### `TrackpadEdge`
```swift
enum TrackpadEdge { case top, bottom, left, right }
```

### `EdgeAction`
```swift
enum EdgeAction {
    case volume
    case brightness
    case mediaScrub
    case scrollVertical
    case scrollHorizontal
    case disabled
}
```

### `EdgeProfile`
```swift
struct EdgeProfile {
    var top: EdgeAction
    var left: EdgeAction
    var right: EdgeAction
    var bottom: EdgeAction

    static let media = EdgeProfile(
        top: .mediaScrub,
        left: .volume,
        right: .brightness,
        bottom: .scrollHorizontal
    )

    static let reading = EdgeProfile(
        top: .mediaScrub,
        left: .volume,
        right: .scrollVertical,
        bottom: .scrollHorizontal
    )
}
```

---

## Design decisions

### Why direct `dlopen` bindings instead of an SPM wrapper?

Every off-the-shelf Swift wrapper for `MultitouchSupport.framework` calls `MTDeviceCreateDefault()`. On Apple Silicon MacBooks that returns a 60×2 auxiliary sensor — not the real 26×18 trackpad — so every coordinate is unusable.

The fix is to enumerate devices with `MTDeviceCreateList` and pick the one with a real trackpad-sized sensor grid. That's ~80 lines of `dlopen`/`dlsym` in `MultitouchCapture.swift`, no SPM dependencies, and it works on every M-series Mac.

### Why relative-delta control instead of absolute?

Absolute ("touch at y=0.5 → volume=50%") is jarring. You'd slam volume to 50% on every touch. Relative ("starting value + (finger travel × sensitivity)") is how touchscreen sliders feel.

### Why single-finger only?

Multi-finger gestures are already claimed by the system (three-finger swipe, pinch to zoom, smart zoom, etc.). Edge drags are a layer on top of single-touch input specifically to avoid stepping on existing gestures.

### Why one executable, no helper process?

- Simpler distribution
- Simpler permissions (one app to grant Accessibility to)
- Simpler debugging
- Lower overhead
- We don't need privilege separation — the app doesn't do anything privileged

### Why not SwiftUI for the overlay?

For volume and brightness, we don't render anything ourselves — we call `[OSDManager showImage:onDisplayID:…filledChiclets:totalChiclets:locked:]` from the private `OSD.framework` and let macOS draw its real HUD. The user sees pixel-identical Apple chrome (same chiclets, same fade, same display) instead of a clone. See `Sources/NativeHUD.swift`.

For scrub and scroll, where macOS has no native HUD, we use AppKit `NSWindow` + custom `NSView.draw(_:)`. SwiftUI would force us into a `NSHostingView` with animation complications and extra overhead for a single 220×220 window. The HUD is pure Core Graphics, and it's fast.

We DO use SwiftUI for the settings window — that's where SwiftUI shines.

---

## Settings persistence

`AppSettings` is an `@Observable` class backed by `UserDefaults`. Keys:
- `edgepad.profile` (string: "media" / "reading" / "custom")
- `edgepad.enabled` (bool)
- `edgepad.edge.top.action` / `edgepad.edge.left.action` / etc (string)
- `edgepad.edge.top.sensitivity` / etc (float)
- `edgepad.edgeInset` (float, 0.05 – 0.15)
- `edgepad.typingSuppressionMs` (int, 0 – 500)
- `edgepad.launchAtLogin` (bool)
- `edgepad.telemetry.enabled` (bool, default false)

All writes go through `AppSettings` so the menu bar and the settings window stay in sync.

---

## Error handling

- **Framework load failure**: show a user-friendly alert, disable the app, offer an "Open System Settings" button, don't crash
- **Permission denied (Accessibility)**: prompt with the standard TCC request, re-check on `NSApplication.didBecomeActive`
- **Volume/brightness API failure**: log, skip the update, don't break the drag
- **Touch stream gap (> 500 ms)**: assume drag ended, reset state, clear overlay

No silent swallowing. Every error path logs to `os_log` with subsystem `com.thomaslenh.EdgePad`.

---

## Build system

- **Swift Package Manager** for dependency management + compilation
- **`build.sh`** wraps the SPM output binary into a proper `.app` bundle with `Info.plist` and ad-hoc code signature
- **Xcode project** (post v0.2): hand-generated or via `xcodegen` for advanced workflows (DMG creation, Sparkle integration, Developer ID signing)

The SPM path is the primary build path for developers. Xcode is an escape hatch for tasks SPM doesn't handle well.

---

## Testing strategy

- **Unit tests** for `EdgeDetector` — it's pure logic, no system APIs, easy to test with fake `TouchSample` streams
- **Controller smoke tests** — can we read/write volume, brightness, post arrow keys on the CI simulator? (skip when CI is headless)
- **Manual test matrix** for each supported app: Safari YouTube, VLC, QuickTime, IINA, Spotify, Preview zoom, Figma, Numbers

No UI automation in v1.0. The HUD is too bespoke for XCUITest to hit reliably, and the value isn't worth the complexity.
