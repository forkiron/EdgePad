# Roadmap

Ship small, ship often. Each row is a user-visible change, not a refactor.

---

## v0.1 — Core prototype (internal)
- [x] Project scaffold
- [ ] OpenMultitouchSupport integrated via SPM
- [ ] Edge detection (4 edges) with dead zone
- [ ] Volume on left edge
- [ ] Brightness on right edge
- [ ] Minimal HUD overlay
- [ ] Menu bar icon with quit option
- [ ] CLI build via `build.sh`

## v0.2 — Media profile complete
- [ ] Video scrub on top edge (arrow keys)
- [ ] Horizontal scroll on bottom edge
- [ ] Relative-delta control for all edges
- [ ] HUD polish (icons, fade, dark/light mode)
- [ ] Typing suppression (300 ms)
- [ ] Multi-touch cancellation

## v0.3 — Reading profile
- [ ] Reading profile with right-edge vertical scroll
- [ ] Profile toggle from menu bar
- [ ] Global hotkey for profile toggle (`⌃⌥⌘R`)
- [ ] Menu-bar icon changes with active profile

## v0.4 — Settings
- [ ] SwiftUI settings window
- [ ] Per-edge action dropdown
- [ ] Sensitivity sliders
- [ ] Edge inset slider
- [ ] Typing suppression slider
- [ ] Launch at login (SMAppService)
- [ ] Settings persistence via UserDefaults

## v0.5 — Alpha release
- [ ] GitHub pre-release DMG
- [ ] Ad-hoc signing in build script
- [ ] README with demo GIF
- [ ] Installation instructions (incl. quarantine workaround)
- [ ] Invite ~10 testers

## v0.9 — Beta
- [ ] Apple Developer Program enrollment
- [ ] Developer ID signing + notarization
- [ ] Sparkle integration for auto-updates
- [ ] Appcast XML
- [ ] Landing page on GitHub Pages

## v1.0 — Public launch
- [ ] Show HN post
- [ ] r/macapps + r/MacOS + r/apple posts
- [ ] Product Hunt launch
- [ ] Homebrew cask submission
- [ ] Blog post / launch writeup

---

## Future (post v1.0)

### v1.1 — Haptics and polish
- [ ] Haptic feedback on edge-entry, value clamp, state change
- [ ] Force Touch pressure for scrub speed
- [ ] Reduce Motion support
- [ ] High contrast HUD variant
- [ ] Localization: JA, ZH-CN, KO, DE, ES, FR, PT-BR

### v1.2 — Smart profiles
- [ ] Per-app profile switching
- [ ] Auto-detect Reading mode when focused app is zoomed
- [ ] Custom profile editor

### v1.3 — MIDI mode
- [ ] Optional MIDI output for edge values
- [ ] Virtual MIDI destination ("EdgePad Output")
- [ ] CC mapping per edge

### v1.4 — Developer API
- [ ] Plugin system with sandboxed Swift plugins
- [ ] Community plugin marketplace

### Ideas parking lot
- Hold a modifier → different actions per edge
- Tap-to-jump (jump to ±30s with a corner tap)
- Integration with MediaRemote for frame-accurate scrub
- iPad companion via Sidecar that uses iPad touch as extra edges
- Windows port via Windows Precision Touchpad API (stretch)

---

## What we're NOT doing

- Cloud sync of settings — offline-first forever
- Accounts or login — offline-first forever
- Advertising, sponsored content, affiliate links
- Paywalls on core features
- Telemetry without explicit opt-in
- Electron, Tauri, Catalyst, or any non-native UI layer
