import Cocoa

final class GamepadButtonView: NSView {

    let button: GamepadButton
    private var config: ButtonConfig
    private let label = NSTextField(labelWithString: "")
    private var isPressed = false
    private var trackingArea: NSTrackingArea?

    init(button: GamepadButton, config: ButtonConfig) {
        self.button = button
        self.config = config
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true

        label.stringValue = config.label
        label.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        label.textColor = .white
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -4)
        ])

        updateAppearance(animated: false)
        NSLog("[Button \(button.rawValue)] Created frame will be set by parent, keyCode=\(config.keyCode)")
    }

    func updateConfig(_ newConfig: ButtonConfig) {
        config = newConfig
        label.stringValue = config.label
        updateAppearance(animated: false)
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        NSLog("[Button \(button.rawValue)] acceptsFirstMouse called → true")
        return true
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
        NSLog("[Button \(button.rawValue)] mouseDown ✓")
        setPressed(true)
    }

    override func mouseUp(with event: NSEvent) {
        NSLog("[Button \(button.rawValue)] mouseUp ✓")
        setPressed(false)
    }

    override func mouseDragged(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        if inside != isPressed { setPressed(inside) }
    }

    override func mouseExited(with event: NSEvent) {
        NSLog("[Button \(button.rawValue)] mouseExited")
        if isPressed { setPressed(false) }
    }

    private func setPressed(_ pressed: Bool) {
        guard pressed != isPressed else { return }
        isPressed = pressed
        let keyCode = CGKeyCode(config.keyCode)
        NSLog("[Button \(button.rawValue)] setPressed=\(pressed) keyCode=\(keyCode)")
        if pressed {
            KeyInjector.shared.pressRaw(keyCode)
        } else {
            KeyInjector.shared.releaseRaw(keyCode)
        }
        updateAppearance(animated: true)
    }

    private func updateAppearance(animated: Bool) {
        let base = NSColor(hex: config.colorHex)
        let target = isPressed ? base.withAlphaComponent(1.0) : base.withAlphaComponent(0.75)
        let scale: CGFloat = isPressed ? 0.92 : 1.0
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.05
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                layer?.backgroundColor = target.cgColor
                layer?.transform = CATransform3DMakeScale(scale, scale, 1)
            }
        } else {
            layer?.backgroundColor = target.cgColor
        }
    }
}

// NSTextField doesn't have isUserInteractionEnabled in AppKit — remove that line,
// it's UIKit only. The label won't intercept clicks because NSTextField with
// isEditable=false and isBordered=false doesn't install a tracking area.
