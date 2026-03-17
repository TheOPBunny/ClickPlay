import Cocoa

final class GamepadButtonView: NSView {

    let button: GamepadButton
    private let label = NSTextField(labelWithString: "")
    private var isPressed = false
    private var trackingArea: NSTrackingArea?

    // Colors
    private var baseColor: NSColor { colorForButton(button, pressed: false) }
    private var pressedColor: NSColor { colorForButton(button, pressed: true) }

    init(button: GamepadButton) {
        self.button = button
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Setup

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true

        label.stringValue = button.displayLabel
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
    }

    // MARK: - Touch/Mouse Handling

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
        setPressed(true)
    }

    override func mouseUp(with event: NSEvent) {
        setPressed(false)
    }

    override func mouseDragged(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        if inside != isPressed { setPressed(inside) }
    }

    override func mouseExited(with event: NSEvent) {
        if isPressed { setPressed(false) }
    }

    private func setPressed(_ pressed: Bool) {
        guard pressed != isPressed else { return }
        isPressed = pressed
        if pressed {
            KeyInjector.shared.press(button)
        } else {
            KeyInjector.shared.release(button)
        }
        updateAppearance(animated: true)
    }

    // MARK: - Appearance

    private func updateAppearance(animated: Bool) {
        let targetColor = isPressed ? pressedColor : baseColor
        let scale: CGFloat = isPressed ? 0.92 : 1.0

        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.05
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                layer?.backgroundColor = targetColor.cgColor
                let t = CATransform3DMakeScale(scale, scale, 1)
                layer?.transform = t
            }
        } else {
            layer?.backgroundColor = targetColor.cgColor
        }
    }

    private func colorForButton(_ btn: GamepadButton, pressed: Bool) -> NSColor {
        let alpha: CGFloat = pressed ? 0.95 : 0.75
        switch btn.color {
        case .red:    return NSColor(red: 0.90, green: 0.20, blue: 0.20, alpha: alpha)
        case .green:  return NSColor(red: 0.20, green: 0.78, blue: 0.35, alpha: alpha)
        case .blue:   return NSColor(red: 0.20, green: 0.50, blue: 0.95, alpha: alpha)
        case .yellow: return NSColor(red: 0.95, green: 0.78, blue: 0.10, alpha: alpha)
        case .gray:   return NSColor(white: 0.45, alpha: alpha)
        case .purple: return NSColor(red: 0.55, green: 0.25, blue: 0.85, alpha: alpha)
        case .dark:   return NSColor(white: 0.25, alpha: alpha)
        }
    }
}
