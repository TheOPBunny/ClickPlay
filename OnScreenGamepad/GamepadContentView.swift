import Cocoa

final class GamepadContentView: NSView {

    private final class PassthroughVisualEffectView: NSVisualEffectView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    private final class ResizeHandleView: NSView {
        var onDragBegan: ((NSEvent) -> Void)?
        var onDragChanged: ((NSEvent) -> Void)?
        var onDragEnded: (() -> Void)?

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .crosshair)
        }

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)

            NSColor.white.withAlphaComponent(0.6).setStroke()
            let path = NSBezierPath()
            let inset: CGFloat = 4
            for offset in [0, 5, 10] {
                path.move(to: NSPoint(x: bounds.maxX - inset - CGFloat(offset), y: bounds.minY + inset))
                path.line(to: NSPoint(x: bounds.maxX - inset, y: bounds.minY + inset + CGFloat(offset)))
            }
            path.lineWidth = 1.5
            path.stroke()
        }

        override func mouseDown(with event: NSEvent) {
            onDragBegan?(event)
        }

        override func mouseDragged(with event: NSEvent) {
            onDragChanged?(event)
        }

        override func mouseUp(with event: NSEvent) {
            onDragEnded?()
        }
    }

    private var buttonViews: [GamepadButton: GamepadButtonView] = [:]
    private let resizeHandle = ResizeHandleView(frame: .zero)
    private var currentProfile: Profile
    private var dragStartWindowOrigin: NSPoint = .zero
    private var dragStartLocationInScreen: NSPoint = .zero
    private var isDraggingBackground = false
    private var resizeStartFrame: NSRect = .zero
    private var resizeStartLocationInScreen: NSPoint = .zero
    private var isResizing = false

    private let resizeHandleSize = CGSize(width: 22, height: 22)
    private let minimumPadSize = CGSize(width: 260, height: 180)

    init(frame: NSRect, profile: Profile) {
        currentProfile = profile
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

        resizeHandle.wantsLayer = true
        resizeHandle.onDragBegan = { [weak self] event in
            self?.beginResize(with: event)
        }
        resizeHandle.onDragChanged = { [weak self] event in
            self?.continueResize(with: event)
        }
        resizeHandle.onDragEnded = { [weak self] in
            self?.endResize()
        }
        addSubview(resizeHandle)
        updateResizeHandleFrame()
    }

    private func buildButtons(profile: Profile) {
        currentProfile = profile

        let activeButtons = Set(GamepadButton.allCases.filter {
            guard let cfg = profile.buttons[$0.rawValue] else { return false }
            return cfg.enabled
        })

        for button in buttonViews.keys where !activeButtons.contains(button) {
            buttonViews[button]?.removeFromSuperview()
            buttonViews.removeValue(forKey: button)
        }

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
            if let view = buttonViews[btn] {
                view.updateConfig(cfg)
                view.frame = frame
            } else {
                let view = GamepadButtonView(button: btn, config: cfg)
                view.frame = frame
                addSubview(view, positioned: .below, relativeTo: resizeHandle)
                buttonViews[btn] = view
            }
        }

        updateResizeHandleFrame()
        NSLog("[ContentView] Built \(buttonViews.count) buttons")
    }

    func reload(profile: Profile) {
        currentProfile = profile
        let newSize = CGSize(width: profile.padWidth, height: profile.padHeight)
        if newSize != bounds.size { setFrameSize(newSize) }
        buildButtons(profile: profile)
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let window, !isResizing else { return }
        isDraggingBackground = true
        dragStartWindowOrigin = window.frame.origin
        dragStartLocationInScreen = window.convertPoint(toScreen: event.locationInWindow)
        NSLog("[ContentView] Background drag began at \(dragStartLocationInScreen)")
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDraggingBackground, !isResizing, let window else { return }
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

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateResizeHandleFrame()
        buildButtons(profile: currentProfile)
    }

    private func updateResizeHandleFrame() {
        resizeHandle.frame = NSRect(
            x: bounds.maxX - resizeHandleSize.width - 8,
            y: 8,
            width: resizeHandleSize.width,
            height: resizeHandleSize.height
        )
    }

    private func beginResize(with event: NSEvent) {
        guard let window else { return }
        isResizing = true
        isDraggingBackground = false
        resizeStartFrame = window.frame
        resizeStartLocationInScreen = window.convertPoint(toScreen: event.locationInWindow)
        NSLog("[ContentView] Resize began at \(resizeStartLocationInScreen)")
    }

    private func continueResize(with event: NSEvent) {
        guard isResizing, let window else { return }

        let currentLocationInScreen = window.convertPoint(toScreen: event.locationInWindow)
        let dx = currentLocationInScreen.x - resizeStartLocationInScreen.x
        let dy = currentLocationInScreen.y - resizeStartLocationInScreen.y

        let maxSize = maximumResizableContentSize(for: window)
        let newWidth = min(max(resizeStartFrame.width + dx, minimumPadSize.width), maxSize.width)
        let newHeight = min(max(resizeStartFrame.height + dy, minimumPadSize.height), maxSize.height)
        let newFrame = NSRect(origin: resizeStartFrame.origin, size: CGSize(width: newWidth, height: newHeight))

        window.setFrame(newFrame, display: true)
        currentProfile.padWidth = newWidth
        currentProfile.padHeight = newHeight
        (window as? GamepadWindow)?.updatePillPosition()
    }

    private func endResize() {
        guard isResizing else { return }
        isResizing = false
        ProfileStore.shared.updateActiveProfileSize(width: currentProfile.padWidth, height: currentProfile.padHeight)
        NSLog("[ContentView] Resize ended")
    }

    private func maximumResizableContentSize(for window: NSWindow) -> CGSize {
        let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(origin: .zero, size: CGSize(width: 1440, height: 900))
        let maxWidth = max(minimumPadSize.width, visibleFrame.maxX - window.frame.minX - 12)
        let maxHeight = max(minimumPadSize.height, visibleFrame.maxY - window.frame.minY - 36)
        return CGSize(width: maxWidth, height: maxHeight)
    }
}
