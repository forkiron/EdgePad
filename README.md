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
- **Real macOS HUD** — volume and brightness drag the actual system overlay (via `OSDManager`), not a clone. Same chiclets, same fade, same display you'd see pressing F11/F12.
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

EdgePad streams raw per-finger trackpad coordinates by `dlopen`ing Apple's private `MultitouchSupport.framework` and binding the C symbols (`MTDeviceCreateList`, `MTRegisterContactFrameCallback`, `MTDeviceStart`, …) directly. It enumerates every multitouch device on the system and starts only the ones with a real trackpad-sized sensor grid — calling `MTDeviceCreateDefault()` on Apple Silicon picks an auxiliary 60×2 sensor instead of the real trackpad, so we don't use it. **No SPM dependencies — pure Swift + Apple's frameworks.**

The `EdgeDetector` classifies each touch sample. If a contact lands inside one of four edge strips (default 10% inset from each side), it opens a drag. Subsequent samples from the same finger update the drag's position. When the finger lifts, the drag ends.

System state changes go through Apple's own APIs:

| Action | API |
|---|---|
| Volume read/write | `CoreAudio` → `kAudioDevicePropertyVolumeScalar` on the default output device |
| Brightness read/write | Private `DisplayServices.framework` via `dlopen` — same entry point macOS System Settings uses |
| Volume / brightness HUD | Private `OSD.framework` → `[OSDManager showImage:onDisplayID:…filledChiclets:totalChiclets:locked:]`. We do **not** draw our own HUD for these — we ask macOS to show its real one, so what you see is pixel-identical to pressing F1/F2 or F11/F12. |
| Video scrub | `CGEvent` posting `←` and `→` keys to the focused app |
| Horizontal / vertical scroll | `CGEvent` scroll wheel events, pixel units, posted to the focused app |

For scrub, where macOS has no native HUD, we draw a small custom borderless `NSWindow` overlay (click-through, auto-hides after 0.6 s). Scroll has no overlay — the page moving under the cursor is the feedback.

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

1. Runs `swift build -c release` (no external dependencies to fetch)
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

- [ ] v0.9 — beta with Developer ID + notarization + Sparkle auto-update
- [ ] v1.0 — public launch, Show HN, Homebrew cask

---

## Contributing

EdgePad is a personal project. Bug reports are welcome via GitHub issues; please don't open a PR without asking first. See [CONTRIBUTING.md](CONTRIBUTING.md).

---

## FAQ

### Does this work on external Magic Trackpads?

Yes. EdgePad enumerates every multitouch device on the system and reads from any with a real trackpad-sized sensor grid, so external Magic Trackpads work the same as the built-in one.

### Does it work with a mouse?

No — EdgePad only reads from multitouch trackpad devices. Mice don't have edges.

### Will Apple remove the private MultitouchSupport framework?

It has been part of macOS since at least 10.6 and the C ABI hasn't changed in roughly 15 years. Apple has patented reconfigurable illuminated trackpads (November 2024), which suggests they're going _deeper_ into trackpad hardware, not shallower. If a future macOS does change the layout, our `dlopen` bindings in `MultitouchCapture.swift` are ~80 lines and easy to update.

### Why can't this be on the Mac App Store?

The Mac App Store requires app sandboxing. App sandboxing prevents access to the private `MultitouchSupport.framework`. No private framework = no touch coordinates = no EdgePad.

### Is this safe? You're using private APIs.

The private APIs EdgePad touches are read-only observation (`MultitouchSupport`), a brightness setter that Apple's own System Settings uses (`DisplayServices`), and a HUD presenter that the OS itself uses for the F-key shortcuts (`OSD.framework`). We never modify kernel state, never touch IOKit directly, never patch system binaries. The worst case if a future macOS breaks them is that the app stops working gracefully.

Read the code: it's pure Swift, MIT licensed, no binary blobs, no SPM dependencies, no network calls, no telemetry unless you turn it on.

### Will you accept donations / sponsors?

Yes — once there's an app worth donating to. For now, star the repo.

---

## License

MIT. See [LICENSE](LICENSE).
