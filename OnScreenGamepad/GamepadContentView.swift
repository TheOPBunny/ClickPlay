import Cocoa

final class GamepadContentView: NSView {

    private var buttonViews: [GamepadButton: GamepadButtonView] = [:]

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

        let blur = NSVisualEffectView(frame: bounds)
        blur.autoresizingMask = [.width, .height]
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        addSubview(blur, positioned: .below, relativeTo: nil)

        // Drag gesture — fires alongside normal event delivery, doesn't swallow clicks
        let pan = NSPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delaysPrimaryMouseButtonEvents = false   // critical: don't delay subview mouseDown
        addGestureRecognizer(pan)
    }

    private var dragStartWindowOrigin: NSPoint = .zero
    private var dragStartLocation: NSPoint = .zero

    @objc private func handlePan(_ gr: NSPanGestureRecognizer) {
        // Only drag when the gesture started on empty background (not a button)
        if gr.state == .began {
            let pt = gr.location(in: self)
            let overButton = buttonViews.values.contains { $0.frame.contains(pt) }
            NSLog("[ContentView] Pan began at \(pt), overButton=\(overButton)")
            guard !overButton else {
                NSLog("[ContentView] Pan cancelled — started on button")
                gr.state = .cancelled
                return
            }
            dragStartWindowOrigin = window?.frame.origin ?? .zero
            dragStartLocation = gr.location(in: nil)  // in screen coords
        }
        if gr.state == .changed {
            let cur = gr.location(in: nil)
            let dx = cur.x - dragStartLocation.x
            let dy = cur.y - dragStartLocation.y
            let newOrigin = NSPoint(x: dragStartWindowOrigin.x + dx,
                                    y: dragStartWindowOrigin.y + dy)
            window?.setFrameOrigin(newOrigin)
            (window as? GamepadWindow)?.updatePillPosition()
        }
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
}
