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

    private final class HeaderBarView: NSView {
        var onToggleMinimize: (() -> Void)?
        var onHideOverlay: (() -> Void)?
        var onDragBegan: ((NSEvent) -> Void)?
        var onDragChanged: ((NSEvent) -> Void)?
        var onDragEnded: (() -> Void)?

        private let closeButton = NSButton(frame: .zero)
        private let minimizeButton = NSButton(frame: .zero)
        private let titleLabel = NSTextField(labelWithString: "")
        private let separatorView = NSView(frame: .zero)

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            setup()
        }

        required init?(coder: NSCoder) { fatalError() }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            onDragBegan?(event)
        }

        override func mouseDragged(with event: NSEvent) {
            onDragChanged?(event)
        }

        override func mouseUp(with event: NSEvent) {
            onDragEnded?()
        }

        func updateTitle(_ title: String) {
            titleLabel.stringValue = title
        }

        func setMinimized(_ minimized: Bool) {
            minimizeButton.title = minimized ? "+" : "−"
            closeButton.isHidden = minimized
            titleLabel.isHidden = minimized
            separatorView.isHidden = minimized
            needsLayout = true
        }

        private func setup() {
            closeButton.title = "×"
            closeButton.font = NSFont.systemFont(ofSize: 18, weight: .regular)
            closeButton.isBordered = false
            closeButton.contentTintColor = .white
            closeButton.target = self
            closeButton.action = #selector(handleHideOverlay)
            closeButton.setButtonType(.momentaryChange)
            addSubview(closeButton)

            minimizeButton.font = NSFont.systemFont(ofSize: 18, weight: .regular)
            minimizeButton.isBordered = false
            minimizeButton.contentTintColor = .white
            minimizeButton.target = self
            minimizeButton.action = #selector(handleToggleMinimize)
            minimizeButton.setButtonType(.momentaryChange)
            addSubview(minimizeButton)

            titleLabel.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
            titleLabel.textColor = .white
            titleLabel.alignment = .center
            titleLabel.lineBreakMode = .byTruncatingTail
            addSubview(titleLabel)

            separatorView.wantsLayer = true
            separatorView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
            addSubview(separatorView)

            setMinimized(false)
        }

        override func layout() {
            super.layout()

            let buttonSize = CGSize(width: 24, height: 24)
            if closeButton.isHidden {
                minimizeButton.frame = NSRect(
                    x: bounds.midX - buttonSize.width / 2,
                    y: bounds.midY - buttonSize.height / 2,
                    width: buttonSize.width,
                    height: buttonSize.height
                )
            } else {
                closeButton.frame = NSRect(x: 10, y: bounds.midY - buttonSize.height / 2, width: buttonSize.width, height: buttonSize.height)
                minimizeButton.frame = NSRect(x: closeButton.frame.maxX + 8, y: bounds.midY - buttonSize.height / 2, width: buttonSize.width, height: buttonSize.height)
                titleLabel.frame = NSRect(x: 84, y: bounds.midY - 10, width: max(50, bounds.width - 168), height: 20)
                separatorView.frame = NSRect(x: 12, y: 0, width: bounds.width - 24, height: 1)
                separatorView.isHidden = bounds.height <= 32
            }
        }

        @objc private func handleToggleMinimize() {
            onToggleMinimize?()
        }

        @objc private func handleHideOverlay() {
            onHideOverlay?()
        }
    }

    private final class PadSurfaceView: NSView {
        var onDragBegan: ((NSEvent) -> Void)?
        var onDragChanged: ((NSEvent) -> Void)?
        var onDragEnded: (() -> Void)?

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

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

    static let headerHeight: CGFloat = 32
    static let contentGap: CGFloat = 0
    static let minimizedTileSize = CGSize(width: 56, height: headerHeight)

    static func windowSize(for profile: Profile, minimized: Bool) -> CGSize {
        if minimized { return minimizedTileSize }
        return CGSize(
            width: profile.padWidth,
            height: profile.padHeight + headerHeight + contentGap
        )
    }

    var onToggleMinimize: (() -> Void)?
    var onHideOverlay: (() -> Void)?

    private var buttonViews: [GamepadButton: GamepadButtonView] = [:]
    private let headerBar = HeaderBarView(frame: .zero)
    private let padSurface = PadSurfaceView(frame: .zero)
    private let blurView = PassthroughVisualEffectView(frame: .zero)
    private let resizeHandle = ResizeHandleView(frame: .zero)

    private var currentProfile: Profile
    private var isMinimized = false

    private var dragStartWindowOrigin: NSPoint = .zero
    private var dragStartLocationInScreen: NSPoint = .zero
    private var isDraggingWindow = false

    private var resizeStartFrame: NSRect = .zero
    private var resizeStartLocationInScreen: NSPoint = .zero
    private var isResizing = false

    private let resizeHandleSize = CGSize(width: 22, height: 22)
    private let minimumPadSize = CGSize(width: 260, height: 180)

    init(frame: NSRect, profile: Profile, minimized: Bool = false) {
        currentProfile = profile
        isMinimized = minimized
        super.init(frame: frame)
        setup()
        updateLayout()
        buildButtons(profile: profile)
        updateHeader()
    }

    required init?(coder: NSCoder) { fatalError() }

    func reload(profile: Profile, minimized: Bool) {
        currentProfile = profile
        isMinimized = minimized
        updateHeader()
        updateLayout()
        buildButtons(profile: profile)
    }

    func setMinimized(_ minimized: Bool) {
        isMinimized = minimized
        updateHeader()
        updateLayout()
        buildButtons(profile: currentProfile)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateLayout()
        buildButtons(profile: currentProfile)
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        layer?.cornerRadius = 20
        layer?.masksToBounds = true

        blurView.autoresizingMask = [.width, .height]
        blurView.material = .hudWindow
        blurView.blendingMode = .behindWindow
        blurView.state = .active
        addSubview(blurView, positioned: .below, relativeTo: nil)

        headerBar.onToggleMinimize = { [weak self] in
            self?.onToggleMinimize?()
        }
        headerBar.onHideOverlay = { [weak self] in
            self?.onHideOverlay?()
        }
        headerBar.onDragBegan = { [weak self] event in
            self?.beginWindowDrag(with: event)
        }
        headerBar.onDragChanged = { [weak self] event in
            self?.continueWindowDrag(with: event)
        }
        headerBar.onDragEnded = { [weak self] in
            self?.endWindowDrag()
        }
        addSubview(headerBar)

        padSurface.onDragBegan = { [weak self] event in
            self?.beginWindowDrag(with: event)
        }
        padSurface.onDragChanged = { [weak self] event in
            self?.continueWindowDrag(with: event)
        }
        padSurface.onDragEnded = { [weak self] in
            self?.endWindowDrag()
        }
        addSubview(padSurface)

        resizeHandle.onDragBegan = { [weak self] event in
            self?.beginResize(with: event)
        }
        resizeHandle.onDragChanged = { [weak self] event in
            self?.continueResize(with: event)
        }
        resizeHandle.onDragEnded = { [weak self] in
            self?.endResize()
        }
        padSurface.addSubview(resizeHandle)
    }

    private func updateHeader() {
        headerBar.updateTitle(currentProfile.name)
        headerBar.setMinimized(isMinimized)
    }

    private func updateLayout() {
        blurView.frame = bounds

        headerBar.frame = NSRect(
            x: 0,
            y: bounds.height - Self.headerHeight,
            width: bounds.width,
            height: Self.headerHeight
        )

        if isMinimized {
            padSurface.isHidden = true
            return
        }

        let padHeight = max(0, bounds.height - Self.headerHeight - Self.contentGap)
        padSurface.isHidden = false
        padSurface.frame = NSRect(x: 0, y: 0, width: bounds.width, height: padHeight)
        resizeHandle.frame = NSRect(
            x: padSurface.bounds.maxX - resizeHandleSize.width - 8,
            y: 8,
            width: resizeHandleSize.width,
            height: resizeHandleSize.height
        )
    }

    private func buildButtons(profile: Profile) {
        currentProfile = profile

        if isMinimized || padSurface.bounds.isEmpty {
            buttonViews.values.forEach { $0.removeFromSuperview() }
            buttonViews.removeAll()
            return
        }

        let activeButtons = Set(GamepadButton.allCases.filter {
            guard let cfg = profile.buttons[$0.rawValue] else { return false }
            return cfg.enabled
        })

        for button in buttonViews.keys where !activeButtons.contains(button) {
            buttonViews[button]?.removeFromSuperview()
            buttonViews.removeValue(forKey: button)
        }

        let width = padSurface.bounds.width
        let height = padSurface.bounds.height
        NSLog("[ContentView] buildButtons W=\(width) H=\(height) count=\(profile.buttons.count)")

        for button in GamepadButton.allCases {
            guard let cfg = profile.buttons[button.rawValue], cfg.enabled else { continue }
            let cx = CGFloat(cfg.x) * width
            let cy = CGFloat(cfg.y) * height
            let bw = CGFloat(cfg.width) * width
            let bh = CGFloat(cfg.height) * height
            let frame = CGRect(x: cx - bw / 2, y: cy - bh / 2, width: bw, height: bh)

            if let view = buttonViews[button] {
                view.updateConfig(cfg)
                view.frame = frame
            } else {
                let view = GamepadButtonView(button: button, config: cfg)
                view.frame = frame
                padSurface.addSubview(view, positioned: .below, relativeTo: resizeHandle)
                buttonViews[button] = view
            }
        }

        padSurface.addSubview(resizeHandle)
        NSLog("[ContentView] Built \(buttonViews.count) buttons")
    }

    private func beginWindowDrag(with event: NSEvent) {
        guard let window, !isResizing else { return }
        isDraggingWindow = true
        dragStartWindowOrigin = window.frame.origin
        dragStartLocationInScreen = window.convertPoint(toScreen: event.locationInWindow)
        NSLog("[ContentView] Window drag began at \(dragStartLocationInScreen)")
    }

    private func continueWindowDrag(with event: NSEvent) {
        guard isDraggingWindow, !isResizing, let window else { return }
        let currentLocationInScreen = window.convertPoint(toScreen: event.locationInWindow)
        let dx = currentLocationInScreen.x - dragStartLocationInScreen.x
        let dy = currentLocationInScreen.y - dragStartLocationInScreen.y
        let newOrigin = NSPoint(x: dragStartWindowOrigin.x + dx, y: dragStartWindowOrigin.y + dy)
        window.setFrameOrigin(newOrigin)
    }

    private func endWindowDrag() {
        guard isDraggingWindow else { return }
        isDraggingWindow = false
        NSLog("[ContentView] Window drag ended")
    }

    private func beginResize(with event: NSEvent) {
        guard !isMinimized, let window else { return }
        isResizing = true
        isDraggingWindow = false
        resizeStartFrame = window.frame
        resizeStartLocationInScreen = window.convertPoint(toScreen: event.locationInWindow)
        NSLog("[ContentView] Resize began at \(resizeStartLocationInScreen)")
    }

    private func continueResize(with event: NSEvent) {
        guard isResizing, let window else { return }

        let currentLocationInScreen = window.convertPoint(toScreen: event.locationInWindow)
        let dx = currentLocationInScreen.x - resizeStartLocationInScreen.x
        let dy = currentLocationInScreen.y - resizeStartLocationInScreen.y

        let maxSize = maximumResizablePadSize(for: window)
        let newPadWidth = min(max(resizeStartFrame.width + dx, minimumPadSize.width), maxSize.width)
        let newPadHeight = min(max((resizeStartFrame.height - Self.headerHeight - Self.contentGap) + dy, minimumPadSize.height), maxSize.height)
        let newWindowSize = CGSize(width: newPadWidth, height: newPadHeight + Self.headerHeight + Self.contentGap)
        let newFrame = NSRect(origin: resizeStartFrame.origin, size: newWindowSize)

        window.setFrame(newFrame, display: true)
        currentProfile.padWidth = newPadWidth
        currentProfile.padHeight = newPadHeight
    }

    private func endResize() {
        guard isResizing else { return }
        isResizing = false
        ProfileStore.shared.updateActiveProfileSize(width: currentProfile.padWidth, height: currentProfile.padHeight)
        NSLog("[ContentView] Resize ended")
    }

    private func maximumResizablePadSize(for window: NSWindow) -> CGSize {
        let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(origin: .zero, size: CGSize(width: 1440, height: 900))
        let maxWidth = max(minimumPadSize.width, visibleFrame.maxX - window.frame.minX - 12)
        let maxWindowHeight = max(Self.headerHeight + Self.contentGap + minimumPadSize.height, visibleFrame.maxY - window.frame.minY - 12)
        let maxPadHeight = max(minimumPadSize.height, maxWindowHeight - Self.headerHeight - Self.contentGap)
        return CGSize(width: maxWidth, height: maxPadHeight)
    }
}
