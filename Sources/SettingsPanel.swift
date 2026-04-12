// SettingsPanel.swift
//
// Custom NSView-based menu items for inline settings — no separate window.
// Sliders and trackpad preview live directly in the menu dropdown.

import AppKit

// MARK: - Slider row (label + slider in a menu item)

final class MenuSliderView: NSView {

    private let titleLabel = NSTextField(labelWithString: "")
    private let slider = NSSlider()
    var onValueChanged: ((Float) -> Void)?

    init(title: String, min: Float, max: Float, value: Float, menuWidth: CGFloat = 280) {
        super.init(frame: NSRect(x: 0, y: 0, width: menuWidth, height: 30))

        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.textColor = .labelColor
        titleLabel.isBezeled = false
        titleLabel.drawsBackground = false
        titleLabel.isEditable = false
        titleLabel.isSelectable = false
        titleLabel.frame = NSRect(x: 20, y: 5, width: 76, height: 20)
        addSubview(titleLabel)

        slider.minValue = Double(min)
        slider.maxValue = Double(max)
        slider.doubleValue = Double(value)
        slider.controlSize = .small
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(changed(_:))
        slider.frame = NSRect(x: 100, y: 7, width: menuWidth - 120, height: 16)
        addSubview(slider)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func changed(_ sender: NSSlider) {
        onValueChanged?(Float(sender.doubleValue))
    }
}

// MARK: - Edge zone slider (label + slider + percentage)

final class MenuEdgeSliderView: NSView {

    private let slider = NSSlider()
    private let pctLabel = NSTextField(labelWithString: "10%")
    var onValueChanged: ((Float) -> Void)?

    init(value: Float, menuWidth: CGFloat = 280) {
        super.init(frame: NSRect(x: 0, y: 0, width: menuWidth, height: 30))

        let title = NSTextField(labelWithString: "Width")
        title.font = .systemFont(ofSize: 13)
        title.textColor = .labelColor
        title.isBezeled = false
        title.drawsBackground = false
        title.isEditable = false
        title.isSelectable = false
        title.frame = NSRect(x: 20, y: 5, width: 50, height: 20)
        addSubview(title)

        slider.minValue = 5
        slider.maxValue = 25
        slider.doubleValue = Double(value * 100)
        slider.controlSize = .small
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(changed(_:))
        slider.frame = NSRect(x: 76, y: 7, width: menuWidth - 136, height: 16)
        addSubview(slider)

        pctLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        pctLabel.textColor = .secondaryLabelColor
        pctLabel.alignment = .right
        pctLabel.isBezeled = false
        pctLabel.drawsBackground = false
        pctLabel.isEditable = false
        pctLabel.isSelectable = false
        pctLabel.stringValue = "\(Int(value * 100))%"
        pctLabel.frame = NSRect(x: menuWidth - 56, y: 5, width: 40, height: 20)
        addSubview(pctLabel)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func changed(_ sender: NSSlider) {
        let pct = Float(sender.doubleValue) / 100.0
        pctLabel.stringValue = "\(Int(sender.doubleValue))%"
        onValueChanged?(pct)
    }
}

// MARK: - Section header

final class MenuSectionView: NSView {

    init(title: String, menuWidth: CGFloat = 280) {
        super.init(frame: NSRect(x: 0, y: 0, width: menuWidth, height: 22))

        let label = NSTextField(labelWithString: title.uppercased())
        label.font = .systemFont(ofSize: 10, weight: .semibold)
        label.textColor = .tertiaryLabelColor
        label.isBezeled = false
        label.drawsBackground = false
        label.isEditable = false
        label.isSelectable = false
        label.frame = NSRect(x: 20, y: 2, width: menuWidth - 40, height: 16)
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - Trackpad preview

final class TrackpadPreviewView: NSView {

    var edgeInset: CGFloat = 0.10 {
        didSet { needsDisplay = true }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let pad: CGFloat = 24
        let rect = NSRect(x: pad, y: 8, width: bounds.width - pad * 2, height: bounds.height - 16)

        // Trackpad body
        let body = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
        NSColor.white.withAlphaComponent(0.06).setFill()
        body.fill()
        NSColor.white.withAlphaComponent(0.12).setStroke()
        body.lineWidth = 1
        body.stroke()

        // Edge zones
        NSColor.systemBlue.withAlphaComponent(0.2).setFill()
        let inW = rect.width * edgeInset
        let inH = rect.height * edgeInset

        // Top
        NSBezierPath(rect: NSRect(x: rect.minX, y: rect.maxY - inH, width: rect.width, height: inH))
            .fill()
        // Bottom
        NSBezierPath(rect: NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: inH))
            .fill()
        // Left
        NSBezierPath(rect: NSRect(x: rect.minX, y: rect.minY + inH, width: inW, height: rect.height - 2 * inH))
            .fill()
        // Right
        NSBezierPath(rect: NSRect(x: rect.maxX - inW, y: rect.minY + inH, width: inW, height: rect.height - 2 * inH))
            .fill()

        // Labels
        let font = NSFont.systemFont(ofSize: 8, weight: .medium)
        let color = NSColor.white.withAlphaComponent(0.45)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]

        centered("scrub", in: NSRect(x: rect.minX, y: rect.maxY - inH, width: rect.width, height: inH), attrs: attrs)
        centered("scroll", in: NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: inH), attrs: attrs)
        if inW > 20 {
            centered("vol", in: NSRect(x: rect.minX, y: rect.minY + inH, width: inW, height: rect.height - 2 * inH), attrs: attrs)
            centered("brt", in: NSRect(x: rect.maxX - inW, y: rect.minY + inH, width: inW, height: rect.height - 2 * inH), attrs: attrs)
        }
    }

    private func centered(_ text: String, in r: NSRect, attrs: [NSAttributedString.Key: Any]) {
        let s = (text as NSString).size(withAttributes: attrs)
        guard s.width < r.width, s.height < r.height else { return }
        (text as NSString).draw(at: NSPoint(x: r.midX - s.width / 2, y: r.midY - s.height / 2), withAttributes: attrs)
    }
}
