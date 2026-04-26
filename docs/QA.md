# EdgePad — manual QA checklist

EdgePad is a system-wide utility that hooks raw trackpad input, posts synthetic events, and pokes private OS overlays. Most of its surface area can't be exercised by `swift test`. This is the manual checklist to run before tagging a release. Skip nothing — the items here exist because they've broken before in apps that do similar things (see AltTab's QA notes for prior art).

Mark each line ✅ / ❌ / N/A as you go. If anything is ❌, file an issue and don't tag.

---

## 1. Input capture — does the trackpad even talk to us?

- [ ] Built-in MacBook trackpad: each of the 4 edges fires its action
- [ ] External Magic Trackpad (USB or BT): each of the 4 edges fires its action
- [ ] Both built-in **and** external connected at once: edges work on whichever surface the finger is on
- [ ] Plug in / unplug an external Magic Trackpad while EdgePad is running: no crash, gestures still work after
- [ ] After Sleep → Wake: gestures still work without restarting the app
- [ ] After Lock → Unlock: gestures still work
- [ ] After fast user switch: gestures still work for the foreground user
- [ ] First launch: macOS prompts for Accessibility / Input Monitoring; granting it does **not** require an app restart to start working

## 2. Edge detector — drag state machine

- [ ] Touch lands inside the edge strip → drag opens
- [ ] Touch lands outside the edge strip → no drag, normal cursor behavior
- [ ] Finger leaves the hold zone → drag ends (regression: see commit b0ad76d)
- [ ] Lift finger → drag ends
- [ ] Two fingers down at once: only the qualifying finger drives the drag, the other is ignored (no jitter from finger #2)
- [ ] Quickly tap an edge with no movement: no spurious action fires
- [ ] Drag from corner where two edges meet: behavior is consistent (one wins, no flicker)

## 3. Volume (left edge)

- [ ] Drag down → volume drops; drag up → rises
- [ ] **Real macOS HUD** appears (chiclets, fade) — not a custom clone
- [ ] Mute → unmute via the edge: HUD reflects unmute correctly
- [ ] Change default output device (built-in → AirPods → display speakers): edge controls the new device
- [ ] No output device connected: edge gesture does nothing, no crash
- [ ] Slider is continuous (not stepped to 16 like F11/F12)

## 4. Brightness (right edge, Media profile)

- [ ] Drag up → brightness rises; drag down → drops
- [ ] Real macOS HUD appears
- [ ] External display attached: brightness changes the **active** display (the one the cursor is on, or the built-in for the built-in trackpad — pick the rule and verify)
- [ ] Built-in display closed (clamshell): edge gesture does nothing or controls the external — does not crash

## 5. Video scrub (top edge)

- [ ] YouTube in Safari (full-page video): scrubs ←/→
- [ ] YouTube in Safari (mini player): scrubs
- [ ] YouTube in Chrome: scrubs
- [ ] Netflix in Safari: scrubs
- [ ] Twitch in Safari: scrubs
- [ ] VLC: scrubs
- [ ] QuickTime Player: scrubs
- [ ] IINA: scrubs
- [ ] Velocity-amplified scrub (commit bcce73e): fast drag = bigger jumps, slow drag = fine control
- [ ] Custom scrub HUD overlay appears, click-through, auto-hides ~0.6 s after release
- [ ] Scrub does **not** trigger when no video has focus (e.g. drag while typing in a text field) — typing-suppression dead zone

## 6. Horizontal scroll (bottom edge, Media profile)

- [ ] Numbers wide sheet: scrolls horizontally
- [ ] Figma canvas: pans horizontally
- [ ] Preview with a zoomed-in image: pans horizontally
- [ ] Logic / Final Cut timeline: scrolls
- [ ] Pixel scrolling looks smooth, not stepped

## 7. Reading profile

- [ ] Toggle via menu bar item: right edge switches from brightness to vertical scroll
- [ ] Hotkey ⌃⌥⌘R toggles
- [ ] Zoomed PDF in Preview: right edge pans vertically
- [ ] Magnified Safari page (⌘+): right edge pans
- [ ] macOS Accessibility Zoom active: right edge pans the zoom viewport
- [ ] Toggle back to Media: brightness restored, vertical scroll gone

## 8. Typing suppression

- [ ] Type continuously, drag an edge during typing: gesture is suppressed
- [ ] Stop typing, wait ~300 ms, drag: gesture works
- [ ] Modifier-only keys (⌘, ⇧ alone) do not start the suppression window
- [ ] Suppression window setting in Settings actually changes behavior

## 9. OS interactions — the weird stuff

- [ ] Mission Control open: edge gestures do not fire (or are suppressed gracefully — pick the rule)
- [ ] Spaces transition in progress: no crash, no spurious action; gestures resume after transition completes
- [ ] App goes fullscreen mid-drag: drag ends cleanly, no stuck cursor lock
- [ ] App quits / launches mid-drag: no crash, drag ends cleanly
- [ ] Multiple displays with **separate Spaces** enabled: gestures work on whichever display the cursor is on
- [ ] Multiple displays with **separate Spaces** disabled: same
- [ ] Secure Input is active (e.g. focused 1Password unlock, sudo prompt in Terminal): EdgePad does not steal events; gestures may degrade gracefully but app does not crash or spam logs
- [ ] Switch to a different app mid-drag (⌘Tab): drag ends, scroll/scrub doesn't leak into the new app

## 10. HUD / overlay

- [ ] Volume / brightness HUD: identical to F-key HUD, no clone visible
- [ ] Scrub HUD: visible during drag, fades after release
- [ ] Scroll HUD (if any): same
- [ ] HUD on external display: shows on the **correct** display (same one the gesture is acting on)
- [ ] Dark Mode: HUD readable
- [ ] Light Mode: HUD readable
- [ ] Reduce Transparency on (System Settings → Accessibility → Display): HUD has solid background
- [ ] Increase Contrast on: HUD readable

## 11. Settings & menu bar

- [ ] Menu bar icon appears on launch
- [ ] Settings window opens, closes cleanly, can re-open
- [ ] Per-edge action picker actually swaps which controller fires
- [ ] Sensitivity slider per edge changes drag responsiveness
- [ ] Edge inset (activation zone width) slider: small inset = harder to trigger, large inset = easier
- [ ] Reading-mode toggle in menu bar reflects current state with a checkmark or icon swap
- [ ] Quit menu item actually quits

## 12. Permissions & first-run

- [ ] Fresh user account, app never run: first launch prompts for Accessibility (and Input Monitoring if applicable)
- [ ] User denies the permission: app does not crash; menu bar icon shows a "permission needed" affordance
- [ ] User revokes Accessibility while app is running: gestures stop working without crash; affordance reappears
- [ ] User re-grants: gestures resume without restart, **OR** affordance instructs them to relaunch

## 13. Resource usage

- [ ] Idle (no gestures): < 1% CPU on M-series
- [ ] Active dragging: CPU stays reasonable, no runaway loops
- [ ] RAM after 24h idle: ~20 MB, no leak growth
- [ ] No unexpected network traffic (verify with Little Snitch / Lulu / `nettop` filtered to the EdgePad pid)

## 14. Build & signing

- [ ] `./build.sh` produces `build/EdgePad.app` with no warnings beyond Swift's
- [ ] App launches from `/Applications` (Gatekeeper / quarantine path works after `xattr -dr com.apple.quarantine`)
- [ ] If signed with the local self-signed cert (`scripts/codesign/setup_local.sh`): Accessibility grant **persists across rebuilds**
- [ ] If ad-hoc signed: app still launches and runs (this is the public-build path)

---

When all of the above is ✅ on the target macOS version (current shipping + N-1), tag the release.
