import Cocoa

final class GamepadContentView: NSView {

    private final class PassthroughVisualEffectView: NSVisualEffectView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    private final class HeaderBarView: NSView {
        var onToggleMinimize: (() -> Void)?
        var onHideOverlay: (() -> Void)?
        var menuProvider: (() -> NSMenu?)?
        var onDragBegan: ((NSEvent) -> Void)?
        var onDragChanged: ((NSEvent) -> Void)?
        var onDragEnded: (() -> Void)?

        private let closeButton = NSButton(frame: .zero)
        private let minimizeButton = NSButton(frame: .zero)
        private let menuButton = NSButton(frame: .zero)
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
            menuButton.isHidden = minimized
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

            if let menuImage = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "Menu") {
                menuButton.image = menuImage
                menuButton.imagePosition = .imageOnly
            } else {
                menuButton.title = "⋯"
            }
            menuButton.font = NSFont.systemFont(ofSize: 16, weight: .semibold)
            menuButton.isBordered = false
            menuButton.contentTintColor = .white
            menuButton.target = self
            menuButton.action = #selector(handleMenu)
            menuButton.setButtonType(.momentaryChange)
            addSubview(menuButton)

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
                menuButton.frame = NSRect(x: bounds.width - 34, y: bounds.midY - buttonSize.height / 2, width: buttonSize.width, height: buttonSize.height)
                titleLabel.frame = NSRect(x: 84, y: bounds.midY - 10, width: max(50, menuButton.frame.minX - 96), height: 20)
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

        @objc private func handleMenu() {
            guard let menu = menuProvider?() else { return }

            menu.popUp(
                positioning: nil,
                at: NSPoint(x: menuButton.frame.minX, y: menuButton.frame.minY - 6),
                in: self
            )
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
    static let minimumPadSize = CGSize(width: 260, height: 180)

    static func windowSize(for profile: Profile, minimized: Bool) -> CGSize {
        if minimized { return minimizedTileSize }
        return CGSize(
            width: profile.displayPadWidth,
            height: profile.displayPadHeight + headerHeight + contentGap
        )
    }

    var onToggleMinimize: (() -> Void)?
    var onHideOverlay: (() -> Void)?
    var menuProvider: (() -> NSMenu?)?
    var onJoystickCaptureChanged: ((Bool) -> Void)?

    private var buttonViews: [GamepadButton: GamepadButtonView] = [:]
    private let headerBar = HeaderBarView(frame: .zero)
    private let padSurface = PadSurfaceView(frame: .zero)
    private let blurView = PassthroughVisualEffectView(frame: .zero)

    private var currentProfile: Profile
    private var isMinimized = false
    private var capturedJoystickButton: GamepadButton?

    private var dragStartWindowOrigin: NSPoint = .zero
    private var dragStartLocationInScreen: NSPoint = .zero
    private var isDraggingWindow = false

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

    func releaseAllInputs() {
        releaseAllButtonsForRebuild()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateLayout()
        buildButtons(profile: currentProfile, releasesExistingInputs: false)
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
        headerBar.menuProvider = { [weak self] in
            self?.menuProvider?()
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
    }

    private func buildButtons(profile: Profile, releasesExistingInputs: Bool = true) {
        if releasesExistingInputs {
            releaseAllButtonsForRebuild()
        }
        currentProfile = profile

        if isMinimized || padSurface.bounds.isEmpty {
            buttonViews.values.forEach { $0.removeFromSuperview() }
            buttonViews.removeAll()
            capturedJoystickButton = nil
            return
        }

        let activeButtons = Set(profile.orderedButtonIDs.filter {
            guard let cfg = profile.buttons[$0.rawValue] else { return false }
            return cfg.enabled
        })

        for button in buttonViews.keys where !activeButtons.contains(button) {
            buttonViews[button]?.releaseIfNeeded()
            buttonViews[button]?.removeFromSuperview()
            buttonViews.removeValue(forKey: button)
        }

        let width = padSurface.bounds.width
        let height = padSurface.bounds.height
        debugLog("[ContentView] buildButtons W=\(width) H=\(height) count=\(profile.buttons.count)")

        for button in profile.orderedButtonIDs {
            guard let cfg = profile.buttons[button.rawValue], cfg.enabled else { continue }
            let rawWidth = CGFloat(cfg.width) * width
            let rawHeight = CGFloat(cfg.height) * height
            let minimumSize = ButtonSizing.minimumSize(for: cfg.type)
            let bw = min(width, max(rawWidth, CGFloat(minimumSize.width)))
            let bh = min(height, max(rawHeight, CGFloat(minimumSize.height)))
            let cx = min(max(CGFloat(cfg.x) * width, bw / 2), width - bw / 2)
            let cy = min(max(CGFloat(cfg.y) * height, bh / 2), height - bh / 2)
            let frame = CGRect(x: cx - bw / 2, y: cy - bh / 2, width: bw, height: bh)

            if let view = buttonViews[button] {
                view.frame = frame
                if releasesExistingInputs {
                    view.updateConfig(
                        cfg,
                        compatibilityModeEnabled: profile.compatibilityMode,
                        activeSubProfileID: profile.id
                    )
                }
            } else {
                let view = GamepadButtonView(
                    button: button,
                    config: cfg,
                    compatibilityModeEnabled: profile.compatibilityMode,
                    activeSubProfileID: profile.id
                )
                view.onJoystickCaptureChanged = { [weak self, weak view] captured in
                    guard let self, let view else {
                        return
                    }
                    self.setJoystickCapture(captured, for: view.button)
                }
                view.frame = frame
                padSurface.addSubview(view)
                buttonViews[button] = view
            }
        }
        updateButtonVisibilityForJoystickCapture()
        debugLog("[ContentView] Built \(buttonViews.count) buttons")
    }

    private func releaseAllButtonsForRebuild() {
        let hadJoystickCapture = capturedJoystickButton != nil
        buttonViews.values.forEach { $0.releaseIfNeeded() }
        capturedJoystickButton = nil
        updateButtonVisibilityForJoystickCapture()
        if hadJoystickCapture {
            onJoystickCaptureChanged?(false)
        }
    }

    private func setJoystickCapture(_ captured: Bool, for button: GamepadButton) {
        let wasCaptured = capturedJoystickButton != nil
        if captured {
            capturedJoystickButton = button
        } else if capturedJoystickButton == button {
            capturedJoystickButton = nil
        }

        updateButtonVisibilityForJoystickCapture()
        let isCaptured = capturedJoystickButton != nil
        if wasCaptured != isCaptured {
            onJoystickCaptureChanged?(isCaptured)
        }
    }

    private func updateButtonVisibilityForJoystickCapture() {
        for (button, view) in buttonViews {
            view.isHidden = capturedJoystickButton.map { $0 != button } ?? false
        }
    }

    private func beginWindowDrag(with event: NSEvent) {
        guard let window else { return }
        isDraggingWindow = true
        dragStartWindowOrigin = window.frame.origin
        dragStartLocationInScreen = window.convertPoint(toScreen: event.locationInWindow)
        debugLog("[ContentView] Window drag began at \(dragStartLocationInScreen)")
    }

    private func continueWindowDrag(with event: NSEvent) {
        guard isDraggingWindow, let window else { return }
        let currentLocationInScreen = window.convertPoint(toScreen: event.locationInWindow)
        let dx = currentLocationInScreen.x - dragStartLocationInScreen.x
        let dy = currentLocationInScreen.y - dragStartLocationInScreen.y
        let newOrigin = NSPoint(x: dragStartWindowOrigin.x + dx, y: dragStartWindowOrigin.y + dy)
        window.setFrameOrigin(newOrigin)
    }

    private func endWindowDrag() {
        guard isDraggingWindow else { return }
        isDraggingWindow = false
            debugLog("[ContentView] Window drag ended")
    }
}
