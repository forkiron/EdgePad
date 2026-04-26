// OverlayWindow.swift
//
// Borderless, click-through, always-on-top HUD window for actions that
// don't have a native macOS HUD equivalent (currently just scrub).
// Volume and brightness go through NativeHUD instead — they trigger
// the real OSDManager overlay so the user sees Apple's actual HUD.
// Scroll has no overlay: the page moving under the cursor is the
// feedback.

import AppKit

@MainActor
public final class OverlayWindow {

    public enum HUDKind {
        case scrub

        var icon: String {
            switch self {
            case .scrub: return "\u{25B6}"   // ▶
            }
        }

        var label: String {
            switch self {
            case .scrub: return "Scrub"
            }
        }
    }

    private var window: NSWindow?
    private var hideWorkItem: DispatchWorkItem?

    public init() {}

    public func showPulse(kind: HUDKind, direction: Int) {
        ensureWindow()
        guard let window, let view = window.contentView as? HUDView else { return }
        view.pulse(kind: kind, direction: direction)
        window.orderFrontRegardless()
        scheduleHide(after: 0.6)
    }

    public func hide() {
        hideWorkItem?.cancel()
        window?.orderOut(nil)
    }

    // MARK: - Private

    private func ensureWindow() {
        if window != nil { return }

        let size = NSSize(width: 220, height: 220)
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let origin = NSPoint(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.minY + 80
        )
        let frame = NSRect(origin: origin, size: size)

        let w = NSWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        w.level = .statusBar
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = true
        w.ignoresMouseEvents = true
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let view = HUDView(frame: NSRect(origin: .zero, size: size))
        w.contentView = view
        window = w
    }

    private func scheduleHide(after seconds: TimeInterval) {
        hideWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.window?.orderOut(nil)
        }
        hideWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
    }
}

// MARK: - HUDView

private final class HUDView: NSView {

    private var kind: OverlayWindow.HUDKind = .scrub
    private var pulseDirection: CGFloat = 0

    override var isFlipped: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 24
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) { fatalError() }

    func pulse(kind: OverlayWindow.HUDKind, direction: Int) {
        self.kind = kind
        self.pulseDirection = direction >= 0 ? 1 : -1
        needsDisplay = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.pulseDirection = 0
            self?.needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds

        NSColor(calibratedWhite: 0.1, alpha: 0.85).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 24, yRadius: 24).fill()

        let iconFont = NSFont.systemFont(ofSize: 44, weight: .medium)
        let iconAttrs: [NSAttributedString.Key: Any] = [
            .font: iconFont,
            .foregroundColor: NSColor.white.withAlphaComponent(0.95),
        ]
        let iconStr = kind.icon as NSString
        let iconSize = iconStr.size(withAttributes: iconAttrs)
        iconStr.draw(
            at: NSPoint(x: (rect.width - iconSize.width) / 2, y: rect.height - 88),
            withAttributes: iconAttrs
        )

        let labelFont = NSFont.systemFont(ofSize: 12, weight: .medium)
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: NSColor.white.withAlphaComponent(0.6),
        ]
        let labelStr = kind.label as NSString
        let labelSize = labelStr.size(withAttributes: labelAttrs)
        labelStr.draw(
            at: NSPoint(x: (rect.width - labelSize.width) / 2, y: rect.height - 108),
            withAttributes: labelAttrs
        )

        let arrow: NSString
        switch kind {
        case .scrub:
            arrow = pulseDirection >= 0 ? "\u{25B6}\u{25B6}" : "\u{25C0}\u{25C0}"
        }
        let arrowFont = NSFont.systemFont(ofSize: 36, weight: .bold)
        let alpha = 0.4 + 0.5 * abs(pulseDirection)
        let arrowAttrs: [NSAttributedString.Key: Any] = [
            .font: arrowFont,
            .foregroundColor: NSColor.white.withAlphaComponent(alpha),
        ]
        let sz = arrow.size(withAttributes: arrowAttrs)
        arrow.draw(
            at: NSPoint(x: (rect.width - sz.width) / 2, y: 36),
            withAttributes: arrowAttrs
        )
    }
}
