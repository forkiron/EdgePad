// SettingsPanel.swift
//
// Custom NSView-based menu items — inline settings in the dropdown.

import AppKit

// MARK: - Slider row

final class MenuSliderView: NSView {

    private let slider = NSSlider()
    var onValueChanged: ((Float) -> Void)?

    init(title: String, min: Float, max: Float, value: Float,
         menuWidth: CGFloat = 280, darkBg: Bool = false) {
        super.init(frame: NSRect(x: 0, y: 0, width: menuWidth, height: 30))
        if darkBg {
            wantsLayer = true
            layer?.backgroundColor = NSColor.black.withAlphaComponent(0.18).cgColor
        }

        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13)
        label.textColor = darkBg ? .secondaryLabelColor : .labelColor
        label.isBezeled = false
        label.drawsBackground = false
        label.isEditable = false
        label.isSelectable = false
        label.frame = NSRect(x: darkBg ? 32 : 20, y: 5, width: 76, height: 20)
        addSubview(label)

        let sliderX: CGFloat = darkBg ? 110 : 100
        slider.minValue = Double(min)
        slider.maxValue = Double(max)
        slider.doubleValue = Double(value)
        slider.controlSize = .small
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(changed(_:))
        slider.frame = NSRect(x: sliderX, y: 7, width: menuWidth - sliderX - 16, height: 16)
        slider.trackFillColor = .systemBlue
        addSubview(slider)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func changed(_ sender: NSSlider) {
        onValueChanged?(Float(sender.doubleValue))
    }
}

// MARK: - Overall sensitivity with disclosure arrow

final class SensitivityHeaderView: NSView {

    private let slider = NSSlider()
    private let arrowLabel = NSTextField(labelWithString: "")
    var onValueChanged: ((Float) -> Void)?
    var onDisclosureTapped: (() -> Void)?
    var isExpanded = false {
        didSet { arrowLabel.stringValue = isExpanded ? "\u{25BE}" : "\u{25B8}" }
    }

    init(value: Float, expanded: Bool, menuWidth: CGFloat = 280) {
        super.init(frame: NSRect(x: 0, y: 0, width: menuWidth, height: 30))
        isExpanded = expanded

        let label = NSTextField(labelWithString: "Overall")
        label.font = .systemFont(ofSize: 13)
        label.textColor = .labelColor
        label.isBezeled = false
        label.drawsBackground = false
        label.isEditable = false
        label.isSelectable = false
        label.frame = NSRect(x: 20, y: 5, width: 60, height: 20)
        addSubview(label)

        slider.minValue = 0.3
        slider.maxValue = 2.5
        slider.doubleValue = Double(value)
        slider.controlSize = .small
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(sliderChanged(_:))
        slider.frame = NSRect(x: 86, y: 7, width: menuWidth - 126, height: 16)
        slider.trackFillColor = .systemBlue
        addSubview(slider)

        // Disclosure arrow button
        arrowLabel.stringValue = expanded ? "\u{25BE}" : "\u{25B8}"
        arrowLabel.font = .systemFont(ofSize: 11)
        arrowLabel.textColor = .tertiaryLabelColor
        arrowLabel.alignment = .center
        arrowLabel.isBezeled = false
        arrowLabel.drawsBackground = false
        arrowLabel.isEditable = false
        arrowLabel.isSelectable = false
        arrowLabel.frame = NSRect(x: menuWidth - 28, y: 5, width: 20, height: 20)
        addSubview(arrowLabel)

        let clickArea = NSButton(frame: NSRect(x: menuWidth - 36, y: 0, width: 36, height: 30))
        clickArea.title = ""
        clickArea.isBordered = false
        clickArea.isTransparent = true
        clickArea.target = self
        clickArea.action = #selector(arrowTapped)
        addSubview(clickArea)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func sliderChanged(_ sender: NSSlider) {
        onValueChanged?(Float(sender.doubleValue))
    }

    @objc private func arrowTapped() {
        onDisclosureTapped?()
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
        slider.trackFillColor = .systemBlue
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

// MARK: - Profile row (custom view so clicking doesn't close menu)

final class ProfileItemView: NSView {

    private let checkmark = NSTextField(labelWithString: "")
    var onSelected: (() -> Void)?

    init(title: String, symbolName: String, isActive: Bool, menuWidth: CGFloat = 280) {
        super.init(frame: NSRect(x: 0, y: 0, width: menuWidth, height: 28))

        // Checkmark
        checkmark.stringValue = isActive ? "\u{2713}" : ""
        checkmark.font = .systemFont(ofSize: 13, weight: .medium)
        checkmark.textColor = .labelColor
        checkmark.isBezeled = false
        checkmark.drawsBackground = false
        checkmark.isEditable = false
        checkmark.isSelectable = false
        checkmark.frame = NSRect(x: 8, y: 4, width: 16, height: 20)
        addSubview(checkmark)

        // Icon
        if let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: title) {
            let iv = NSImageView(frame: NSRect(x: 28, y: 4, width: 18, height: 18))
            iv.image = img
            iv.contentTintColor = .secondaryLabelColor
            addSubview(iv)
        }

        // Label
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13)
        label.textColor = .labelColor
        label.isBezeled = false
        label.drawsBackground = false
        label.isEditable = false
        label.isSelectable = false
        label.frame = NSRect(x: 52, y: 4, width: menuWidth - 68, height: 20)
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseUp(with event: NSEvent) {
        // Highlight briefly
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.1).cgColor
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.layer?.backgroundColor = nil
        }
        onSelected?()
    }

    func setActive(_ active: Bool) {
        checkmark.stringValue = active ? "\u{2713}" : ""
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

        let body = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
        NSColor.white.withAlphaComponent(0.06).setFill()
        body.fill()
        NSColor.white.withAlphaComponent(0.12).setStroke()
        body.lineWidth = 1
        body.stroke()

        NSColor.controlAccentColor.withAlphaComponent(0.2).setFill()
        let inW = rect.width * edgeInset
        let inH = rect.height * edgeInset

        NSBezierPath(rect: NSRect(x: rect.minX, y: rect.maxY - inH, width: rect.width, height: inH)).fill()
        NSBezierPath(rect: NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: inH)).fill()
        NSBezierPath(rect: NSRect(x: rect.minX, y: rect.minY + inH, width: inW, height: rect.height - 2 * inH)).fill()
        NSBezierPath(rect: NSRect(x: rect.maxX - inW, y: rect.minY + inH, width: inW, height: rect.height - 2 * inH)).fill()

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
