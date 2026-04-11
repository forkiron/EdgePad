// OverlayWindow.swift
//
// Borderless, click-through, always-on-top HUD window. Mimics the macOS
// native volume/brightness HUD so it feels like a system control rather
// than a third-party overlay.

import AppKit

@MainActor
public final class OverlayWindow {

    public enum HUDKind {
        case volume
        case brightness
        case scrub
        case scrollHorizontal
        case scrollVertical

        var icon: String {
            switch self {
            case .volume:            return "\u{1F50A}"  // 🔊
            case .brightness:        return "\u{2600}"   // ☀
            case .scrub:             return "\u{25B6}"   // ▶
            case .scrollHorizontal:  return "\u{2B0C}"   // ⬌
            case .scrollVertical:    return "\u{2B0D}"   // ⬍
            }
        }

        var label: String {
            switch self {
            case .volume:            return "Volume"
            case .brightness:        return "Brightness"
            case .scrub:             return "Scrub"
            case .scrollHorizontal:  return "Scroll"
            case .scrollVertical:    return "Scroll"
            }
        }

        var hasValueBar: Bool {
            switch self {
            case .volume, .brightness: return true
            default: return false
            }
        }
    }

    private var window: NSWindow?
    private var hideWorkItem: DispatchWorkItem?

    public init() {}

    public func showValue(kind: HUDKind, value: Float) {
        ensureWindow()
        guard let window, let view = window.contentView as? HUDView else { return }
        view.update(kind: kind, value: value)
        window.orderFrontRegardless()
        scheduleHide(after: 0.9)
    }

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

    private var kind: OverlayWindow.HUDKind = .volume
    private var value: Float = 0
    private var pulseDirection: CGFloat = 0

    override var isFlipped: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 24
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(kind: OverlayWindow.HUDKind, value: Float) {
        self.kind = kind
        self.value = max(0, min(1, value))
        self.pulseDirection = 0
        needsDisplay = true
    }

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

        if kind.hasValueBar {
            let barWidth: CGFloat = rect.width - 48
            let barHeight: CGFloat = 8
            let barX = (rect.width - barWidth) / 2
            let barY: CGFloat = 44

            NSColor.white.withAlphaComponent(0.18).setFill()
            NSBezierPath(
                roundedRect: NSRect(x: barX, y: barY, width: barWidth, height: barHeight),
                xRadius: 4, yRadius: 4
            ).fill()

            NSColor.white.withAlphaComponent(0.95).setFill()
            NSBezierPath(
                roundedRect: NSRect(x: barX, y: barY, width: barWidth * CGFloat(value), height: barHeight),
                xRadius: 4, yRadius: 4
            ).fill()
        } else {
            let arrow: NSString
            switch kind {
            case .scrub:
                arrow = pulseDirection >= 0 ? "\u{25B6}\u{25B6}" : "\u{25C0}\u{25C0}"
            case .scrollHorizontal:
                arrow = pulseDirection >= 0 ? "\u{279C}" : "\u{2B05}"
            case .scrollVertical:
                arrow = pulseDirection >= 0 ? "\u{2B06}" : "\u{2B07}"
            default:
                arrow = ""
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
}
