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

<p align="center">
  macOS 13+ | Swift 6 | Menu-bar app | MIT licensed
</p>

---

EdgePad turns the edges of a Mac trackpad into lightweight system controls. Drag the top edge to scrub media, the left edge to adjust volume, the right edge to adjust brightness or scroll vertically, and the bottom edge to scroll horizontally when the active mode allows it.

It is a native Swift menu-bar app with no external Swift Package Manager dependencies. It reads raw trackpad contact data, classifies intentional edge drags, and sends the matching system action to macOS or the focused app.

## What It Does

| Edge | Auto mode | Media mode | Reading mode |
| --- | --- | --- | --- |
| Top | Media scrub when EdgePad detects media context | Media scrub | Media scrub |
| Left | Volume | Volume | Volume |
| Right | Brightness in media context, vertical scroll elsewhere | Brightness | Vertical scroll |
| Bottom | Horizontal scroll outside media context | Disabled | Horizontal scroll |

Auto mode is the default behavior in the current app. It uses the frontmost app, browser window title, recent clicks on video elements, CoreAudio activity, and accessibility information to decide whether an edge should act like a media control or a scroll control.

## Features

- **Top-edge media scrubbing** - uses an accessibility slider when one is available, MediaRemote skip commands for Now Playing sources, and arrow-key fallback for players that use keyboard seeking.
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

There is no packaged DMG or Homebrew cask in this repository right now. Build the app from source:

```bash
git clone https://github.com/thomaslenh/EdgePad.git
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

The Swift package has one executable target, `EdgePad`, and one test target, `EdgePadTests`.

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

Run tests:

```bash
swift test
```

The current tests focus on `EdgeDetector`, which is the pure logic layer for edge classification and drag state transitions. System controllers require real macOS devices and permissions, so they are not covered the same way.

## Contributing

Pull requests are welcome. For setup steps, review expectations, and project boundaries, see [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT. See [LICENSE](LICENSE).
