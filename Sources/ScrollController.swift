// ScrollController.swift
//
// Posts scroll wheel events (pixel units) to the focused app via CGEvent.
// Used for:
//   - Bottom-edge horizontal scroll (both profiles)
//   - Right-edge vertical scroll (Reading profile only)
//
// The events are delivered as continuous scroll (pixel-level) so the
// result feels smooth and matches macOS's momentum-free edge pan.

import Foundation
import CoreGraphics

@MainActor
public final class ScrollController {

    /// How many pixels of scroll output per unit of edge delta.
    /// Trackpad delta [0, 1] = full edge travel; screen width ~1600px
    /// means a full-edge drag = ~3200px of scroll at sensitivity 2.0.
    public var horizontalSensitivity: Float = 800
    public var verticalSensitivity: Float = 800

    // Track the last delta we emitted so we can send INCREMENTAL scroll
    // steps rather than absolute-from-start. Edge drags give us absolute
    // deltas from drag start; scroll events want frame-to-frame deltas.
    private var lastHorizontalDelta: Float = 0
    private var lastVerticalDelta: Float = 0

    public init() {}

    public func reset() {
        lastHorizontalDelta = 0
        lastVerticalDelta = 0
    }

    /// Called on each edge drag update for horizontal-scroll-mapped
    /// edges. `delta` is the signed travel from drag start.
    public func handleHorizontalEdgeDelta(_ delta: Float) {
        let step = delta - lastHorizontalDelta
        lastHorizontalDelta = delta
        let pixels = Int32(step * horizontalSensitivity)
        guard pixels != 0 else { return }
        postScroll(horizontal: pixels, vertical: 0)
    }

    /// Called on each edge drag update for vertical-scroll-mapped edges.
    public func handleVerticalEdgeDelta(_ delta: Float) {
        let step = delta - lastVerticalDelta
        lastVerticalDelta = delta
        let pixels = Int32(step * verticalSensitivity)
        guard pixels != 0 else { return }
        postScroll(horizontal: 0, vertical: pixels)
    }

    // MARK: - Private

    private func postScroll(horizontal: Int32, vertical: Int32) {
        // CGEvent scrollWheelEvent2 with 2 wheels: wheel1 = vertical,
        // wheel2 = horizontal. .pixel units for smooth, momentum-free
        // scrolling. nil source = default event source.
        NSLog("[SCR] post scroll h=\(horizontal) v=\(vertical)")
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: vertical,
            wheel2: horizontal,
            wheel3: 0
        ) else {
            NSLog("[SCR] ✗ CGEvent creation returned nil")
            return
        }
        event.post(tap: .cghidEventTap)
    }
}
