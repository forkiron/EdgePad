// ScrollDetector.swift
//
// Uses the macOS Accessibility API to determine whether the element
// under a screen point can scroll along a given axis.
//
// Strategy (layered, most-reliable-first):
//   1. AXUIElementCopyElementAtPosition gets the leaf element under cursor;
//      walk up the parent chain to find the nearest AXScrollArea ancestor.
//   2. On that scroll area, query AXHorizontalScrollBar / AXVerticalScrollBar.
//      If the bar is exposed for the requested axis → trust it. This is
//      definitive when present.
//   3. Otherwise fall back to overflow detection: compare the scroll area's
//      AXSize to the bounding size of its AXContents children. This is the
//      native equivalent of `element.scrollWidth > element.clientWidth` on
//      web — and is what we *should* be using, because macOS hides scroll
//      bars by default for trackpad users (especially in Chromium-based
//      browsers), so AXScrollBar absence does NOT imply "not scrollable".
//   4. Last-resort fallback: vertical permissive, horizontal strict. False
//      positives on horizontal scroll (firing where there's no h-content)
//      are much more annoying than false negatives, so we'd rather suppress.
//
// Known limitation: macOS accessibility zoom and browser pinch-zoom can
// allow horizontal panning even when content has no real overflow (visual
// viewport < layout viewport). AX doesn't expose this state cleanly, so
// we don't detect it.
//
// Failure mode: if AX queries fail entirely (no permission, weird app),
// fail open — better to occasionally fire a no-op scroll than silently
// swallow gestures.

import ApplicationServices
import CoreGraphics
import Foundation

@MainActor
public enum ScrollAxis {
    case horizontal
    case vertical
}

@MainActor
public enum ScrollDetector {

    /// Returns true if the element under the given screen point appears
    /// to be scrollable along the requested axis.
    public static func canScroll(at point: CGPoint, axis: ScrollAxis) -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var elementRef: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(
            systemWide,
            Float(point.x),
            Float(point.y),
            &elementRef
        )
        guard result == .success, let leaf = elementRef else {
            NSLog("[SCD] no AX element at (\(point.x), \(point.y)) — fail open")
            return true
        }

        // Walk up looking for a scrollable container. AXScrollArea is the
        // native AppKit role; AXWebArea is what Safari/Chromium expose for
        // the page itself (often without an enclosing AXScrollArea).
        var current: AXUIElement? = leaf
        var depth = 0
        while let cur = current, depth < 30 {
            let r = role(of: cur)
            if r == kAXScrollAreaRole || r == "AXWebArea" {
                return canScrollIn(cur, role: r ?? "?", axis: axis, depth: depth)
            }
            current = parent(of: cur)
            depth += 1
        }

        NSLog("[SCD] no scrollable ancestor (depth=\(depth)) — fail open")
        return true
    }

    // MARK: - Per-area decision

    /// Decide whether the given scrollable container can scroll on the
    /// requested axis.
    ///
    ///   Vertical — permissive. Most pages scroll vertically, and AX in
    ///     browsers does NOT expose enough info to detect "no vertical
    ///     scroll" reliably (AXContents reports visible-viewport size,
    ///     not document scrollHeight).
    ///
    ///   Horizontal — layered:
    ///     1. AXHorizontalScrollBar exposed → definitive yes.
    ///     2. Width-overflow detected → definitive yes.
    ///     3. AXVerticalScrollBar exposed but NOT AXHorizontalScrollBar
    ///        → definitive no (native AppKit pattern: a Notes/Mail window
    ///        with vertical-only scroll exposes only the v-bar).
    ///     4. No clear AX signal → fail open. This handles browser pinch
    ///        zoom, macOS accessibility zoom, and Chromium-style apps that
    ///        hide all AX scroll-bar attributes — cases where horizontal
    ///        panning is genuinely possible but AX won't tell us.
    private static func canScrollIn(_ area: AXUIElement, role: String, axis: ScrollAxis, depth: Int) -> Bool {
        if axis == .vertical {
            NSLog("[SCD] depth=\(depth) role=\(role) → vertical=true (permissive)")
            return true
        }

        var hBarRef: CFTypeRef?
        var vBarRef: CFTypeRef?
        AXUIElementCopyAttributeValue(area, kAXHorizontalScrollBarAttribute as CFString, &hBarRef)
        AXUIElementCopyAttributeValue(area, kAXVerticalScrollBarAttribute as CFString, &vBarRef)
        let hasH = hBarRef != nil
        let hasV = vBarRef != nil

        // 1. Definitive: explicit horizontal bar.
        if hasH {
            NSLog("[SCD] depth=\(depth) role=\(role) AXHorizontalScrollBar present → horizontal=true")
            return true
        }

        // 2. Definitive: detected width-overflow.
        if let viewport = size(of: area), let content = contentExtent(of: area) {
            if content.width > viewport.width + 1 {
                NSLog("[SCD] depth=\(depth) role=\(role) overflow content.w=\(content.width) > viewport.w=\(viewport.width) → horizontal=true")
                return true
            }
        }

        // 3. Definitive negative: vertical bar exposed but no horizontal —
        //    typical native-AppKit "vertical-only scroll" pattern.
        if hasV {
            NSLog("[SCD] depth=\(depth) role=\(role) hasV=true hasH=false → horizontal=false (vertical-only)")
            return false
        }

        // 4. No signal — fail open. Browser pinch-zoom, macOS zoom-pan,
        //    and Chromium-style apps that hide all AX bars all land here.
        NSLog("[SCD] depth=\(depth) role=\(role) no AX scroll-bar signal — horizontal=true (fail open for zoom-pan)")
        return true
    }

    // MARK: - AX helpers

    private static func role(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let r = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value)
        guard r == .success else { return nil }
        return value as? String
    }

    private static func parent(of element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        let r = AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &value)
        guard r == .success, let v = value else { return nil }
        return (v as! AXUIElement)
    }

    /// Returns the on-screen size of an AX element, in screen points.
    private static func size(of element: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &value) == .success,
              let v = value,
              CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        let axValue = v as! AXValue
        guard AXValueGetValue(axValue, .cgSize, &size) else { return nil }
        return size
    }

    /// Bounding size of a scroll area's contents — the native equivalent of
    /// `element.scrollWidth × element.scrollHeight`. We use AXContents when
    /// available (it's the canonical attribute for scroll-area content) and
    /// fall back to AXChildren for apps that don't expose AXContents.
    private static func contentExtent(of scrollArea: AXUIElement) -> CGSize? {
        var contentsRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(scrollArea, kAXContentsAttribute as CFString, &contentsRef) == .success,
           let contents = contentsRef as? [AXUIElement],
           let extent = boundingSize(of: contents) {
            return extent
        }
        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(scrollArea, kAXChildrenAttribute as CFString, &childrenRef) == .success,
           let children = childrenRef as? [AXUIElement] {
            return boundingSize(of: children)
        }
        return nil
    }

    /// Max width × max height across a set of AX elements.
    private static func boundingSize(of elements: [AXUIElement]) -> CGSize? {
        var maxWidth: CGFloat = 0
        var maxHeight: CGFloat = 0
        var found = false
        for el in elements {
            if let s = size(of: el) {
                maxWidth = max(maxWidth, s.width)
                maxHeight = max(maxHeight, s.height)
                found = true
            }
        }
        return found ? CGSize(width: maxWidth, height: maxHeight) : nil
    }
}
