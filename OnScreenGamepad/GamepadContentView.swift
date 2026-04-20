import Cocoa

final class GamepadContentView: NSView {

    private final class PassthroughVisualEffectView: NSVisualEffectView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    private var buttonViews: [GamepadButton: GamepadButtonView] = [:]
    private var dragStartWindowOrigin: NSPoint = .zero
    private var dragStartLocationInScreen: NSPoint = .zero
    private var isDraggingBackground = false

    init(frame: NSRect, profile: Profile) {
        super.init(frame: frame)
        setup()
        buildButtons(profile: profile)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        layer?.cornerRadius = 20
        layer?.masksToBounds = true

        let blur = PassthroughVisualEffectView(frame: bounds)
        blur.autoresizingMask = [.width, .height]
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        addSubview(blur, positioned: .below, relativeTo: nil)
    }

    private func buildButtons(profile: Profile) {
        buttonViews.values.forEach { $0.removeFromSuperview() }
        buttonViews.removeAll()

        let W = bounds.width
        let H = bounds.height
        NSLog("[ContentView] buildButtons W=\(W) H=\(H) count=\(profile.buttons.count)")

        for btn in GamepadButton.allCases {
            guard let cfg = profile.buttons[btn.rawValue], cfg.enabled else { continue }
            let cx = CGFloat(cfg.x) * W
            let cy = CGFloat(cfg.y) * H
            let bw = CGFloat(cfg.width) * W
            let bh = CGFloat(cfg.height) * H
            let frame = CGRect(x: cx - bw/2, y: cy - bh/2, width: bw, height: bh)
            let view = GamepadButtonView(button: btn, config: cfg)
            view.frame = frame
            addSubview(view)
            buttonViews[btn] = view
        }
        NSLog("[ContentView] Built \(buttonViews.count) buttons")
    }

    func reload(profile: Profile) {
        let newSize = CGSize(width: profile.padWidth, height: profile.padHeight)
        if newSize != bounds.size { setFrameSize(newSize) }
        buildButtons(profile: profile)
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        isDraggingBackground = true
        dragStartWindowOrigin = window.frame.origin
        dragStartLocationInScreen = window.convertPoint(toScreen: event.locationInWindow)
        NSLog("[ContentView] Background drag began at \(dragStartLocationInScreen)")
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDraggingBackground, let window else { return }
        let currentLocationInScreen = window.convertPoint(toScreen: event.locationInWindow)
        let dx = currentLocationInScreen.x - dragStartLocationInScreen.x
        let dy = currentLocationInScreen.y - dragStartLocationInScreen.y
        let newOrigin = NSPoint(x: dragStartWindowOrigin.x + dx, y: dragStartWindowOrigin.y + dy)
        window.setFrameOrigin(newOrigin)
        (window as? GamepadWindow)?.updatePillPosition()
    }

    override func mouseUp(with event: NSEvent) {
        guard isDraggingBackground else { return }
        isDraggingBackground = false
        NSLog("[ContentView] Background drag ended")
    }
}
