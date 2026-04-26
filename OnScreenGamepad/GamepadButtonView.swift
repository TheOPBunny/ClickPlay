import Cocoa

final class GamepadButtonView: NSView {

    private final class CenteredLabelView: NSView {
        var stringValue = "" {
            didSet { needsDisplay = true }
        }
        var font: NSFont = .systemFont(ofSize: 11) {
            didSet { needsDisplay = true }
        }

        override var isFlipped: Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)

            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            let attributedLabel = NSAttributedString(
                string: stringValue,
                attributes: [
                    .font: font,
                    .foregroundColor: NSColor.white,
                    .paragraphStyle: paragraphStyle,
                ]
            )
            let measuredSize = attributedLabel.size()
            let drawRect = CGRect(
                x: 2,
                y: max(0, bounds.midY - ceil(measuredSize.height) / 2),
                width: max(0, bounds.width - 4),
                height: ceil(measuredSize.height)
            )
            attributedLabel.draw(in: drawRect)
        }
    }

    private static let compatibilityTapDuration: TimeInterval = 0.033

    let button: GamepadButton
    private var config: ButtonConfig
    private var compatibilityModeEnabled: Bool
    private var pressedBinding: (keyCode: CGKeyCode, modifiers: NSEvent.ModifierFlags)?
    private let shapeLayer = CAShapeLayer()
    private let label = CenteredLabelView(frame: .zero)
    private var isPressed = false
    private var trackingArea: NSTrackingArea?
    private var autoReleaseWorkItem: DispatchWorkItem?

    init(button: GamepadButton, config: ButtonConfig, compatibilityModeEnabled: Bool) {
        self.button = button
        self.config = config
        self.compatibilityModeEnabled = compatibilityModeEnabled
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        wantsLayer = true
        layer?.masksToBounds = false
        shapeLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        layer?.addSublayer(shapeLayer)

        label.stringValue = config.resolvedDisplayLabel
        label.font = config.resolvedLabelFont
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        updateAppearance(animated: false)
        NSLog("[Button \(button.rawValue)] Created frame will be set by parent, keyCode=\(config.keyCode)")
    }

    override func layout() {
        super.layout()
        updateShapePath()
    }

    func updateConfig(_ newConfig: ButtonConfig, compatibilityModeEnabled: Bool) {
        releaseIfNeeded()
        config = newConfig
        self.compatibilityModeEnabled = compatibilityModeEnabled
        label.stringValue = config.resolvedDisplayLabel
        label.font = config.resolvedLabelFont
        updateAppearance(animated: false)
    }

    func releaseIfNeeded() {
        autoReleaseWorkItem?.cancel()
        autoReleaseWorkItem = nil

        guard let pressedBinding else { return }

        KeyInjector.shared.releaseRaw(pressedBinding.keyCode, modifiers: pressedBinding.modifiers)
        self.pressedBinding = nil
        isPressed = false
        updateAppearance(animated: false)
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        NSLog("[Button \(button.rawValue)] acceptsFirstMouse called → true")
        return true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard containsAnyInteractivePointCandidate(point) else {
            return nil
        }

        return self
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }

    override func mouseDown(with event: NSEvent) {
        guard containsInteractivePoint(convert(event.locationInWindow, from: nil)) else {
            return
        }

        NSLog("[Button \(button.rawValue)] mouseDown ✓")
        handlePressStarted()
    }

    override func mouseUp(with event: NSEvent) {
        NSLog("[Button \(button.rawValue)] mouseUp ✓")
        handlePressEnded()
    }

    override func mouseDragged(with event: NSEvent) {
        guard !usesToggleHold, !usesCompatibilityTap else { return }
        let inside = containsInteractivePoint(convert(event.locationInWindow, from: nil))
        if inside != isPressed { setPressed(inside) }
    }

    override func mouseExited(with event: NSEvent) {
        NSLog("[Button \(button.rawValue)] mouseExited")
        guard !usesToggleHold, !usesCompatibilityTap else { return }
        if isPressed { setPressed(false) }
    }

    private var usesToggleHold: Bool {
        config.interactionMode == .toggleHold
    }

    private var usesCompatibilityTap: Bool {
        compatibilityModeEnabled && config.interactionMode == .momentary
    }

    private func handlePressStarted() {
        if usesToggleHold {
            setPressed(!isPressed)
            return
        }

        if usesCompatibilityTap {
            setPressed(true)
            scheduleCompatibilityRelease()
            return
        }

        setPressed(true)
    }

    private func handlePressEnded() {
        guard !usesToggleHold, !usesCompatibilityTap else { return }
        setPressed(false)
    }

    private func scheduleCompatibilityRelease() {
        autoReleaseWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.setPressed(false)
        }
        autoReleaseWorkItem = workItem

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.compatibilityTapDuration, execute: workItem)
    }

    private func setPressed(_ pressed: Bool) {
        guard pressed != isPressed else { return }
        isPressed = pressed
        let keyCode = CGKeyCode(config.keyCode)
        let modifiers = NSEvent.ModifierFlags(rawValue: UInt(config.keyModifiers))
        NSLog("[Button \(button.rawValue)] setPressed=\(pressed) keyCode=\(keyCode) modifiers=\(config.keyModifiers) mode=\(config.interactionMode.rawValue) compatibilityMode=\(compatibilityModeEnabled)")
        if pressed {
            pressedBinding = (keyCode: keyCode, modifiers: modifiers)
            KeyInjector.shared.pressRaw(keyCode, modifiers: modifiers)
        } else {
            let bindingToRelease = pressedBinding ?? (keyCode: keyCode, modifiers: modifiers)
            KeyInjector.shared.releaseRaw(bindingToRelease.keyCode, modifiers: bindingToRelease.modifiers)
            pressedBinding = nil
            autoReleaseWorkItem?.cancel()
            autoReleaseWorkItem = nil
        }
        updateAppearance(animated: true)
    }

    deinit {
        releaseIfNeeded()
    }

    private func updateAppearance(animated: Bool) {
        let base = NSColor(hex: config.colorHex)
        let target = isPressed ? base.withAlphaComponent(1.0) : base.withAlphaComponent(0.75)
        let scale: CGFloat = isPressed ? 0.92 : 1.0
        updateShapePath()
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.05
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                shapeLayer.fillColor = target.cgColor
                layer?.transform = CATransform3DMakeScale(scale, scale, 1)
            }
        } else {
            shapeLayer.fillColor = target.cgColor
            layer?.transform = CATransform3DMakeScale(scale, scale, 1)
        }
    }

    private func updateShapePath() {
        shapeLayer.frame = bounds
        shapeLayer.path = buttonPath(in: bounds)
    }

    private func buttonPath(in rect: CGRect) -> CGPath {
        switch config.shape {
        case .roundedRectangle:
            return CGPath(roundedRect: rect, cornerWidth: 8, cornerHeight: 8, transform: nil)
        case .oval:
            return CGPath(ellipseIn: rect, transform: nil)
        }
    }

    private func containsInteractivePoint(_ point: CGPoint) -> Bool {
        guard bounds.contains(point) else {
            return false
        }

        switch config.shape {
        case .roundedRectangle:
            return true
        case .oval:
            guard bounds.width > 0, bounds.height > 0 else {
                return false
            }

            let normalizedX = (point.x - bounds.midX) / (bounds.width / 2)
            let normalizedY = (point.y - bounds.midY) / (bounds.height / 2)
            return (normalizedX * normalizedX) + (normalizedY * normalizedY) <= 1
        }
    }

    private func containsAnyInteractivePointCandidate(_ point: CGPoint) -> Bool {
        if containsInteractivePoint(point) {
            return true
        }

        guard let superview else {
            return false
        }

        return containsInteractivePoint(convert(point, from: superview))
    }
}
