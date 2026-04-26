// AXScrubber.swift
//
// Find and drive a video / audio scrubber via the macOS Accessibility
// API — the same channel a screen reader uses. Lets us scrub directly
// into the page's slider element, bypassing per-site keybinding
// quirks (X swallowing arrows, JS players intercepting input, etc.).
//
// Search order at drag-begin:
//   1. Element under the cursor → walk up looking for AXSlider
//   2. System-wide focused element → walk up
//   3. Focused window's AX tree (depth-limited) → first slider whose
//      role description / parent / siblings look video-y
//
// On each scrub-delta the caller calls `setValue(_:)` which writes
// kAXValueAttribute. The page's slider `input` listener fires and
// the video seeks. AX queries cache poorly across frames, so the
// expensive search runs once at arm-time; per-frame writes are cheap.
//
// Coverage:
//   - Works: HTML <input type="range">, modern role="slider" custom
//     scrubbers (LinkedIn, YouTube, Vimeo, most embedded video).
//   - Won't work: sites that don't expose the scrubber via AX, or
//     hide it until hover (some autoplay players). Falls back to
//     arrow / skip modes via MediaController.

import AppKit
import ApplicationServices
import Foundation

@MainActor
public enum AXScrubber {

    /// A located scrubber and the values needed to drive it.
    /// `AXUIElement` is a CFType (retain/release-managed) so it is
    /// safe to share across actors — the @unchecked is just because
    /// the compiler can't see the C-level memory management.
    public struct Handle: @unchecked Sendable {
        public let element: AXUIElement
        public let initialValue: Double
        public let minValue: Double
        public let maxValue: Double
        public let label: String   // for logging
    }

    /// Scrubber-y substrings we accept in role description / title /
    /// description / label. Generous on purpose — different browsers
    /// and apps publish different strings. False positives are bounded
    /// because we still require role==AXSlider (or subrole==AXTimeline).
    private static let scrubberHints: [String] = [
        "video", "movie", "player", "playback", "playhead", "scrub",
        "seek", "time", "timeline", "progress", "position", "duration",
    ]

    /// Anti-hints — sliders matching these are almost never the
    /// playback scrubber. "scroll" / "scrollbar" / "page" reject the
    /// page's own scrollbar slider (which some browsers expose as
    /// AXSlider rather than AXScrollBar); the rest reject volume /
    /// zoom / etc.
    private static let scrubberAntiHints: [String] = [
        "scroll", "scrollbar", "page", "vertical scroll", "horizontal scroll",
        "volume", "brightness", "zoom", "speed", "rate", "size", "scale",
    ]

    /// Find a plausible scrubber for the current focus state. Returns
    /// nil if nothing slidery is exposed via AX.
    ///
    /// Only the under-cursor and walk-up-from-focus paths run — they
    /// require the user to have positioned the cursor near the
    /// scrubber, which keeps the search bounded AND prevents us from
    /// grabbing an unrelated AXSlider somewhere else in the window
    /// (e.g. browser zoom UI, settings controls, page scrollbar).
    public static func findSlider() -> Handle? {
        let cursor = CGEvent(source: nil)?.location ?? .zero
        if let h = sliderUnderPoint(cursor) { return capture(h, label: "under cursor") }
        if let h = sliderFromFocus()         { return capture(h, label: "from focus") }
        return nil
    }

    /// Write the slider to `value`, clamped to its known range. Returns
    /// false on AX error so the caller can fall back to arrow keys.
    @discardableResult
    public static func setValue(_ handle: Handle, to value: Double) -> Bool {
        let clamped = max(handle.minValue, min(handle.maxValue, value))
        let n = NSNumber(value: clamped)
        let status = AXUIElementSetAttributeValue(handle.element, kAXValueAttribute as CFString, n)
        return status == .success
    }

    // MARK: - Search

    private static func sliderUnderPoint(_ point: CGPoint) -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var hit: AXUIElement?
        let status = AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &hit)
        guard status == .success, let hit else { return nil }
        return walkUpToSlider(from: hit)
    }

    private static func sliderFromFocus() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &ref) == .success,
              let cf = ref, CFGetTypeID(cf) == AXUIElementGetTypeID() else { return nil }
        return walkUpToSlider(from: cf as! AXUIElement)
    }

    /// From a starting element, walk up to 8 ancestors looking for an
    /// AXSlider. Returns the first plausible scrubber.
    private static func walkUpToSlider(from start: AXUIElement) -> AXUIElement? {
        var current: AXUIElement? = start
        for _ in 0..<8 {
            guard let el = current else { return nil }
            if let slider = matchSlider(el) { return slider }
            // Also check immediate children — sometimes the hit-tested
            // element is a wrapper containing a sibling slider.
            if let children = childrenOf(el) {
                for child in children.prefix(12) {
                    if let s = matchSlider(child) { return s }
                }
            }
            var parentRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(el, kAXParentAttribute as CFString, &parentRef) == .success,
               let p = parentRef, CFGetTypeID(p) == AXUIElementGetTypeID() {
                current = (p as! AXUIElement)
            } else {
                return nil
            }
        }
        return nil
    }

    /// True if `element` is a slider that smells like a playback
    /// scrubber. Returns the element on match, nil otherwise.
    private static func matchSlider(_ element: AXUIElement) -> AXUIElement? {
        guard let role = stringAttr(element, kAXRoleAttribute as CFString) else { return nil }
        guard role == "AXSlider" else { return nil }

        // Subrole — modern WebKit uses AXTimeline for video scrubbers
        // even when role is generic. Strong positive signal.
        if let sub = stringAttr(element, kAXSubroleAttribute as CFString),
           sub.contains("Timeline") || sub.contains("ScrubBar") {
            return element
        }

        // Hint-bag: combine role description / title / description /
        // help / value description into one lowercased blob and look
        // for both positive and negative substrings.
        var bag = ""
        for key in [
            kAXRoleDescriptionAttribute,
            kAXTitleAttribute,
            kAXDescriptionAttribute,
            kAXHelpAttribute,
            kAXValueDescriptionAttribute,
        ] {
            if let s = stringAttr(element, key as CFString) {
                bag += " " + s.lowercased()
            }
        }
        // Anti-hints win: a slider explicitly labeled "volume" is not a
        // video scrubber even if some other field says "player".
        for anti in scrubberAntiHints where bag.contains(anti) { return nil }
        for hint in scrubberHints where bag.contains(hint) { return element }

        // Last-ditch: AX min/max look like a duration in seconds (>30
        // and <86400 = 24h). Catches plain `<input type="range">` with
        // no labels. Only accepts when nothing actively rejects.
        if let min = numberAttr(element, kAXMinValueAttribute as CFString),
           let max = numberAttr(element, kAXMaxValueAttribute as CFString),
           min == 0, max > 30, max < 86400 {
            return element
        }
        return nil
    }

    private static func capture(_ element: AXUIElement, label: String) -> Handle? {
        let value = numberAttr(element, kAXValueAttribute as CFString) ?? 0
        // Many sliders publish 0…1 or 0…duration. If min/max are
        // missing, default to 0…1; setValue clamps anyway.
        let minV = numberAttr(element, kAXMinValueAttribute as CFString) ?? 0
        let maxV = numberAttr(element, kAXMaxValueAttribute as CFString) ?? 1
        guard maxV > minV else { return nil }

        // Prefer a human-readable label for logs.
        let title = stringAttr(element, kAXTitleAttribute as CFString)
            ?? stringAttr(element, kAXDescriptionAttribute as CFString)
            ?? stringAttr(element, kAXRoleDescriptionAttribute as CFString)
            ?? "(unnamed)"
        NSLog("[AXS] found slider \(label): \"\(title.prefix(40))\" value=\(value) range=\(minV)…\(maxV)")
        return Handle(element: element, initialValue: value, minValue: minV, maxValue: maxV, label: title)
    }

    // MARK: - AX helpers

    private static func stringAttr(_ element: AXUIElement, _ key: CFString) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key, &ref) == .success else { return nil }
        return ref as? String
    }

    private static func numberAttr(_ element: AXUIElement, _ key: CFString) -> Double? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key, &ref) == .success else { return nil }
        if let n = ref as? NSNumber { return n.doubleValue }
        return nil
    }

    private static func childrenOf(_ element: AXUIElement) -> [AXUIElement]? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &ref) == .success else { return nil }
        return ref as? [AXUIElement]
    }
}
