<h1 align="center">
  <br>
  EdgePad
  <br>
</h1>

<p align="center">
  <strong>Trackpad-edge controls for macOS.</strong>
  <br>
  Scrub media, adjust volume and brightness, and pan scrollable content without leaving the trackpad.
</p>


---

EdgePad turns the edges of a Mac trackpad into lightweight system controls. Drag the top edge to scrub media, the left edge to adjust volume, the right edge to adjust brightness or scroll vertically, and the bottom edge to scroll horizontally when the active mode allows it.

It is a native Swift menu-bar app. It reads raw trackpad contact data, classifies intentional edge drags, and sends the matching system action to macOS or the focused app.

## What It Does

| Edge | Auto mode | Media mode | Reading mode |
| --- | --- | --- | --- |
| Top | Media scrub when EdgePad detects media context | Media scrub | Media scrub |
| Left | Volume | Volume | Volume |
| Right | Brightness in media context, vertical scroll elsewhere | Brightness | Vertical scroll |
| Bottom | Horizontal scroll outside media context | Disabled | Horizontal scroll |

Auto mode is the default behavior in the current app. It uses the frontmost app, browser window title, recent clicks on video elements, CoreAudio activity, and accessibility information to decide whether an edge should act like a media control or a scroll control.

## Features

- **Top-edge media scrubbing** - works wherever the focused player binds left/right arrow keys to small playhead seeks: (e.g. YouTube, Tubi, Discord). Players that don't bind arrow-key seek won't respond — EdgePad is sending arrow keypresses. For Apple Music / Podcasts / Apple TV / Spotify (which ignore arrow keys), it falls back to MediaRemote skip-15 commands; an accessibility slider drag is used on top if the page exposes one.
- **Left-edge volume control** - reads and writes the default output device through CoreAudio.
- **Right-edge brightness control** - uses macOS DisplayServices at runtime for built-in display brightness.
- **Reading mode** - swaps the right edge from brightness to vertical scrolling and enables bottom-edge horizontal scrolling.
- **Horizontal and vertical scrolling** - posts pixel-based scroll events with velocity amplification, sub-pixel accumulation, and momentum.
- **Native macOS HUDs** - volume and brightness call the system OSD manager instead of drawing a clone.
- **Scrub overlay** - media scrubbing gets a small click-through overlay for feedback.
- **Typing and palm rejection** - suppresses new edge gestures shortly after typing and rejects obvious palm contacts.
- **Adjustable sensitivity** - tune global sensitivity, individual action sensitivity, and edge-zone size from the menu-bar menu.
- **No bundled network code** - the current source tree contains no telemetry, analytics, or updater network calls.

## System Requirements

- macOS 13 Ventura or later
- Swift 6.0 or later
- Xcode Command Line Tools or Xcode 16+
- A Mac trackpad device exposed through Apple's multitouch framework
- Accessibility permission for keyboard and scroll event posting

EdgePad uses private Apple frameworks for raw multitouch capture, brightness, MediaRemote commands, and native HUD display. Those frameworks are loaded dynamically at runtime, so the app can fail gracefully if a future macOS release changes one of them.

## Installation

### Option 1 (recommended): Install via curl

```bash
curl -fsSL https://raw.githubusercontent.com/forkiron/EdgePad/main/install.sh | bash
```

This downloads the latest release, installs it to `/Applications`, and launches it. **No Gatekeeper warning, no first-launch dance** — see "About the install methods" below for why.

After EdgePad opens, grant Accessibility permission when prompted, in `System Settings -> Privacy & Security -> Accessibility`.

### Option 2: Download the .zip directly

Download `EdgePad-x.y.z.zip` from [GitHub Releases](https://github.com/forkiron/EdgePad/releases/latest), unzip it, and move `EdgePad.app` into `/Applications`.

> ⚠ **Browser-downloaded apps trigger a Gatekeeper warning.** macOS marks every browser download as quarantined, and because the released binary is ad-hoc signed (not Developer ID signed), the warning will block the app from opening on first launch. You'll need to bypass it once.

To bypass after a browser download, run:

```bash
xattr -dr com.apple.quarantine /Applications/EdgePad.app
```

Or via System Settings: open `System Settings -> Privacy & Security`, scroll to the banner that says *"EdgePad was blocked from use…"*, click **Open Anyway**, then re-launch and click **Open** in the new dialog.

The curl install in Option 1 avoids this entirely.

### About the install methods

The Gatekeeper warning is triggered by an extended attribute (`com.apple.quarantine`) that browsers attach to downloads. `curl`, `wget`, and `git` don't set it, so an app fetched via the install script bypasses Gatekeeper without any signing change. This is the same mechanism Homebrew, Rust (`rustup`), Bun, and Deno use for their installers.

The released binary is currently ad-hoc signed rather than signed with an Apple Developer ID. This is a signing status, not a malware indicator:

- EdgePad is open source (MIT). The full source tree of every release is in this repository, and you can rebuild the same binary yourself with `./build.sh`.
- The current source tree contains no telemetry, analytics, or auto-update network calls.
- Future versions are expected to be Developer ID signed and notarized by Apple, at which point both install paths will be warning-free.

### Option 3: Build from source

```bash
git clone https://github.com/forkiron/EdgePad.git
cd EdgePad
./build.sh
```

The build script creates:

```text
build/EdgePad.app
```

To build and launch in one step:

```bash
./build.sh run
```

For foreground development logs:

```bash
./build.sh dev
```

On first launch, grant Accessibility permission in:

```text
System Settings -> Privacy & Security -> Accessibility
```

If macOS blocks the locally built app because it is ad-hoc signed, remove the quarantine flag after building:

```bash
xattr -dr com.apple.quarantine build/EdgePad.app
```

To produce a distributable zip for upload to a release, run:

```bash
./package.sh
```

This produces `build/EdgePad-<version>.zip`, ad-hoc signed, ready to attach to a GitHub release.

Optional: run `scripts/codesign/setup_local.sh` once on macOS to create a local development signing identity used by `build.sh`.

## Usage

1. Launch `build/EdgePad.app`.
2. Open the EdgePad menu-bar item.
3. Choose `Auto`, `Media`, or `Reading`.
4. Adjust sensitivity or edge-zone size if the default 10% edge strip feels too narrow or too wide.
5. Drag along a trackpad edge.

Use **Media** when you want fixed media controls: top scrub, left volume, right brightness. Use **Reading** when you are working with zoomed pages, PDFs, wide documents, timelines, or canvases and want right-edge vertical scroll plus bottom-edge horizontal scroll. Use **Auto** when you want EdgePad to switch between those behaviors based on context.

## How It Works

EdgePad is organized around a small input pipeline:

| Component | Role |
| --- | --- |
| `MultitouchCapture` | Loads `MultitouchSupport.framework`, enumerates real trackpad-sized devices, and streams contact samples. |
| `EdgeDetector` | Classifies edge touches, waits for a dead zone, rejects likely palm/navigation gestures, and emits drag events. |
| `ContextDetector` | Resolves Auto mode by inspecting the frontmost app, browser media hints, click targets, audio activity, and scrollability. |
| `MediaController` | Scrubs with accessibility sliders, MediaRemote skip commands, or arrow-key events. |
| `VolumeController` | Reads and writes output volume through CoreAudio. |
| `BrightnessController` | Reads and writes display brightness through DisplayServices. |
| `ScrollController` | Posts horizontal or vertical pixel scroll events with momentum. |
| `NativeHUD` | Shows the real macOS volume and brightness HUD through OSD.framework. |

The Swift package has one executable target, `EdgePad`.

## Development

Build:

```bash
./build.sh
```

Run:

```bash
./build.sh run
```

Clean:

```bash
./build.sh clean
```

## Contributing

Pull requests are welcome. For setup steps, review expectations, and project boundaries, see [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT. See [LICENSE](LICENSE).
