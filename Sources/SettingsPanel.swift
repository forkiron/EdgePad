// SettingsPanel.swift
//
// Frosted glass settings panel — macOS Control Center aesthetic.
// Sensitivity sliders + interactive edge zone preview.

import AppKit

@MainActor
final class SettingsPanel {

    private var panel: NSPanel?

    // Bound controllers
    private weak var detector: EdgeDetector?
    private weak var scroll: ScrollController?
    private weak var volume: VolumeController?
    private weak var brightness: BrightnessController?
    private weak var media: MediaController?

    // Views that need updating
    private var trackpadPreview: TrackpadPreviewView?
    private var edgeSlider: NSSlider?
    private var edgeLabel: NSTextField?

    func configure(
        detector: EdgeDetector,
        scroll: ScrollController,
        volume: VolumeController,
        brightness: BrightnessController,
        media: MediaController
    ) {
        self.detector = detector
        self.scroll = scroll
        self.volume = volume
        self.brightness = brightness
        self.media = media
    }

    func toggle() {
        if let p = panel, p.isVisible {
            p.close()
        } else {
            show()
        }
    }

    private func show() {
        if panel == nil { buildPanel() }
        guard let panel else { return }

        // Position near menu bar, right side
        if let screen = NSScreen.main {
            let x = screen.frame.maxX - 340
            let y = screen.frame.maxY - 60 - panel.frame.height
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        panel.makeKeyAndOrderFront(nil)
    }

    // MARK: - Build

    private func buildPanel() {
        let width: CGFloat = 300
        let height: CGFloat = 440

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.titlebarAppearsTransparent = true
        p.titleVisibility = .hidden
        p.isMovableByWindowBackground = true
        p.level = .floating
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true

        // Frosted glass background
        let vibrancy = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        vibrancy.blendingMode = .behindWindow
        vibrancy.material = .hudWindow
        vibrancy.state = .active
        vibrancy.wantsLayer = true
        vibrancy.layer?.cornerRadius = 14
        vibrancy.layer?.masksToBounds = true
        p.contentView = vibrancy

        var y = height - 40

        // Title
        y -= 24
        addLabel("EdgePad", at: y, in: vibrancy, size: 16, bold: true, width: width)

        // — Sensitivity section —
        y -= 36
        addSectionHeader("Sensitivity", at: y, in: vibrancy, width: width)

        y -= 30
        addSliderRow("Scroll", at: y, in: vibrancy, width: width,
                     min: 200, max: 2000, value: Float(scroll?.horizontalSensitivity ?? 800)) { [weak self] val in
            self?.scroll?.horizontalSensitivity = val
            self?.scroll?.verticalSensitivity = val
        }

        y -= 30
        addSliderRow("Volume", at: y, in: vibrancy, width: width,
                     min: 0.3, max: 3.0, value: volume?.sensitivity ?? 1.2) { [weak self] val in
            self?.volume?.sensitivity = val
        }

        y -= 30
        addSliderRow("Brightness", at: y, in: vibrancy, width: width,
                     min: 0.3, max: 3.0, value: brightness?.sensitivity ?? 1.2) { [weak self] val in
            self?.brightness?.sensitivity = val
        }

        y -= 30
        addSliderRow("Scrub", at: y, in: vibrancy, width: width,
                     min: 0.02, max: 0.15, value: media?.stepSize ?? 0.05) { [weak self] val in
            self?.media?.stepSize = val
        }

        // — Edge Zone section —
        y -= 40
        addSectionHeader("Edge Zone", at: y, in: vibrancy, width: width)

        y -= 30
        let insetPct = Int((detector?.edgeInset ?? 0.10) * 100)
        let label = addLabel("\(insetPct)%", at: y + 2, in: vibrancy, size: 12, bold: false, width: width, align: .right, rightPad: 20)
        edgeLabel = label

        let slider = NSSlider(frame: NSRect(x: 80, y: y, width: width - 120, height: 20))
        slider.minValue = 5
        slider.maxValue = 25
        slider.doubleValue = Double((detector?.edgeInset ?? 0.10) * 100)
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(edgeInsetChanged(_:))
        vibrancy.addSubview(slider)
        edgeSlider = slider

        addLabel("Width", at: y + 2, in: vibrancy, size: 12, bold: false, width: width, align: .left, leftPad: 20)

        // Trackpad preview
        y -= 150
        let preview = TrackpadPreviewView(
            frame: NSRect(x: 40, y: y, width: width - 80, height: 130)
        )
        preview.edgeInset = CGFloat(detector?.edgeInset ?? 0.10)
        vibrancy.addSubview(preview)
        trackpadPreview = preview

        panel = p
    }

    // MARK: - Actions

    @objc private func edgeInsetChanged(_ sender: NSSlider) {
        let pct = Float(sender.doubleValue) / 100.0
        detector?.edgeInset = pct
        edgeLabel?.stringValue = "\(Int(sender.doubleValue))%"
        trackpadPreview?.edgeInset = CGFloat(pct)
        trackpadPreview?.needsDisplay = true
    }

    // MARK: - UI Helpers

    private typealias SliderCallback = (Float) -> Void
    private var sliderCallbacks: [NSSlider: SliderCallback] = [:]

    private func addSliderRow(
        _ title: String, at y: CGFloat, in parent: NSView, width: CGFloat,
        min: Float, max: Float, value: Float, onChange: @escaping SliderCallback
    ) {
        addLabel(title, at: y + 2, in: parent, size: 12, bold: false, width: width, align: .left, leftPad: 20)

        let slider = NSSlider(frame: NSRect(x: 100, y: y, width: width - 130, height: 20))
        slider.minValue = Double(min)
        slider.maxValue = Double(max)
        slider.doubleValue = Double(value)
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(sliderMoved(_:))
        parent.addSubview(slider)
        sliderCallbacks[slider] = onChange
    }

    @objc private func sliderMoved(_ sender: NSSlider) {
        sliderCallbacks[sender]?(Float(sender.doubleValue))
    }

    @discardableResult
    private func addLabel(
        _ text: String, at y: CGFloat, in parent: NSView,
        size: CGFloat, bold: Bool, width: CGFloat,
        align: NSTextAlignment = .center,
        leftPad: CGFloat = 0, rightPad: CGFloat = 0
    ) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = bold ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size)
        label.textColor = .labelColor
        label.alignment = align
        let lx = leftPad > 0 ? leftPad : rightPad > 0 ? 0 : 0
        let lw = leftPad > 0 || rightPad > 0 ? width - leftPad - rightPad : width
        label.frame = NSRect(x: lx, y: y, width: lw, height: 18)
        parent.addSubview(label)
        return label
    }

    private func addSectionHeader(_ text: String, at y: CGFloat, in parent: NSView, width: CGFloat) {
        let label = NSTextField(labelWithString: text.uppercased())
        label.font = .systemFont(ofSize: 10, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.frame = NSRect(x: 20, y: y, width: width - 40, height: 14)
        parent.addSubview(label)
    }
}

// MARK: - Trackpad Preview

private final class TrackpadPreviewView: NSView {

    var edgeInset: CGFloat = 0.10 {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds

        // Trackpad body
        NSColor.white.withAlphaComponent(0.08).setFill()
        let body = NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12)
        body.fill()

        // Border
        NSColor.white.withAlphaComponent(0.15).setStroke()
        body.lineWidth = 1
        body.stroke()

        // Edge zones
        let color = NSColor.systemBlue.withAlphaComponent(0.25)
        color.setFill()

        let inW = rect.width * edgeInset
        let inH = rect.height * edgeInset

        // Top
        NSBezierPath(roundedRect: NSRect(x: 0, y: rect.height - inH, width: rect.width, height: inH),
                     xRadius: 12, yRadius: 0).fill()
        // Bottom
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: rect.width, height: inH),
                     xRadius: 0, yRadius: 12).fill()
        // Left
        NSBezierPath(rect: NSRect(x: 0, y: inH, width: inW, height: rect.height - 2 * inH)).fill()
        // Right
        NSBezierPath(rect: NSRect(x: rect.width - inW, y: inH, width: inW, height: rect.height - 2 * inH)).fill()

        // Center label
        let centerRect = NSRect(
            x: inW, y: inH,
            width: rect.width - 2 * inW,
            height: rect.height - 2 * inH
        )
        NSColor.white.withAlphaComponent(0.06).setFill()
        NSBezierPath(rect: centerRect).fill()

        // Edge labels
        let labelFont = NSFont.systemFont(ofSize: 9, weight: .medium)
        let labelColor = NSColor.white.withAlphaComponent(0.5)
        let attrs: [NSAttributedString.Key: Any] = [.font: labelFont, .foregroundColor: labelColor]

        drawCentered("scrub", in: NSRect(x: 0, y: rect.height - inH, width: rect.width, height: inH), attrs: attrs)
        drawCentered("scroll", in: NSRect(x: 0, y: 0, width: rect.width, height: inH), attrs: attrs)
        drawCentered("vol", in: NSRect(x: 0, y: inH, width: inW, height: rect.height - 2 * inH), attrs: attrs)
        drawCentered("brt", in: NSRect(x: rect.width - inW, y: inH, width: inW, height: rect.height - 2 * inH), attrs: attrs)
    }

    private func drawCentered(_ text: String, in rect: NSRect, attrs: [NSAttributedString.Key: Any]) {
        let str = text as NSString
        let size = str.size(withAttributes: attrs)
        guard size.width < rect.width && size.height < rect.height else { return }
        let pt = NSPoint(
            x: rect.midX - size.width / 2,
            y: rect.midY - size.height / 2
        )
        str.draw(at: pt, withAttributes: attrs)
    }
}
