# EdgePad

> **The Touch Bar Apple killed, built into the trackpad you already have.**

EdgePad turns the edges of your MacBook trackpad into system controls. Drag along the top edge to scrub a video. Drag along the left edge to set volume. Drag along the right edge to set brightness. Drag along the bottom edge to pan horizontally through zoomed images, wide spreadsheets, or accessibility Zoom.

A separate **Reading mode** turns the right edge into a vertical scroller — so you can pan zoomed PDFs, magnified Safari pages, and macOS Zoom without ever mouse-reaching for the screen edges.

Free. Open source. MIT licensed. 10 MB. 20 MB of RAM. Pure Swift.

<!-- TODO: drop a 2-second loop GIF here that shows top-edge scrubbing a YouTube video in Safari. This GIF is the most important asset in the whole launch. -->

---

## Why

Apple removed the Touch Bar from the MacBook Pro in 2023. The scrub bar, the volume slider, the brightness slider — all gone, with no replacement. Meanwhile the trackpad kept getting bigger.

EdgePad puts those controls back, on a surface every MacBook already has. No new hardware. No dongles. No Electron. Just the edges of the trackpad you're already touching.

### What it replaces

| Before | With EdgePad |
|---|---|
| Tap `F11` / `F12` for volume (16 discrete steps) | Slide the left edge — precise, continuous |
| Tap `F1` / `F2` for brightness (same) | Slide the right edge |
| Click the YouTube/Netflix/VLC timeline with the mouse | Slide the top edge |
| Shift+scroll-wheel for horizontal scroll (clunky) | Slide the bottom edge |
| Mouse to the screen edge to pan macOS Zoom | Switch to Reading mode and use right+bottom edges |

---

## Features

- **Top-edge video scrub** — works in Safari (YouTube, Netflix, Twitch), VLC, QuickTime, IINA, Spotify desktop, and basically anything that responds to arrow keys
- **Left-edge volume** — continuous, precise, via CoreAudio
- **Right-edge brightness** — same, via `DisplayServices`
- **Bottom-edge horizontal scroll** — for wide Numbers sheets, Figma canvases, zoomed images in Preview, long DAW/NLE timelines
- **Reading mode** — toggle via menu bar or `⌃⌥⌘R`. Right edge becomes a vertical scroller, for zoomed PDFs, magnified web pages, and macOS accessibility Zoom
- **Relative-delta control** — drags add to the _current_ value, so nothing jumps when you touch the edge
- **Typing-aware dead zones** — edge gestures are suppressed for 300 ms after any key press, to kill accidental triggers
- **Minimal native HUD** — looks like a system volume HUD, not a third-party overlay
- **Menu-bar only** — no dock icon, no windows, no distraction. Runs in the background, 20 MB of RAM
- **No network** — zero telemetry, zero analytics, zero update pings unless you turn them on
- **Open source** — MIT licensed, pure Swift, no hidden dependencies

---

## System requirements

- **macOS 13 Ventura** or later
- **Apple Silicon or Intel** (both supported)
- **Built-in MacBook trackpad** (external Magic Trackpad also supported)

---

## Installation

### Option 1: Download the DMG (recommended once we cut a release)

1. Download the latest `EdgePad.dmg` from [GitHub Releases](https://github.com/thomaslenh/EdgePad/releases/latest)
2. Open it and drag **EdgePad** to `/Applications`
3. Launch EdgePad from `/Applications`
4. Grant Accessibility permission when prompted (System Settings → Privacy & Security → Accessibility)
5. **Pre-release note**: while we're still alpha, the app is ad-hoc signed instead of Developer-ID signed. macOS will warn you it's from an "unidentified developer." Run this in Terminal to clear the quarantine flag:

   ```bash
   xattr -dr com.apple.quarantine /Applications/EdgePad.app
   ```

### Option 2: Homebrew cask _(coming in v1.0)_

```bash
brew install --cask thomaslenh/edgepad/edgepad
```

### Option 3: Build from source

See [Building from source](#building-from-source) below.

---

## Usage

1. Launch EdgePad. The `◱` icon appears in your menu bar.
2. Make sure a video is playing (for scrubbing) or you have a video open in a supported player.
3. **Drag the top edge of your trackpad horizontally** — the video scrubs backward or forward.
4. **Drag the left edge vertically** — system volume changes.
5. **Drag the right edge vertically** — display brightness changes.
6. **Drag the bottom edge horizontally** — the focused app scrolls horizontally (try a wide Numbers sheet or a zoomed image in Preview).

### Reading mode

Click the menu bar icon and toggle **Reading mode**, or press `⌃⌥⌘R`. The right edge becomes a vertical scroller. Perfect for:
- Reading a zoomed PDF
- Panning a magnified Safari page (`⌘+`)
- Panning around when macOS Accessibility Zoom is active

Toggle back to **Media mode** the same way to restore brightness on the right edge.

### Customization

Click the menu bar icon → **Settings** to change:
- What action each edge performs
- Sensitivity per edge
- How far from the edge the activation zone starts (default 10%)
- How long to suppress edge gestures after typing (default 300 ms)

---

## How it works

EdgePad uses [Kyome22/OpenMultitouchSupport](https://github.com/Kyome22/OpenMultitouchSupport) (MIT) to stream raw per-finger coordinates from Apple's private `MultitouchSupport.framework`. This is the same technique used by BetterTouchTool, TrackWeight, Jitouch, and countless others. The Swift library handles the dlopen plumbing so EdgePad doesn't have to.

The `EdgeDetector` classifies each touch sample. If a contact lands inside one of four edge strips (default 10% inset from each side), it opens a drag. Subsequent samples from the same finger update the drag's position. When the finger lifts, the drag ends.

System state changes go through public macOS APIs:

| Action | API |
|---|---|
| Volume read/write | `CoreAudio` → `kAudioDevicePropertyVolumeScalar` on the default output device |
| Brightness read/write | Private `DisplayServices.framework` via `dlopen` — same entry point macOS System Settings uses |
| Video scrub | `CGEvent` posting `←` and `→` keys to the focused app |
| Horizontal / vertical scroll | `CGEvent` scroll wheel events, pixel units, posted to the focused app |

The HUD overlay is a borderless `NSWindow` with a custom `NSView.draw(_:)` that renders an `NSBezierPath` rounded rect, icon glyph, and value bar in ~1ms per frame. Click-through (`ignoresMouseEvents = true`), always on top, auto-hides after 0.9 seconds.

For the full design, read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). For the spec, read [docs/PRD.md](docs/PRD.md).

---

## Building from source

### Prerequisites

- **macOS 13+**
- **Swift 6.0+** (ships with Xcode 16+, or install standalone toolchain)
- **Xcode Command Line Tools** — `xcode-select --install`

### Build

```bash
git clone https://github.com/thomaslenh/EdgePad.git
cd EdgePad
./build.sh              # produces build/EdgePad.app
./build.sh run          # build + launch
```

What `build.sh` does:

1. Runs `swift build -c release` (pulls OpenMultitouchSupport from SPM)
2. Copies the binary into `build/EdgePad.app/Contents/MacOS/EdgePad`
3. Writes `Info.plist`
4. Ad-hoc signs (`codesign --force --sign -`)

You can also use Xcode: `open Package.swift` → run with `⌘R`. SPM targets open as Xcode workspaces on Xcode 16+.

### Run tests

```bash
swift test
```

Tests cover `EdgeDetector` state transitions and profile assignment. System controllers are smoke-tested only (they need a real output device and accessibility permission).

---

## Roadmap

See [docs/ROADMAP.md](docs/ROADMAP.md) for the full plan.

Short version:

- [x] v0.1 — project scaffold, PRD, architecture docs
- [ ] v0.2 — all 4 edges working, HUD, typing suppression
- [ ] v0.3 — Reading profile + hotkey + profile toggle
- [ ] v0.4 — SwiftUI settings window
- [ ] v0.5 — alpha DMG with ad-hoc signing
- [ ] v0.9 — beta with Developer ID + notarization + Sparkle auto-update
- [ ] v1.0 — public launch, Show HN, Homebrew cask

---

## Contributing

Issues and PRs are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) before opening anything large.

If you want to add a new edge action, start by reading [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and then implementing a new `EdgeAction` case + matching controller. The `EdgeDetector` is already generic.

---

## FAQ

### Does this work on external Magic Trackpads?

Yes. `OpenMultitouchSupport` reads from any connected multitouch device.

### Does it work with a mouse?

No — EdgePad only reads from multitouch trackpad devices. Mice don't have edges.

### Will Apple remove the private MultitouchSupport framework?

It has been part of macOS since at least 10.6. Apple has patented reconfigurable illuminated trackpads (November 2024) which suggests they're going _deeper_ into trackpad hardware, not shallower. If they do break it, `OpenMultitouchSupport` will likely be updated, and EdgePad follows.

### Why can't this be on the Mac App Store?

The Mac App Store requires app sandboxing. App sandboxing prevents access to the private `MultitouchSupport.framework`. No private framework = no touch coordinates = no EdgePad. Most serious trackpad utilities on Mac (BetterTouchTool, TrackWeight, Mactic, Slidr, Jitouch) ship outside the App Store for the same reason.

### Is this safe? You're using private APIs.

The private APIs EdgePad touches are read-only observation (`MultitouchSupport`) and a brightness setter that Apple's own System Settings uses (`DisplayServices`). We never modify kernel state, never touch IOKit directly, never patch system binaries. The worst case if a future macOS breaks them is that the app stops working gracefully.

Read the code: it's 1,500 lines of Swift, MIT licensed, no binary blobs, no network calls, no telemetry unless you turn it on.

### How is this different from BetterTouchTool?

BTT is a Swiss Army knife — 500 features, 10-year learning curve. EdgePad does one thing (trackpad edges as controls) and does it without any configuration. It's also free and open source. Use both: BTT for everything else, EdgePad for the edges.

### How is this different from Slidr?

Slidr is a $5 closed-source app that does volume and brightness on the left and right edges only. Its own homepage displays "0 downloads." EdgePad adds the top edge (video scrub), the bottom edge (horizontal scroll), the Reading profile (accessibility vertical scroll), is free, open source, and under active development.

### Will you accept donations / sponsors?

Yes — once there's an app worth donating to. For now, star the repo.

---

## License

MIT. See [LICENSE](LICENSE).

---

## Credits

- **[Kyome22/OpenMultitouchSupport](https://github.com/Kyome22/OpenMultitouchSupport)** — the Swift wrapper that made this possible
- **[TheBoredTeam/boring.notch](https://github.com/TheBoredTeam/boring.notch)** — inspiration for the menu-bar HUD replacement pattern
- **[KrishKrosh/TrackWeight](https://github.com/KrishKrosh/TrackWeight)** — proof that creative uses of the trackpad go viral
- **Apple** — for deleting the Touch Bar and not replacing it, giving us the problem statement

---

## Acknowledgments

Thanks to the macOS open-source community. This is a love letter to a trackpad.
