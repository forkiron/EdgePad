# Feature Specification: Edge Detection

**Status**: Approved
**Priority**: P0
**PRD Reference**: Section 5, Features 1 & 2
**Author**: Thomas Lenh
**Last Updated**: 2026-04-11

## Overview

The core gesture primitive of EdgePad. Converts a stream of raw multitouch contacts into clean `EdgeDragEvent` messages ("the user is dragging along the left edge, current delta from start is +0.32"). Every feature in the app sits downstream of this component.

## User Stories

1. As a user, when I place a finger in an edge zone and slide along it, EdgePad recognizes the gesture as an edge drag and not as normal cursor movement.
2. As a user, when I tap randomly in the middle of my trackpad, EdgePad does nothing.
3. As a user, when I'm typing and my palm brushes the edge, EdgePad does not trigger an accidental volume change.
4. As a user, when I touch an edge but don't move, nothing happens — only deliberate sliding registers.

## Acceptance Criteria

- [ ] Top, bottom, left, right edges each detectable independently
- [ ] Activation zone is configurable (default 10% inset from each edge)
- [ ] Dead zone of 1.5% prevents tap jitter and palm brushes
- [ ] Drag continues if the finger drifts outside the edge strip after start (grab-and-drag feel)
- [ ] Single-finger only; multi-touch cancels an active drag
- [ ] Typing suppression: ignore new drags for 300 ms after any key event from `NSEvent.addGlobalMonitorForEvents(.keyDown)`
- [ ] Clean `begin / update / end` lifecycle delivered to delegate
- [ ] Pure `@MainActor` logic, testable with synthetic `TouchSample` sequences
- [ ] Handles touch IDs robustly: one active drag per touch ID, new ID = potential new drag

## Technical Design

### Architecture

```
MultitouchSupport.framework ─► MultitouchCapture ─► EdgeDetector ─► delegate
   (C callback, dlopen)        (TouchSample)        (EdgeDragEvent)
```

`EdgeDetector` is a pure state machine. No UI, no system calls, no side effects. That makes it unit-testable.

### State machine

```
IDLE ──(touch lands in edge zone)──► LANDED
LANDED ──(delta ≥ deadZone)──► DRAGGING
LANDED ──(touch ends / multi-finger)──► IDLE
DRAGGING ──(touch ends / multi-finger)──► IDLE (emit didEndDrag)
DRAGGING ──(touch update)──► DRAGGING (emit didUpdate)
```

### Edge classification

A touch sample is classified as:
- `.top` if `y > 1 - edgeInset`
- `.bottom` if `y < edgeInset`
- `.left` if `x < edgeInset`
- `.right` if `x > 1 - edgeInset`
- `nil` otherwise

Edge corners (e.g., `x < inset && y < inset`) are classified by whichever side the touch is _deeper_ into — but simpler: first check in order `top, bottom, left, right` and pick the first match. Corners are rare enough that this works.

### Axis per edge

```swift
func axisPosition(for edge: TrackpadEdge, x: Float, y: Float) -> Float {
    switch edge {
    case .top, .bottom: return x   // horizontal slide
    case .left, .right: return y   // vertical slide
    }
}
```

### Relative delta

At drag-start, capture `startPosition = axisPosition(for: edge, x, y)`.
On each update, `delta = currentAxisPosition - startPosition`.
Emit `EdgeDragEvent(edge, delta, position, isStart)`.

### Typing suppression

- Install `NSEvent.addGlobalMonitorForEvents(matching: [.keyDown])` in `AppDelegate`
- On each keydown, set `lastKeyDownTime = CACurrentMediaTime()`
- In `EdgeDetector.shouldAcceptNewDrag()`, check `CACurrentMediaTime() - lastKeyDownTime > 0.3`
- Active drags are NOT cancelled by typing — only new drag starts are suppressed

### Multi-finger cancellation

`MultitouchSupport.framework` delivers an array of active contacts per frame via the C callback. If the array size > 1 while we're in LANDED or DRAGGING state, we cancel the drag and return to IDLE.

## Data Models

```swift
public struct TouchSample: Sendable {
    public let id: Int32         // per-finger identifier from MTData
    public let x: Float          // 0…1
    public let y: Float          // 0…1, 0 = bottom
    public let pressure: Float   // 0…1
    public let timestamp: Double
}

public enum TrackpadEdge: Sendable {
    case top, bottom, left, right
}

public struct EdgeDragEvent: Sendable {
    public let edge: TrackpadEdge
    public let delta: Float       // signed travel since drag start
    public let position: Float    // current axis position [0, 1]
    public let isStart: Bool
}

@MainActor
public protocol EdgeDetectorDelegate: AnyObject {
    func edgeDetector(_ d: EdgeDetector, didBeginDragOn edge: TrackpadEdge, at position: Float)
    func edgeDetector(_ d: EdgeDetector, didUpdate event: EdgeDragEvent)
    func edgeDetector(_ d: EdgeDetector, didEndDragOn edge: TrackpadEdge)
}
```

## Edge Cases

- **Finger lifts briefly then returns** — touch ID changes, treat as new gesture
- **Two fingers in two edge zones** — cancel both, wait for single-finger
- **Touch starts in edge, moves to center, moves back** — drag stays active throughout
- **Trackpad disconnect mid-drag** — MT stream stops, treat as drag end
- **Framework returns out-of-range coordinates** — clamp to [0, 1] before classification
- **System wake from sleep** — reset state on `NSWorkspace.didWakeNotification`

## Testing Plan

Unit tests in `EdgeDetectorTests.swift`:

1. `testTouchInCenterDoesNotTriggerDrag`
2. `testTouchInLeftEdgeBeginsLeftDrag`
3. `testDragBelowDeadZoneDoesNotEmit`
4. `testDragAboveDeadZoneEmitsBeginAndUpdate`
5. `testDragContinuesWhenFingerLeavesEdgeZone`
6. `testMultiFingerCancelsActiveDrag`
7. `testNewTouchIdStartsFreshDrag`
8. `testTypingSuppressionPreventsNewDrag`
9. `testTypingSuppressionDoesNotCancelActiveDrag`

Each test injects synthetic `TouchSample` values into a fresh `EdgeDetector` and asserts on the delegate calls via a mock delegate.

## Open Questions

- [ ] What should `edgeInset` default to? 10% feels right on a 16" MacBook Pro; possibly tighter on external Magic Trackpads
- [ ] Should typing suppression be per-edge or global? (start global, add per-edge tuning if requested)
- [ ] Palm rejection beyond typing suppression — do we need anything?
