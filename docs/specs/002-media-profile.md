# Feature Specification: Media Profile

**Status**: Approved
**Priority**: P0
**PRD Reference**: Section 5, Feature 3
**Author**: Thomas Lenh
**Last Updated**: 2026-04-11

## Overview

The default EdgePad profile. Top edge scrubs video, left edge sets volume, right edge sets brightness, bottom edge scrolls horizontally.

## Edge → Action Map

| Edge | Action | Controller |
|---|---|---|
| Top | Video timeline scrub (arrow key steps) | `MediaController` |
| Left | System volume | `VolumeController` |
| Right | Display brightness | `BrightnessController` |
| Bottom | Horizontal scroll | `ScrollController` |

## Volume

### API
`CoreAudio` `AudioObjectSetPropertyData` on `kAudioDevicePropertyVolumeScalar`, scope `kAudioDevicePropertyScopeOutput`, element `kAudioObjectPropertyElementMain`. Fall back to per-channel (elements 1 and 2) if the master element is not supported.

### Control semantics
- Drag start: `startVolume = currentVolume()`
- Drag update: `newVolume = clamp(startVolume + delta * sensitivity, 0, 1)` then `setVolume(newVolume)`
- Default sensitivity: `1.2`
- HUD: volume icon + filled bar `[0, 1]`

### Acceptance
- [ ] Sliding the left edge from y=0.2 to y=0.8 changes volume by ~72% of range (0.6 × 1.2)
- [ ] Volume clamps cleanly at 0 and 1
- [ ] Works with internal speakers, Bluetooth output, AirPods, USB DACs
- [ ] HUD matches system volume HUD visual weight

## Brightness

### API
Private `DisplayServices.framework` → `DisplayServicesSetBrightness(CGDirectDisplayID, Float)`. Loaded via `dlopen` in `BrightnessController`. Read current via `DisplayServicesGetBrightness`.

### Fallback
If `DisplayServices` symbols are missing (future macOS break), fall back to posting `F1`/`F2` brightness media keys via `CGEvent`. This loses absolute-setting capability but still works.

### Control semantics
- Drag start: `startBrightness = currentBrightness()`
- Drag update: same delta formula as volume
- Default sensitivity: `1.2`
- HUD: sun icon + filled bar

### Acceptance
- [ ] Sliding the right edge changes brightness smoothly
- [ ] Works on Apple Silicon (MBP 14/16) and Intel (older MBPs)
- [ ] Works with built-in display; skip (no-op) on external displays until v1.1

## Video Scrub (Top Edge)

### Strategy
Post `CGEvent` left/right arrow keys to the focused app. Arrow keys work as scrub controls in:
- Safari (YouTube, Netflix, Twitch, Vimeo, any HTML5 `<video>`)
- Chrome, Firefox, Arc, Brave (same)
- VLC, IINA, QuickTime Player, Movist, Infuse
- Spotify desktop
- Apple Music
- Final Cut Pro (J-K-L), Premiere (same), Resolve

### Quantization
Edge drag is continuous (float), but arrow key steps are discrete. We accumulate delta and emit a key press each time the accumulator crosses `stepSize` (default 0.05, meaning ~5% edge travel = 1 step = ~5 seconds in most players).

```
accumulator += delta
while accumulator >= stepSize {
    postArrow(right: true)
    accumulator -= stepSize
}
while accumulator <= -stepSize {
    postArrow(right: false)
    accumulator += stepSize
}
```

Reset accumulator on drag start.

### HUD
Arrow pulse (`▶▶` or `◀◀`), alpha decays after each pulse. No value bar — scrub is relative.

### Known limitations
- Arrow key scrubbing is step-based, not frame-accurate. Most users don't care.
- Does not work in apps that steal arrow keys for navigation (e.g., some custom media players). Document.
- Does not work on YouTube if the page has focus on a search box instead of the video.

### Acceptance
- [ ] Scrubbing works in Safari YouTube, VLC, IINA, QuickTime, Spotify, Apple Music
- [ ] `stepSize` is configurable in settings
- [ ] No arrow keys are leaked if no video is playing (cost of posting keys to the focused app when there's nothing to scrub — acceptable, but document it)

## Horizontal Scroll (Bottom Edge)

### API
`CGEvent` scroll wheel event with horizontal delta in pixel units:

```swift
let event = CGEvent(
    scrollWheelEvent2Source: nil,
    units: .pixel,
    wheelCount: 2,
    wheel1: 0,                          // vertical (unused)
    wheel2: Int32(deltaPixels),         // horizontal
    wheel3: 0
)
event?.post(tap: .cghidEventTap)
```

### Control semantics
- Drag delta → pixels per frame
- Throttled to 60 events per second max
- Default sensitivity: screen width × 2 pixels per edge unit

### HUD
Horizontal arrow pulse, same as scrub but different icon.

### Acceptance
- [ ] Works in Safari (horizontal scroll on wide pages)
- [ ] Works in Preview (panning zoomed images)
- [ ] Works in Numbers, Excel, Google Sheets (wide tables)
- [ ] Works in Figma (canvas panning)
- [ ] Smooth, not jumpy

## Data Models

```swift
@MainActor
public final class VolumeController {
    public func currentVolume() -> Float
    @discardableResult public func setVolume(_ value: Float) -> Bool
}

@MainActor
public final class BrightnessController {
    public func currentBrightness() -> Float
    @discardableResult public func setBrightness(_ value: Float) -> Bool
}

@MainActor
public final class MediaController {
    public var stepSize: Float
    public func handleScrubDelta(_ delta: Float)
    public func resetAccumulator()
}

@MainActor
public final class ScrollController {
    public func scroll(horizontal: Float)
    public func scroll(vertical: Float)
}
```

## Testing Plan

- **Unit**: MediaController accumulator math (deterministic, no system calls)
- **Smoke**: each controller on a real MBP before merging
- **Manual matrix**:
  - YouTube in Safari, Chrome
  - Netflix in Safari
  - VLC, IINA, QuickTime Player
  - Spotify desktop
  - Numbers, Excel
  - Preview zoomed image
  - Figma canvas

## Open Questions

- [ ] Should we post `media-key-next`/`media-key-previous` HID events instead of arrow keys for better DAW/video-editor compatibility?
- [ ] Should horizontal scroll sensitivity scale with content width heuristically? (Probably no — too magic.)
- [ ] External display brightness support — deferred or in v1.0?
