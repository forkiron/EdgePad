# Feature Specification: Reading Profile

**Status**: Approved
**Priority**: P0
**PRD Reference**: Section 5, Feature 4
**Author**: Thomas Lenh
**Last Updated**: 2026-04-11

## Overview

An alternate edge profile optimized for reading zoomed content, including macOS Accessibility Zoom. The right edge swaps from brightness to vertical scroll. The bottom edge (already horizontal scroll in the Media profile) is unchanged. Top edge still scrubs, left edge still volume.

This is the **accessibility differentiator** — nobody else offers a dedicated pan input for macOS Zoom users.

## User Stories

1. As a low-vision user, when I enable Accessibility Zoom and zoom in on my screen, I want to pan the magnified region by dragging the right and bottom edges of my trackpad, not by mouseing to the screen edges.
2. As a designer, when I'm zoomed into a Figma canvas, I want to pan around quickly without two-finger-scrolling.
3. As someone reading a PDF zoomed to 200%, I want to scroll vertically by sliding my finger down the right edge of the trackpad.

## Edge → Action Map (Reading profile)

| Edge | Action | Change from Media profile |
|---|---|---|
| Top | Video scrub | Same |
| Left | Volume | Same |
| **Right** | **Vertical scroll** | **Replaces brightness** |
| Bottom | Horizontal scroll | Same |

## Toggling

### Menu bar
Menu bar → Profile: Media / Reading / Custom. Radio-style, active profile checked.

### Hotkey
Default: `⌃⌥⌘R` (Control-Option-Command-R). Rebindable in settings. Registered via `NSEvent.addGlobalMonitorForEvents`.

### Auto (v1.1 — not in v1.0)
Detect focused app + zoom state via Accessibility APIs, auto-switch.

## Technical Design

Profile state lives in `AppSettings.activeProfile: EdgeProfile`. `AppDelegate.edgeDetector(_:didUpdate:)` routes events based on `activeProfile[event.edge]`:

```swift
func edgeDetector(_ d: EdgeDetector, didUpdate event: EdgeDragEvent) {
    let action = settings.activeProfile.action(for: event.edge)
    switch action {
    case .volume:          volume.applyDelta(event.delta)
    case .brightness:      brightness.applyDelta(event.delta)
    case .mediaScrub:      media.handleScrubDelta(event.delta)
    case .scrollVertical:  scroll.scroll(vertical: event.delta)
    case .scrollHorizontal:scroll.scroll(horizontal: event.delta)
    case .disabled:        break
    }
    overlay.showForAction(action, value: ...)
}
```

No special casing. The only difference between Media and Reading is which `EdgeAction` is mapped to the right edge.

## Menu bar visual feedback

Menu bar icon changes based on active profile:
- Media: `◱` (rectangle with bottom-right corner bold)
- Reading: `◨` (rectangle with right half filled — suggests "right edge is active")

Icons are SF Symbols where possible, Unicode fallback.

## HUD when in Reading profile

When dragging the right edge in Reading profile, HUD shows:
- Icon: upward arrow pulse `⇅`
- Label: "Scroll"
- No value bar (scroll is relative)

## Acceptance Criteria

- [ ] Toggle via menu bar works and updates icon immediately
- [ ] `⌃⌥⌘R` hotkey toggles profile
- [ ] Right-edge drag in Reading profile emits vertical scroll events, not brightness changes
- [ ] Brightness is fully suppressed in Reading profile (no accidental brightness change)
- [ ] Vertical scroll works in Preview (zoomed PDF), Safari (zoomed page), macOS Zoom
- [ ] Profile persists across restarts
- [ ] HUD clearly indicates the profile difference

## Manual test matrix

- [ ] Preview, zoomed image, right edge → scrolls vertically
- [ ] Preview, zoomed PDF, right edge → scrolls vertically
- [ ] Safari, zoomed page (`⌘+` several times), right edge → scrolls vertically
- [ ] Accessibility → Zoom enabled, zoomed in, right edge → pans Zoom region vertically
- [ ] Accessibility → Zoom enabled, zoomed in, bottom edge → pans Zoom region horizontally
- [ ] Profile toggle via `⌃⌥⌘R` is instant
- [ ] No brightness change in Reading profile
- [ ] Switching back to Media profile restores brightness control

## Open Questions

- [ ] Should Reading profile also remap the top edge? (Currently keeping it as scrub — consistency wins.)
- [ ] Auto-profile based on zoom detection: worth the AX complexity for v1.0, or defer to v1.1? (Defer.)
- [ ] Global hotkey: how to handle conflicts with user-configured macOS hotkeys?
- [ ] Should the menu bar icon distinguish profile via color, shape, or both?
