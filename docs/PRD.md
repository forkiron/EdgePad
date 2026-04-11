# Product Requirements Document: EdgePad

**Status**: Draft v0.1
**Author**: Thomas Lenh
**Last Updated**: 2026-04-11
**License**: MIT (planned)

---

## 1. Executive Summary

**EdgePad turns the edges of your MacBook trackpad into system controls.**

Drag along the **top edge** to scrub a video timeline. Drag along the **left edge** to set volume. Drag along the **right edge** to set brightness. Drag along the **bottom edge** to pan horizontally through wide content.

In a Reading mode, the right edge becomes a vertical scroll, making zoomed PDFs, magnified Safari pages, and macOS accessibility Zoom actually pannable without awkward shift-scroll hacks.

EdgePad is a free, open-source, single-binary menu-bar utility for macOS 13+. It uses a public Swift wrapper (`Kyome22/OpenMultitouchSupport`) over Apple's private `MultitouchSupport.framework` to read raw trackpad contacts, and posts system events via public APIs (`CoreAudio`, `DisplayServices`, `CGEvent`). It is **the Touch Bar Apple deleted, built into the trackpad you already have**.

---

## 2. Problem Statement

### Pain points

1. **The Touch Bar is dead.** Apple removed it from the MacBook Pro lineup in 2023. The scrub bar that Spotify, QuickTime, YouTube (via extensions), Final Cut, and Logic exposed on the Touch Bar is gone. There is no system-wide replacement.
2. **Volume and brightness on a MacBook are clumsy.** You either tap F-row keys (fixed increments, no precision) or hold Option+Shift+F for quarter-steps (obscure, hard to remember). Sliders on the menu bar require reaching for the mouse.
3. **Horizontal scrolling is a second-class citizen.** Shift+scroll-wheel is the de facto solution and it is terrible: clunky, requires a modifier, inconsistent across apps. Wide spreadsheets, long timelines in DAWs/NLEs, wide Figma canvases, large maps, and zoomed images all need horizontal pan.
4. **macOS Zoom accessibility is awkward to pan.** When a low-vision user activates the system Zoom feature, they have to physically move the mouse to the screen edges to pan the magnified region. There is no dedicated pan input.
5. **BetterTouchTool is powerful but too heavy for 99% of users.** Users on r/macapps and the BTT forums complain that it is "not intuitive AT ALL" (direct Setapp review quote) and has a steep learning curve. People want a one-purpose utility that "just works."
6. **Slidr (the one existing competitor) is effectively dead.** Its own homepage displays "0 downloads". No Reddit mentions, no GitHub repo, no Product Hunt listing, no press coverage. The market is wide open.

### Why now

- MacBook sales hit an all-time high in 2025. The installed base of Apple Silicon MacBooks is massive.
- The Touch Bar's removal has left a very specific, very concrete feature-gap in the market.
- `OpenMultitouchSupport` shipped a clean, modern, Swift 6 concurrency-friendly wrapper over the private framework in 2024, eliminating the biggest technical barrier.
- Apple themselves are actively patenting reconfigurable illuminated trackpads (Patently Apple, November 2024), validating the direction but taking years to ship.
- The open-source Mac utility space is red-hot: `boring.notch` (8.1k★), `Rectangle`, `AltTab`, `MiddleDrag`, and `TrackWeight` (8.9k★) all show that well-built, focused, free Mac tools go viral.

---

## 3. Target Users

### Primary: Mac power users

- Watch videos in multiple apps (YouTube, Netflix, VLC, IINA, QuickTime, Spotify)
- Miss the Touch Bar scrub bar
- Want precise volume and brightness without reaching for F-keys
- Use MacBooks daily for work and play
- Comfortable installing menu-bar utilities and granting Accessibility permissions

### Secondary: Accessibility users

- Use the macOS Zoom feature for low vision
- Read zoomed PDFs, magnified web pages, high-DPI images
- Struggle with panning around large zoomed content
- Will benefit from the Reading profile's directional scroll edges

### Tertiary: Creators & spreadsheet power users

- Work in Figma, Sketch, Illustrator (wide canvases)
- Use Excel, Numbers, Google Sheets (wide tables)
- Edit audio/video in Logic, Ableton, Final Cut, Resolve (long timelines)
- Want a dedicated horizontal pan input

---

## 4. Success Metrics

| Metric | Target (3 months) | Target (12 months) | Measurement |
|---|---|---|---|
| GitHub stars | 1,500 | 8,000 | GitHub API |
| DMG downloads | 5,000 | 50,000 | GitHub Releases + Homebrew analytics |
| Daily active users | 2,000 | 20,000 | Opt-in anonymous beacon (off by default) |
| Crash-free sessions | ≥ 99.8% | ≥ 99.9% | Opt-in telemetry |
| Memory footprint | < 30 MB RSS | < 25 MB RSS | Activity Monitor |
| CPU usage (idle) | < 0.3% | < 0.1% | Activity Monitor |
| Edge detection latency | < 3 ms | < 1 ms | Internal timing |
| Accidental activations | < 2 / day / user | < 0.5 / day / user | Opt-in telemetry |
| App Store rating _(if published)_ | N/A (private APIs) | N/A | — |
| Homebrew cask installs | 500 | 10,000 | `brew analytics` |

---

## 5. Core Features

### Feature 1: Raw multitouch capture

**User story**: As a developer building EdgePad, I need access to raw per-finger coordinates on the trackpad so I can detect edge contacts.

**Implementation**: Wrap `Kyome22/OpenMultitouchSupport` (MIT-licensed) as a Swift Package dependency. This library provides an `AsyncStream<[OMSTouchData]>` of touch frames with `position`, `pressure`, `state`, `axis`, and `angle` fields, and handles the private-framework plumbing so we don't have to.

**Acceptance criteria**:
- [ ] App starts streaming touches within 100 ms of launch
- [ ] `OMSManager` cleanly stops on app quit with no zombie callbacks
- [ ] Capture survives trackpad disconnect/reconnect (external Magic Trackpad)
- [ ] Failure mode: if framework loading fails, show a friendly alert and disable the app, don't crash

### Feature 2: Edge drag detection

**User story**: As a user, when I place one finger near the edge of my trackpad and slide along it, the app should recognize that as a deliberate edge gesture and not confuse it with normal cursor movement.

**Implementation**: `EdgeDetector` classifies incoming touch samples. A drag starts only if the **first** contact lands inside an edge strip (default 10% inset) and clears a dead zone of 1.5% travel. Once active, the drag continues even if the finger drifts outside the edge strip — this matches how touchscreen sliders work: grab, then drag freely.

**Acceptance criteria**:
- [ ] Top, bottom, left, and right edges each detectable independently
- [ ] Center-trackpad touches never trigger an edge drag
- [ ] Dead zone prevents taps and jitters from flipping volume
- [ ] Multi-finger contact cancels the active drag immediately
- [ ] Typing-aware: suppress drag detection for 300 ms after any key press (prevents palm rejection issues)
- [ ] All four edges can be active simultaneously (different fingers → different edges → one wins via first-contact rule)

### Feature 3: Media profile (default)

**User story**: As a user watching a video, I slide along the top edge and the video scrubs. Volume and brightness work the same way via the side edges. Horizontal pan via the bottom edge.

**Edge → Action map**:
| Edge | Action | Implementation |
|---|---|---|
| **Top** | Video timeline scrub | Post `←`/`→` arrow keys to focused app (works in YouTube, Netflix, VLC, QuickTime, IINA, Spotify, basically everything) |
| **Left** | System volume | `CoreAudio` `kAudioDevicePropertyVolumeScalar` on default output device |
| **Right** | Display brightness | Private `DisplayServices.framework` `DisplayServicesSetBrightness` (same entry point Apple's System Settings uses) |
| **Bottom** | Horizontal scroll | `CGEvent` scroll wheel event with horizontal delta, pixel units |

**Control semantics**: All edge drags use **relative delta control**, not absolute. At drag-start we capture the current value; as the finger slides, we add `delta * sensitivity` to that starting value. This means a drag from trackpad y=0.2 to y=0.5 adds +30% to the starting value, regardless of where the finger landed. Absolute positioning would be jarring ("I touched at y=0.5 and my volume jumped to 50%").

**Acceptance criteria**:
- [ ] Volume changes are smooth and responsive (< 20 ms from finger motion to audio change)
- [ ] Brightness changes are smooth (same)
- [ ] Video scrub works in Safari YouTube, VLC, QuickTime, IINA, Spotify desktop
- [ ] Horizontal scroll works in Safari, Preview (zoomed image), Numbers, Figma
- [ ] HUD overlay shows the current value while dragging, fades after 0.9 s of no input
- [ ] Sensitivity is configurable per-edge (default 1.2× so a full edge travel = ~120% of the value range)

### Feature 4: Reading profile (accessibility)

**User story**: As a low-vision user who has zoomed into a PDF or web page, I want a dedicated way to pan horizontally and vertically around the zoomed content without having to move the cursor to the screen edges.

**Edge → Action map (Reading profile)**:
| Edge | Action |
|---|---|
| **Top** | Video scrub _(unchanged — still useful)_ |
| **Left** | Volume _(unchanged — still useful)_ |
| **Right** | **Vertical scroll** _(REPLACES brightness)_ |
| **Bottom** | Horizontal scroll _(unchanged)_ |

**Implementation**: When active, right-edge drags post `CGEvent` scroll wheel events on the vertical axis instead of writing to `DisplayServices`. Bottom edge continues to post horizontal scroll. Scrolls are pixel-level smooth, not line-level.

**Toggling**: Menu-bar → "Reading Mode" checkbox, or a global hotkey (default `⌃⌥⌘R`). Future v2: auto-detect based on focused app (Preview with zoom > 100%, Safari with `⌘+`, any element reporting AX zoom state).

**Why this matters**: Nobody ships this. Apple's own accessibility Zoom has no dedicated pan input — users currently have to mouse to the screen edge to pan, which is exactly what the feature is supposed to free them from. EdgePad's Reading profile closes that loop.

**Acceptance criteria**:
- [ ] Toggle via menu bar + hotkey works
- [ ] Right-edge drag posts vertical scroll events in Preview, Safari, PDF apps
- [ ] Bottom-edge drag posts horizontal scroll events in same apps
- [ ] Works with macOS Zoom accessibility feature (System Settings → Accessibility → Zoom)
- [ ] HUD clearly shows the profile has switched (icon change)

### Feature 5: HUD overlay

**User story**: While I'm dragging an edge, I want visual feedback showing what's happening without occluding what I'm working on.

**Design**:
- Floating borderless NSWindow at bottom-center of the main screen
- Frosted-glass rounded-rect backdrop, matches macOS system HUDs
- Icon + label + value bar (volume/brightness) or arrow pulse (scrub/scroll)
- Auto-hide after 0.9 s of no input
- Click-through (`ignoresMouseEvents = true`) so it never blocks UI
- Always on top (`NSStatusWindowLevel`), joins all spaces

**Acceptance criteria**:
- [ ] Renders in < 5 ms per frame
- [ ] Works on all attached displays (shows on display containing the cursor)
- [ ] Respects dark/light mode
- [ ] Doesn't flash or flicker on rapid updates
- [ ] Hidden during fullscreen video playback unless the user is actively edge-dragging

### Feature 6: Menu-bar UI and settings

**User story**: As a user, I want a tiny menu bar icon I can click to toggle EdgePad, switch profiles, and tweak sensitivity.

**Menu structure**:
```
◱ EdgePad
├── ● Enabled                  (toggle)
├── Profile: Media             (submenu)
│   ├── Media
│   ├── Reading
│   └── Custom…
├── ─────────
├── Edge sensitivity…          (opens settings window)
├── ─────────
├── Launch at login            (toggle)
├── About EdgePad…
└── Quit
```

**Settings window** (SwiftUI):
- Per-edge action assignment (dropdown)
- Per-edge sensitivity slider (0.5× – 2.5×)
- Edge inset slider (5% – 15%)
- Typing suppression window (0 – 500 ms)
- Launch at login toggle (via `SMAppService`)
- Opt-in anonymous usage telemetry toggle (off by default)

**Acceptance criteria**:
- [ ] Menu bar icon shows profile state (different icon for Media vs Reading)
- [ ] All settings persist across launches (`UserDefaults`)
- [ ] Launch at login works with Apple's 2023+ `SMAppService` API
- [ ] Settings window is VoiceOver-accessible
- [ ] Uninstall is clean: quit + drag to Trash removes everything

---

## 6. Non-Functional Requirements

### Performance
- Edge detection latency: **< 3 ms p99** from touch sample to action dispatch
- Overlay draw: **< 5 ms per frame**
- Idle CPU: **< 0.3%**
- Memory: **< 30 MB RSS**

### Reliability
- Must not crash the host system under any sequence of trackpad events
- Must recover from private-framework symbol failures without user intervention
- Must release all system resources on quit (no zombie MT callbacks)

### Privacy
- **Zero network activity by default.** No analytics, no telemetry, no update pings until the user explicitly opts in.
- Update checks (Sparkle): opt-in via settings, default off.
- Usage beacon: opt-in, default off, anonymous, 1 event/day max, no content ever sent.
- No data leaves the device unless the user turns on updates or beacon.

### Accessibility
- Settings UI built with SwiftUI, VoiceOver compatible
- All controls reachable by keyboard
- Respects Reduce Motion (disables HUD animations)
- Respects Increase Contrast (bolder HUD strokes)
- High-contrast HUD variants

### Internationalization
- v1.0: English only
- v1.1: Use `String Catalogs` (Xcode 15+) for localization
- Target languages: JA, ZH-CN, KO, DE, ES, FR, PT-BR (top Mac markets)

### Open-source hygiene
- MIT license
- `README.md` with animated GIF demo (first-second impact is everything)
- `CONTRIBUTING.md` with clear guidance
- `CHANGELOG.md` following Keep A Changelog conventions
- Conventional commits
- GitHub Actions CI: build + test on every PR

---

## 7. Technical Constraints

- **macOS 13 Ventura or later** (OpenMultitouchSupport requirement)
- **Apple Silicon or Intel** (both supported by OpenMultitouchSupport)
- **Swift 6.0+** with strict concurrency
- **App Sandbox must be disabled** (OpenMultitouchSupport requirement — private framework access)
- **Cannot ship via Mac App Store** because of private API usage. Distribution is DMG + Homebrew cask.
- **Requires Accessibility permission** to post `CGEvent` key/scroll events
- **Requires Input Monitoring permission** to read trackpad contacts (maybe — needs verification during implementation)
- **Code signing**: ad-hoc for alpha, Developer ID + notarization for v1.0 (requires $99 Apple Developer Program)

---

## 8. Dependencies

| Dependency | Version | Purpose | License |
|---|---|---|---|
| `Kyome22/OpenMultitouchSupport` | 3.0.3+ | Raw trackpad touch capture via private MT framework | MIT |
| `sparkle-project/Sparkle` | 2.6+ | Auto-update (opt-in) | MIT |
| `apple/swift-argument-parser` | 1.5+ | CLI argument parsing (optional, for debug CLI build) | Apache 2.0 |

**System frameworks** (no SPM dependency needed):
- `AppKit`, `Foundation`, `SwiftUI` — app shell
- `CoreAudio` — volume read/write
- `CoreGraphics`, `DisplayServices` (private, `dlopen`-loaded) — brightness + events
- `ServiceManagement` — launch at login (`SMAppService`)
- `Carbon` — virtual keycodes for scrub

---

## 9. Out of Scope (v1.0)

Deferred to v1.1+:
- Haptic feedback customization (use `CoreHaptics` or private actuator driver)
- Force Touch pressure-sensitive scrubbing (pressure = scrub speed)
- Per-app edge profiles (auto-switch when focused app changes)
- Custom user-defined profiles beyond Media/Reading
- iPad companion / Sidecar touch mode
- Windows or Linux port
- Full-screen gestures (already handled by system)
- Multi-finger edge gestures (single finger only in v1.0)
- MIDI output mode (possible via a plugin system later)
- Localization beyond English
- In-app tutorial/onboarding video
- Theme customization

**Explicitly not doing**:
- Telemetry or analytics by default
- Bundled cryptocurrency, bitcoin miners, or anything shady (you laugh but the Mac utility space has had incidents)
- Paid tiers for v1.0 (may explore open-core model post-launch)
- Electron, Tauri, Catalyst, or any other wrapped-web UI. Native Swift only.

---

## 10. Timeline

| Phase | Window | Deliverables |
|---|---|---|
| **Phase 1: Core** | Week 1 | Capture + edge detection + volume + brightness, CLI build, overlay stub |
| **Phase 2: Media profile** | Week 2 | Scrub via arrow keys, HUD overlay polish, horizontal scroll on bottom edge |
| **Phase 3: Reading profile** | Week 3 | Vertical scroll on right edge, profile toggle, menu bar icon, basic settings |
| **Phase 4: Polish** | Week 4 | Settings window, launch at login, typing suppression, dead-zone tuning |
| **Phase 5: Alpha** | Week 5 | GitHub pre-release DMG, invite ~10 testers, bug bash |
| **Phase 6: Beta** | Week 6 | Apple Developer Program enrollment, Developer ID signing + notarization |
| **Phase 7: v1.0 launch** | Week 7 | Show HN, r/macapps, r/MacOS, Product Hunt, Homebrew cask |

Aspirational: if the core tech is solid by week 2, Phases 3–7 can overlap.

---

## 11. Launch Strategy

### Narrative

> **"The Touch Bar is dead. Your trackpad is bigger than the Touch Bar ever was. I turned its edges into the scrub bar Apple killed."**

### Distribution channels

1. **GitHub Releases** — signed, notarized `.dmg` on each tagged release
2. **Homebrew Cask** — submit to `homebrew-cask` repo: `brew install --cask edgepad`
3. **Landing page** — one-page static site on GitHub Pages with the demo GIF
4. **Setapp** (evaluate post-launch) — recurring revenue if the app is a hit
5. **Mac App Store** — **not possible** (private API usage)

### Launch-day posts

1. **Show HN** — "Show HN: EdgePad — turn your MacBook trackpad edges into a Touch Bar replacement"
2. **r/macapps** — same + before/after GIF
3. **r/MacOS** — focus on the accessibility angle
4. **r/apple** — broader audience, focus on nostalgia for the Touch Bar
5. **Product Hunt** — cap the launch off with a PH post on Tuesday (best PH day)
6. **X/Twitter thread** — 6-clip thread with the demo GIF, tagging Mac influencers
7. **Mastodon + Bluesky** — same content, mac.social and bsky.app have active Mac communities

### The demo GIF

The README's top section must have an animated GIF that in 2 seconds shows:
1. A YouTube video playing in Safari
2. A finger dragging along the top edge of the trackpad
3. The video timeline scrubbing in sync
4. The HUD overlay flashing with the arrow pulse

**This GIF is the most important asset in the entire launch.** More than the code, more than the docs. First-second impact determines everything.

### Post-launch cadence

- Week 1: respond to every issue, every PR, every comment on every thread
- Week 2: ship a fast-follow release based on feedback (always ship something in the first week after launch to signal activity)
- Week 3: Homebrew cask PR
- Week 4: blog post writing up the launch ("How my weekend project got 2K stars on HN")

---

## 12. Risks and Mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| Apple breaks `MultitouchSupport.framework` in a future macOS | High | Pin OpenMultitouchSupport version; monitor Kyome22's repo for updates; fall back to `CGEventTap` scroll events only if MT goes dark |
| `DisplayServicesSetBrightness` stops working on a future macOS | Medium | Fall back to posting F1/F2 brightness keys via `CGEvent` (step control, works everywhere) |
| Users can't grant Accessibility permission on corporate-managed Macs | Medium | Document clearly in README; offer a "manual install" path with TCC reset instructions |
| Arrow-key scrubbing doesn't work in obscure video players | Low | Document supported apps; accept as a known limitation; future v2 can use `MediaRemote` framework |
| Accidental edge activations feel bad | **Critical** | This is ASUS NumberPad's known failure mode. Invest heavily in: dead zone, typing suppression, minimum-travel threshold, multi-touch cancellation, per-edge disable. Ship with _conservative_ defaults, let power users loosen them. |
| Slidr or BTT adds the video scrubbing feature in response | Low | First-mover advantage, better design, better marketing, open-source community |
| Someone forks and clones the project before we can launch | Low | Accept — the narrative and launch are the moat, not the code |

---

## 13. Open Questions

- [ ] Which brightness API is most stable on macOS 14 / 15 / 26? (validate `DisplayServices` during week 1)
- [ ] Does Input Monitoring permission actually get prompted for `OpenMultitouchSupport`, or only Accessibility?
- [ ] Should the bottom-edge horizontal scroll always be active, or profile-gated?
- [ ] Should Reading profile be auto-triggered by focused-app heuristics, or manual only in v1?
- [ ] Menu bar icon: custom SF Symbol, Apple symbol like `rectangle.compress.vertical`, or text?
- [ ] Are `OpenMultitouchSupport` callbacks guaranteed on the main actor or a background queue? (verify before wiring delegates)

---

## 14. Appendix: Prior Art and Competitive Notes

### What exists

| Tool | Does video scrub? | Does vol/brightness edge? | Does horizontal scroll? | Reading mode? | Open source? | Traction |
|---|---|---|---|---|---|---|
| **Slidr** ($5) | ❌ | ✅ L+R only | ❌ | ❌ | ❌ | "0 downloads" on homepage |
| **BetterTouchTool** ($10–22) | ❌ directly; user-scriptable | ⚠️ manual config | ⚠️ manual config | ❌ | ❌ | 390K+ installs |
| **Swish** ($16) | ❌ | ❌ | ❌ | ❌ | ❌ | 408 PH upvotes |
| **Multitouch** ($16) | ❌ | ❌ | ❌ | ❌ | ❌ | Moderate |
| **Jitouch** (free) | ❌ | ❌ | ❌ | ❌ | ✅ | Cult following |
| **Boring Notch** (free) | ❌ (notch UI, not trackpad) | — | — | — | ✅ | 8.1k★ |
| **TrackWeight** (free) | ❌ (scale, not controls) | — | — | — | ✅ | 8.9k★ |
| **EdgePad** | **✅** | **✅** | **✅** | **✅** | **✅** | — (us) |

### What Apple is planning

- November 2024 patent: reconfigurable illuminated trackpad with pixel array, buttons, sliders, knobs
- May 2024 patent: all-glass MacBook with virtual trackpad + illuminated icons
- 2018 + 2024 patents: Force Touch "Fusion keyboard" replacing physical keys
- None shipped as of this writing. EdgePad is the software version of the hardware Apple is patenting.

### Launches to copy

- **Boring Notch** — Swift, AppKit/SwiftUI, GPL-3.0, DMG + Homebrew + Ko-Fi, grew to 8.1k★ in ~12 months with a single focused feature. Exact playbook for us.
- **TrackWeight** — Swift, private MT framework, open source, went viral on Tom's Hardware / Ubergizmo / BigGo for a single novel use case (weight measurement). Proves that novel uses of the trackpad hardware go viral regardless of how "useful" they are.
- **Rectangle** — replaced paid Spectacle with a free MIT clone and dominated the space. Proof that OSS > paid in this market.

---

## Changelog

| Date | Author | Change |
|---|---|---|
| 2026-04-11 | Thomas | Initial draft |
