// SettingsPanel.swift — Custom NSView menu items.

import AppKit

// MARK: - Slider row

final class MenuSliderView: NSView {

    private let slider = NSSlider()
    var onValueChanged: ((Float) -> Void)?

    init(title: String, min: Float, max: Float, value: Float,
         menuWidth: CGFloat = 280, indent: Bool = false, showArrow: Bool = false) {
        super.init(frame: NSRect(x: 0, y: 0, width: menuWidth, height: 28))

        let labelX: CGFloat = indent ? 32 : 20
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: indent ? 12 : 13)
        label.textColor = indent ? .secondaryLabelColor : .labelColor
        label.isBezeled = false
        label.drawsBackground = false
        label.isEditable = false
        label.isSelectable = false
        label.frame = NSRect(x: labelX, y: 4, width: 76, height: 20)
        addSubview(label)

        let rightPad: CGFloat = showArrow ? 28 : 16
        let sliderX: CGFloat = indent ? 112 : 100
        slider.minValue = Double(min)
        slider.maxValue = Double(max)
        slider.doubleValue = Double(value)
        slider.controlSize = .small
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(changed(_:))
        slider.frame = NSRect(x: sliderX, y: 6, width: menuWidth - sliderX - rightPad, height: 16)
        slider.trackFillColor = .systemBlue
        addSubview(slider)

        if showArrow {
            let arrow = NSTextField(labelWithString: "\u{25B8}")
            arrow.font = .systemFont(ofSize: 10)
            arrow.textColor = .tertiaryLabelColor
            arrow.isBezeled = false
            arrow.drawsBackground = false
            arrow.isEditable = false
            arrow.isSelectable = false
            arrow.frame = NSRect(x: menuWidth - 20, y: 6, width: 14, height: 16)
            addSubview(arrow)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func changed(_ sender: NSSlider) {
        onValueChanged?(Float(sender.doubleValue))
    }
}

// MARK: - Sensitivity row with chevron dropdown (like AirPods Max)

final class SensitivityDropdownView: NSView {

    private let slider = NSSlider()
    private let chevronBg = NSView()
    private let chevronImage = NSImageView()
    private let hoverBg = NSView()
    var onValueChanged: ((Float) -> Void)?
    var onChevronTapped: (() -> Void)?
    private var isExpanded: Bool
    private var trackingArea: NSTrackingArea?

    init(value: Float, expanded: Bool, menuWidth: CGFloat = 280) {
        isExpanded = expanded
        super.init(frame: NSRect(x: 0, y: 0, width: menuWidth, height: 32))

        // Hover bg
        hoverBg.frame = NSRect(x: 4, y: 2, width: menuWidth - 8, height: 28)
        hoverBg.wantsLayer = true
        hoverBg.layer?.cornerRadius = 5
        addSubview(hoverBg)

        // Slider centered, no label
        slider.minValue = 0.3
        slider.maxValue = 2.5
        slider.doubleValue = Double(value)
        slider.controlSize = .regular
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(sliderChanged(_:))
        slider.frame = NSRect(x: 16, y: 6, width: menuWidth - 62, height: 20)
        slider.trackFillColor = .systemBlue
        addSubview(slider)

        // Chevron circle
        let sz: CGFloat = 22
        let cx = menuWidth - sz - 10
        let cy = (32 - sz) / 2
        chevronBg.frame = NSRect(x: cx, y: cy, width: sz, height: sz)
        chevronBg.wantsLayer = true
        chevronBg.layer?.cornerRadius = sz / 2
        chevronBg.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.1).cgColor
        addSubview(chevronBg)

        // SF Symbol chevron
        let symbolName = expanded ? "chevron.up" : "chevron.down"
        let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
        chevronImage.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        chevronImage.contentTintColor = .secondaryLabelColor
        chevronImage.frame = NSRect(x: cx + 4, y: cy + 4, width: sz - 8, height: sz - 8)
        addSubview(chevronImage)
    }

    required init?(coder: NSCoder) { fatalError() }

    func setExpanded(_ expanded: Bool) {
        isExpanded = expanded
        let name = expanded ? "chevron.up" : "chevron.down"
        let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            chevronImage.animator().image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(config)
        }
    }

    override func updateTrackingAreas() {
        if let ta = trackingArea { removeTrackingArea(ta) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        hoverBg.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
        chevronBg.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.18).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        hoverBg.layer?.backgroundColor = nil
        chevronBg.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.1).cgColor
    }

    override func mouseUp(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        if loc.x > bounds.width - 44 {
            onChevronTapped?()
        }
    }

    @objc private func sliderChanged(_ sender: NSSlider) {
        onValueChanged?(Float(sender.doubleValue))
    }
}

// MARK: - Edge zone slider

final class MenuEdgeSliderView: NSView {

    private let slider = NSSlider()
    private let pctLabel = NSTextField(labelWithString: "10%")
    var onValueChanged: ((Float) -> Void)?

    init(value: Float, menuWidth: CGFloat = 280) {
        super.init(frame: NSRect(x: 0, y: 0, width: menuWidth, height: 28))

        slider.minValue = 5
        slider.maxValue = 25
        slider.doubleValue = Double(value * 100)
        slider.controlSize = .regular
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(changed(_:))
        slider.frame = NSRect(x: 16, y: 5, width: menuWidth - 72, height: 18)
        slider.trackFillColor = .systemBlue
        addSubview(slider)

        pctLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        pctLabel.textColor = .secondaryLabelColor
        pctLabel.alignment = .right
        pctLabel.isBezeled = false
        pctLabel.drawsBackground = false
        pctLabel.isEditable = false
        pctLabel.isSelectable = false
        pctLabel.stringValue = "\(Int(value * 100))%"
        pctLabel.frame = NSRect(x: menuWidth - 52, y: 5, width: 36, height: 18)
        addSubview(pctLabel)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func changed(_ sender: NSSlider) {
        let pct = Float(sender.doubleValue) / 100.0
        pctLabel.stringValue = "\(Int(sender.doubleValue))%"
        onValueChanged?(pct)
    }
}

// MARK: - Profile row (hover + animated checkmark)

final class ProfileItemView: NSView {

    private let checkContainer = NSView()
    private let hoverBg = NSView()
    var onSelected: (() -> Void)?
    private var trackingArea: NSTrackingArea?

    init(title: String, symbolName: String, isActive: Bool, menuWidth: CGFloat = 280) {
        super.init(frame: NSRect(x: 0, y: 0, width: menuWidth, height: 28))

        // Hover bg
        hoverBg.frame = NSRect(x: 4, y: 1, width: menuWidth - 8, height: 26)
        hoverBg.wantsLayer = true
        hoverBg.layer?.cornerRadius = 4
        addSubview(hoverBg)

        // Checkmark (clipped container for left-to-right reveal)
        checkContainer.frame = NSRect(x: 10, y: 0, width: isActive ? 18 : 0, height: 28)
        checkContainer.wantsLayer = true
        checkContainer.layer?.masksToBounds = true
        addSubview(checkContainer)

        let check = NSTextField(labelWithString: "\u{2713}")
        check.font = .systemFont(ofSize: 14, weight: .semibold)
        check.textColor = .labelColor
        check.isBezeled = false
        check.drawsBackground = false
        check.isEditable = false
        check.isSelectable = false
        check.frame = NSRect(x: 0, y: 5, width: 18, height: 18)
        checkContainer.addSubview(check)

        // Icon
        let iconX: CGFloat = 30
        if let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: title) {
            let iv = NSImageView(frame: NSRect(x: iconX, y: 6, width: 16, height: 16))
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
        label.frame = NSRect(x: iconX + 22, y: 5, width: menuWidth - iconX - 38, height: 18)
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        if let ta = trackingArea { removeTrackingArea(ta) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        hoverBg.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        hoverBg.layer?.backgroundColor = nil
    }

    override func mouseUp(with event: NSEvent) {
        onSelected?()
    }

    func setActive(_ active: Bool) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            checkContainer.animator().frame = NSRect(
                x: 10, y: 0, width: active ? 18 : 0, height: 28
            )
        }
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

    var edgeInset: CGFloat = 0.10 { didSet { needsDisplay = true } }

    override init(frame: NSRect) { super.init(frame: frame) }
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

        NSColor.systemBlue.withAlphaComponent(0.18).setFill()
        let inW = rect.width * edgeInset
        let inH = rect.height * edgeInset

        NSBezierPath(rect: NSRect(x: rect.minX, y: rect.maxY - inH, width: rect.width, height: inH)).fill()
        NSBezierPath(rect: NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: inH)).fill()
        NSBezierPath(rect: NSRect(x: rect.minX, y: rect.minY + inH, width: inW, height: rect.height - 2 * inH)).fill()
        NSBezierPath(rect: NSRect(x: rect.maxX - inW, y: rect.minY + inH, width: inW, height: rect.height - 2 * inH)).fill()

        let font = NSFont.systemFont(ofSize: 8, weight: .medium)
        let color = NSColor.white.withAlphaComponent(0.4)
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
