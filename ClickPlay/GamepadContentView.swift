import Cocoa

/// Hosts the translucent gamepad chrome, lays out profile buttons, and handles overlay dragging from empty space.
final class GamepadContentView: NSView {

    // These visual layers should never intercept clicks; real input belongs to buttons and drag surfaces.
    private final class PassthroughVisualEffectView: NSVisualEffectView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    private final class PassthroughView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    private final class PointerLocationView: NSView {
        private static let diameter: CGFloat = 26

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            isHidden = true
            layer?.backgroundColor = NSColor.clear.cgColor
            layer?.borderColor = NSColor.white.cgColor
            layer?.borderWidth = 2
            layer?.cornerRadius = Self.diameter / 2
        }

        required init?(coder: NSCoder) { fatalError() }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func updateStrokeColor(_ color: NSColor) {
            layer?.borderColor = color.cgColor
        }

        func show(centeredAt point: NSPoint) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            frame = NSRect(
                x: point.x - Self.diameter / 2,
                y: point.y - Self.diameter / 2,
                width: Self.diameter,
                height: Self.diameter
            )
            layer?.cornerRadius = Self.diameter / 2
            isHidden = false
            CATransaction.commit()
        }

        func hide() {
            guard !isHidden else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            isHidden = true
            CATransaction.commit()
        }
    }

    /// Header controls are separated from the pad surface so minimize/menu/hide interactions do not press buttons.
    private final class HeaderBarView: NSView {
        var onToggleMinimize: (() -> Void)?
        var onHideOverlay: (() -> Void)?
        var menuProvider: (() -> NSMenu?)?
        var onDragBegan: ((NSEvent) -> Void)?
        var onDragChanged: ((NSEvent) -> Void)?
        var onDragEnded: (() -> Void)?

        private var foregroundColor: NSColor = .white
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

        func updateForegroundColor(_ color: NSColor) {
            foregroundColor = color
            applyForegroundColor()
        }

        func setMinimized(_ minimized: Bool) {
            minimizeButton.title = minimized ? "+" : "−"
            closeButton.isHidden = minimized
            titleLabel.isHidden = minimized
            menuButton.isHidden = minimized
            separatorView.isHidden = minimized
            applyForegroundColor()
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

        private func applyForegroundColor() {
            closeButton.contentTintColor = foregroundColor
            minimizeButton.contentTintColor = foregroundColor
            menuButton.contentTintColor = foregroundColor
            titleLabel.textColor = foregroundColor
            separatorView.layer?.backgroundColor = foregroundColor.withAlphaComponent(0.12).cgColor

            applyTitleColor(to: closeButton)
            applyTitleColor(to: minimizeButton)
            if menuButton.image == nil {
                applyTitleColor(to: menuButton)
            }
        }

        private func applyTitleColor(to button: NSButton) {
            button.attributedTitle = NSAttributedString(
                string: button.title,
                attributes: [
                    .font: button.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize),
                    .foregroundColor: foregroundColor
                ]
            )
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
                let titleInset = max(minimizeButton.frame.maxX + 18, bounds.maxX - menuButton.frame.minX + 18)
                titleLabel.frame = NSRect(x: titleInset, y: bounds.midY - 10, width: max(50, bounds.width - (titleInset * 2)), height: 20)
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

    /// Empty background region that starts window dragging without making individual gamepad buttons draggable.
    private final class PadSurfaceView: NSView {
        var onDragBegan: ((NSEvent) -> Void)?
        var onDragChanged: ((NSEvent) -> Void)?
        var onDragEnded: (() -> Void)?

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard bounds.contains(point) else {
                return nil
            }

            for subview in subviews.reversed() where !subview.isHidden {
                let convertedPoint = subview.convert(point, from: self)
                if let hitView = subview.hitTest(convertedPoint) {
                    return hitView
                }
            }

            return self
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

    static let headerHeight: CGFloat = 32
    static let contentGap: CGFloat = 0
    static let minimizedTileSize = CGSize(width: 56, height: headerHeight)
    static let minimumPadSize = CGSize(width: 260, height: 180)

    // MARK: - Sizing

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
    var onDwellActionToggled: ((GamepadButton, DwellActionConfig) -> Bool)?

    private var buttonViews: [GamepadButton: GamepadButtonView] = [:]
    private let headerBar = HeaderBarView(frame: .zero)
    private let padSurface = PadSurfaceView(frame: .zero)
    private let blurView = PassthroughVisualEffectView(frame: .zero)
    private let backgroundTintView = PassthroughView(frame: .zero)
    private let pointerLocationView = PointerLocationView(frame: .zero)

    private var currentProfile: Profile
    private var isMinimized = false
    private var capturedJoystickButton: GamepadButton?
    private var activeDwellButton: GamepadButton?

    // Drag state is stored in screen coordinates so moving the overlay works across Spaces and displays.
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

    // MARK: - Profile Reloading

    func reload(profile: Profile, minimized: Bool) {
        currentProfile = profile
        isMinimized = minimized
        updateBackgroundColor()
        updatePointerLocationVisibility(atScreenPoint: NSEvent.mouseLocation)
        updateHeader()
        updateLayout()
        buildButtons(profile: profile)
    }

    func setMinimized(_ minimized: Bool) {
        isMinimized = minimized
        updatePointerLocationVisibility(atScreenPoint: NSEvent.mouseLocation)
        updateHeader()
        updateLayout()
        buildButtons(profile: currentProfile)
    }

    func releaseAllInputs() {
        releaseAllButtonsForRebuild()
    }

    func setActiveDwellButton(_ button: GamepadButton?) {
        activeDwellButton = button
        syncDwellActionActiveState()
    }

    func syncButtonHover(atScreenPoint screenPoint: NSPoint) {
        guard !isMinimized, !padSurface.isHidden, let window else {
            clearButtonHover()
            return
        }

        let windowPoint = window.convertPoint(fromScreen: screenPoint)
        let contentPoint = convert(windowPoint, from: nil)
        guard bounds.contains(contentPoint), padSurface.frame.contains(contentPoint) else {
            clearButtonHover()
            return
        }

        let padPoint = padSurface.convert(contentPoint, from: self)
        var hoveredView: GamepadButtonView?
        for button in currentProfile.orderedButtonIDs.reversed() {
            guard let view = buttonViews[button], !view.isHidden else {
                continue
            }

            let localPoint = view.convert(padPoint, from: padSurface)
            if view.syncPolledHover(at: localPoint) {
                hoveredView = view
                break
            }
        }

        for view in buttonViews.values {
            if hoveredView.map({ view === $0 }) ?? false {
                continue
            }

            view.clearPolledHover()
        }
    }

    func syncPointerLocation(atScreenPoint screenPoint: NSPoint) {
        updatePointerLocationVisibility(atScreenPoint: screenPoint)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateLayout()
        buildButtons(profile: currentProfile, releasesExistingInputs: false)
    }

    // MARK: - Setup and Layout

    private func setup() {
        wantsLayer = true
        updateBackgroundColor()
        layer?.cornerRadius = 12
        layer?.masksToBounds = true

        blurView.autoresizingMask = [.width, .height]
        blurView.material = .hudWindow
        blurView.blendingMode = .behindWindow
        blurView.state = .active
        addSubview(blurView, positioned: .below, relativeTo: nil)

        backgroundTintView.autoresizingMask = [.width, .height]
        backgroundTintView.wantsLayer = true
        addSubview(backgroundTintView, positioned: .above, relativeTo: blurView)

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

        addSubview(pointerLocationView)
    }

    private func updateHeader() {
        headerBar.updateTitle(currentProfile.name)
        headerBar.updateForegroundColor(headerForegroundColor())
        headerBar.setMinimized(isMinimized)
    }

    private func headerForegroundColor() -> NSColor {
        let backgroundColor = NSColor(hex: currentProfile.backgroundColorHex)
        guard let color = backgroundColor.usingColorSpace(.sRGB) else {
            return .white
        }

        let luminance = (0.2126 * color.redComponent) + (0.7152 * color.greenComponent) + (0.0722 * color.blueComponent)
        return luminance >= 0.82 ? .black : .white
    }

    private func updateBackgroundColor() {
        let color = NSColor(hex: currentProfile.backgroundColorHex)
        let frostedGlassIntensity = CGFloat(min(max(currentProfile.backgroundFrostedGlassIntensity, 0), 100)) / 100
        layer?.backgroundColor = color.cgColor
        blurView.isHidden = frostedGlassIntensity <= 0
        backgroundTintView.layer?.backgroundColor = color.withAlphaComponent(1 - frostedGlassIntensity).cgColor
        pointerLocationView.updateStrokeColor(headerForegroundColor())
    }

    private func updateLayout() {
        blurView.frame = bounds
        backgroundTintView.frame = bounds
        updatePointerLocationVisibility(atScreenPoint: NSEvent.mouseLocation)

        headerBar.frame = NSRect(
            x: 0,
            y: bounds.height - Self.headerHeight,
            width: bounds.width,
            height: Self.headerHeight
        )

        if isMinimized {
            padSurface.isHidden = true
            pointerLocationView.hide()
            return
        }

        let padHeight = max(0, bounds.height - Self.headerHeight - Self.contentGap)
        padSurface.isHidden = false
        padSurface.frame = NSRect(x: 0, y: 0, width: bounds.width, height: padHeight)
    }

    private func updatePointerLocationVisibility(atScreenPoint screenPoint: NSPoint) {
        guard currentProfile.showPointerLocation, !isMinimized, capturedJoystickButton == nil, let window else {
            pointerLocationView.hide()
            return
        }

        let windowPoint = window.convertPoint(fromScreen: screenPoint)
        let contentPoint = convert(windowPoint, from: nil)
        guard bounds.contains(contentPoint) else {
            pointerLocationView.hide()
            return
        }

        pointerLocationView.show(centeredAt: contentPoint)
    }

    // MARK: - Button Construction

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
            let buttonSize = displaySize(for: cfg, in: padSurface.bounds.size, profile: profile)
            let bw = buttonSize.width
            let bh = buttonSize.height
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
                view.setDwellActionActive(activeDwellButton == button)
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
                view.onDwellActionToggled = { [weak self] button, config in
                    self?.onDwellActionToggled?(button, config) ?? false
                }
                view.frame = frame
                view.setDwellActionActive(activeDwellButton == button)
                padSurface.addSubview(view)
                buttonViews[button] = view
            }
        }
        updateButtonVisibilityForJoystickCapture()
        syncDwellActionActiveState()
        debugLog("[ContentView] Built \(buttonViews.count) buttons")
    }

    private func displaySize(for config: ButtonConfig, in padSize: CGSize, profile: Profile) -> CGSize {
        let minimumSize = ButtonSizing.minimumSize(for: config.type)

        guard config.type == .joystick else {
            let rawWidth = CGFloat(config.width) * padSize.width
            let rawHeight = CGFloat(config.height) * padSize.height
            return CGSize(
                width: min(padSize.width, max(rawWidth, CGFloat(minimumSize.width))),
                height: min(padSize.height, max(rawHeight, CGFloat(minimumSize.height)))
            )
        }

        let baseWidthSource = config.editorWidth > 0
            ? config.editorWidth
            : config.width * max(profile.padWidth, 1)
        let baseHeightSource = config.editorHeight > 0
            ? config.editorHeight
            : config.height * max(profile.padHeight, 1)
        let baseWidth = max(1, baseWidthSource)
        let baseHeight = max(1, baseHeightSource)
        let scaleX = padSize.width / max(CGFloat(profile.padWidth), 1)
        let scaleY = padSize.height / max(CGFloat(profile.padHeight), 1)
        let authoredScale = min(scaleX, scaleY)
        let minimumScale = max(
            CGFloat(minimumSize.width) / CGFloat(baseWidth),
            CGFloat(minimumSize.height) / CGFloat(baseHeight)
        )
        let maximumScale = min(
            padSize.width / CGFloat(baseWidth),
            padSize.height / CGFloat(baseHeight)
        )
        let scale = min(max(authoredScale, minimumScale), maximumScale)

        return CGSize(
            width: CGFloat(baseWidth) * scale,
            height: CGFloat(baseHeight) * scale
        )
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

    private func clearButtonHover() {
        buttonViews.values.forEach { $0.clearPolledHover() }
    }

    private func syncDwellActionActiveState() {
        for (button, view) in buttonViews {
            view.setDwellActionActive(activeDwellButton == button)
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
        updatePointerLocationVisibility(atScreenPoint: NSEvent.mouseLocation)
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

    // MARK: - Window Dragging

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
