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

    private final class JoystickCaptureHUDView: NSView {
        private static let labelHeight: CGFloat = 18
        private static let horizontalPadding: CGFloat = 6
        private static let rowHeight: CGFloat = 20

        private var state: JoystickCaptureHUDState?
        private var joystickFrame: NSRect = .zero
        private var foregroundColor: NSColor = .white

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer?.backgroundColor = NSColor.clear.cgColor
            isHidden = true
        }

        required init?(coder: NSCoder) { fatalError() }

        override var isOpaque: Bool { false }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func update(state: JoystickCaptureHUDState?, joystickFrame: NSRect, foregroundColor: NSColor) {
            self.state = state
            self.joystickFrame = joystickFrame
            self.foregroundColor = foregroundColor
            isHidden = state == nil
            needsDisplay = true
        }

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            guard let state else { return }

            drawLayerText(state.layerText)
            drawAxisLabels(state)
            drawMappingRows(state.rows)
        }

        private func drawLayerText(_ text: String) {
            let width = min(max(90, bounds.width * 0.42), 180)
            let rect = NSRect(
                x: bounds.midX - width / 2,
                y: max(4, bounds.maxY - Self.labelHeight - 4),
                width: width,
                height: Self.labelHeight
            )
            drawText(text, in: rect, alignment: .center, isActive: false, color: foregroundColor)
        }

        private func drawAxisLabels(_ state: JoystickCaptureHUDState) {
            let mappingFrame = mappingRowsFrame(forCount: state.rows.count)
            let labelWidth = min(max(54, joystickFrame.width * 0.9), 96)
            let labelHeight = Self.labelHeight
            let gap: CGFloat = 7
            let upRect = NSRect(
                x: clampedX(joystickFrame.midX - labelWidth / 2, width: labelWidth),
                y: min(bounds.maxY - (labelHeight * 2) - 6, joystickFrame.maxY + gap),
                width: labelWidth,
                height: labelHeight
            )
            let downRect = NSRect(
                x: clampedX(joystickFrame.midX - labelWidth / 2, width: labelWidth),
                y: max(4, joystickFrame.minY - labelHeight - gap),
                width: labelWidth,
                height: labelHeight
            )
            let sideWidth = min(max(58, bounds.width * 0.22), 110)
            let sideY = min(max(4, joystickFrame.midY - labelHeight / 2), bounds.maxY - labelHeight - 4)
            let leftMinX = min(mappingFrame.maxX + 6, max(bounds.minX + 4, joystickFrame.minX - 42))
            let leftWidth = max(36, min(sideWidth, joystickFrame.minX - gap - leftMinX))
            let leftRect = NSRect(
                x: leftMinX,
                y: sideY,
                width: leftWidth,
                height: labelHeight
            )
            let rightRect = NSRect(
                x: clampedX(joystickFrame.maxX + gap, width: sideWidth),
                y: sideY,
                width: sideWidth,
                height: labelHeight
            )

            drawText(state.up.label, in: upRect, alignment: .center, isActive: state.up.isActive, color: foregroundColor)
            drawText(state.down.label, in: downRect, alignment: .center, isActive: state.down.isActive, color: foregroundColor)
            drawText(state.left.label, in: leftRect, alignment: .right, isActive: state.left.isActive, color: foregroundColor)
            drawText(state.right.label, in: rightRect, alignment: .left, isActive: state.right.isActive, color: foregroundColor)
        }

        private func drawMappingRows(_ rows: [JoystickCaptureHUDState.MappingRow]) {
            guard !rows.isEmpty else { return }

            let stackFrame = mappingRowsFrame(forCount: rows.count)

            for (index, row) in rows.enumerated() {
                let rect = NSRect(
                    x: stackFrame.minX,
                    y: stackFrame.minY + CGFloat(rows.count - 1 - index) * Self.rowHeight,
                    width: stackFrame.width,
                    height: Self.rowHeight
                )
                let color = row.isActive ? accentColor(for: row.accent) : foregroundColor
                drawText(
                    "\(row.title): \(row.value)",
                    in: rect,
                    alignment: .left,
                    isActive: row.isActive,
                    color: color
                )
            }
        }

        private func mappingRowsFrame(forCount rowCount: Int) -> NSRect {
            let totalHeight = CGFloat(rowCount) * Self.rowHeight
            let availableWidth = max(68, joystickFrame.minX - 14)
            let preferredWidth = min(max(128, bounds.width * 0.34), 210)
            let rowWidth = min(preferredWidth, availableWidth)
            let startY = min(
                max(4, joystickFrame.midY - totalHeight / 2),
                max(4, bounds.maxY - totalHeight - 4)
            )

            return NSRect(
                x: bounds.minX + 6,
                y: startY,
                width: rowWidth,
                height: totalHeight
            )
        }

        private func drawText(
            _ text: String,
            in rect: NSRect,
            alignment: NSTextAlignment,
            isActive: Bool,
            color: NSColor
        ) {
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = alignment
            paragraphStyle.lineBreakMode = .byTruncatingTail
            let font = NSFont.systemFont(ofSize: 13, weight: isActive ? .bold : .semibold)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraphStyle,
            ]
            NSAttributedString(string: text, attributes: attributes).draw(
                in: rect.insetBy(dx: Self.horizontalPadding, dy: 1)
            )
        }

        private func accentColor(for accent: JoystickCaptureHUDState.ActionAccent?) -> NSColor {
            switch accent {
            case .toggleHold:
                return .systemRed
            case .turbo:
                return .systemGreen
            case .action:
                return .systemBlue
            case nil:
                return foregroundColor
            }
        }

        private func clampedX(_ x: CGFloat, width: CGFloat) -> CGFloat {
            min(max(x, bounds.minX + 4), max(bounds.minX + 4, bounds.maxX - width - 4))
        }
    }

    /// Header controls are separated from the pad surface so minimize/menu/hide interactions do not press buttons.
    private final class HeaderBarView: NSView {
        var onToggleMinimize: (() -> Void)?
        var onHideOverlay: (() -> Void)?
        var onToggleCapture: (() -> Void)?
        var onToggleTemporaryRelease: (() -> Void)?
        var menuProvider: (() -> NSMenu?)?
        var onDragBegan: ((NSEvent) -> Void)?
        var onDragChanged: ((NSEvent) -> Void)?
        var onDragEnded: (() -> Void)?

        private var foregroundColor: NSColor = .white
        private let closeButton = NSButton(frame: .zero)
        private let minimizeButton = NSButton(frame: .zero)
        private let captureButton = NSButton(frame: .zero)
        private let captureCountdownLabel = NSTextField(labelWithString: "")
        private let temporaryReleaseButton = NSButton(frame: .zero)
        private let temporaryReleaseCountdownLabel = NSTextField(labelWithString: "")
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
            captureButton.isHidden = minimized
            captureCountdownLabel.isHidden = minimized
            temporaryReleaseButton.isHidden = minimized
            temporaryReleaseCountdownLabel.isHidden = minimized
            titleLabel.isHidden = minimized
            menuButton.isHidden = minimized
            separatorView.isHidden = minimized
            applyForegroundColor()
            needsLayout = true
        }

        func updateCaptureState(
            isPending: Bool,
            isActive: Bool,
            isTemporarilyReleased: Bool,
            countdown: Int,
            temporaryReleaseCountdown: Int
        ) {
            captureButton.title = (isPending || isActive || isTemporarilyReleased) ? "􀎥" : "􀎡"
            captureCountdownLabel.stringValue = isPending ? "\(max(0, countdown))" : ""
            captureCountdownLabel.isHidden = closeButton.isHidden || !isPending
            temporaryReleaseButton.isHidden = closeButton.isHidden || (!isActive && !isTemporarilyReleased)
            temporaryReleaseButton.isEnabled = isActive || isTemporarilyReleased
            temporaryReleaseCountdownLabel.stringValue = isTemporarilyReleased ? "\(max(0, temporaryReleaseCountdown))" : ""
            temporaryReleaseCountdownLabel.isHidden = closeButton.isHidden || !isTemporarilyReleased
            applyTitleColor(to: captureButton)
            applyTitleColor(to: temporaryReleaseButton)
            needsLayout = true
        }

        func handleVirtualPrimaryUp(at point: NSPoint) -> Bool {
            if !temporaryReleaseButton.isHidden, temporaryReleaseButton.frame.contains(point) {
                onToggleTemporaryRelease?()
                return true
            }

            guard !captureButton.isHidden, captureButton.frame.contains(point) else {
                return false
            }

            onToggleCapture?()
            return true
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

            captureButton.title = "􀎡"
            captureButton.font = NSFont.systemFont(ofSize: 16, weight: .regular)
            captureButton.isBordered = false
            captureButton.contentTintColor = .white
            captureButton.target = self
            captureButton.action = #selector(handleToggleCapture)
            captureButton.setButtonType(.momentaryChange)
            addSubview(captureButton)

            captureCountdownLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
            captureCountdownLabel.textColor = .white
            captureCountdownLabel.alignment = .center
            captureCountdownLabel.isHidden = true
            addSubview(captureCountdownLabel)

            temporaryReleaseButton.title = "􂆊"
            temporaryReleaseButton.font = NSFont.systemFont(ofSize: 16, weight: .regular)
            temporaryReleaseButton.isBordered = false
            temporaryReleaseButton.contentTintColor = .white
            temporaryReleaseButton.target = self
            temporaryReleaseButton.action = #selector(handleToggleTemporaryRelease)
            temporaryReleaseButton.setButtonType(.momentaryChange)
            temporaryReleaseButton.isHidden = true
            addSubview(temporaryReleaseButton)

            temporaryReleaseCountdownLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
            temporaryReleaseCountdownLabel.textColor = .white
            temporaryReleaseCountdownLabel.alignment = .center
            temporaryReleaseCountdownLabel.isHidden = true
            addSubview(temporaryReleaseCountdownLabel)

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
            captureButton.contentTintColor = foregroundColor
            captureCountdownLabel.textColor = foregroundColor
            temporaryReleaseButton.contentTintColor = foregroundColor
            temporaryReleaseCountdownLabel.textColor = foregroundColor
            menuButton.contentTintColor = foregroundColor
            titleLabel.textColor = foregroundColor
            separatorView.layer?.backgroundColor = foregroundColor.withAlphaComponent(0.12).cgColor

            applyTitleColor(to: closeButton)
            applyTitleColor(to: minimizeButton)
            applyTitleColor(to: captureButton)
            applyTitleColor(to: temporaryReleaseButton)
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
                captureButton.frame = NSRect(x: menuButton.frame.minX - 30, y: bounds.midY - buttonSize.height / 2, width: buttonSize.width, height: buttonSize.height)
                temporaryReleaseButton.frame = temporaryReleaseButton.isHidden
                    ? .zero
                    : NSRect(x: captureButton.frame.minX - 30, y: bounds.midY - buttonSize.height / 2, width: buttonSize.width, height: buttonSize.height)
                if captureCountdownLabel.isHidden {
                    captureCountdownLabel.frame = .zero
                } else {
                    captureCountdownLabel.frame = NSRect(x: captureButton.frame.minX - 28, y: bounds.midY - 9, width: 24, height: 18)
                }
                if temporaryReleaseCountdownLabel.isHidden {
                    temporaryReleaseCountdownLabel.frame = .zero
                } else {
                    temporaryReleaseCountdownLabel.frame = NSRect(x: temporaryReleaseButton.frame.minX - 28, y: bounds.midY - 9, width: 24, height: 18)
                }

                let rightControlMinX = [
                    menuButton.frame.minX,
                    captureButton.frame.minX,
                    captureCountdownLabel.isHidden ? .greatestFiniteMagnitude : captureCountdownLabel.frame.minX,
                    temporaryReleaseButton.isHidden ? .greatestFiniteMagnitude : temporaryReleaseButton.frame.minX,
                    temporaryReleaseCountdownLabel.isHidden ? .greatestFiniteMagnitude : temporaryReleaseCountdownLabel.frame.minX
                ].min() ?? captureButton.frame.minX
                let titleInset = max(minimizeButton.frame.maxX + 18, bounds.maxX - rightControlMinX + 18)
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

        @objc private func handleToggleCapture() {
            onToggleCapture?()
        }

        @objc private func handleToggleTemporaryRelease() {
            onToggleTemporaryRelease?()
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
    var onVirtualCursorActivity: (() -> Void)?

    private var buttonViews: [GamepadButton: GamepadButtonView] = [:]
    private let headerBar = HeaderBarView(frame: .zero)
    private let padSurface = PadSurfaceView(frame: .zero)
    private let blurView = PassthroughVisualEffectView(frame: .zero)
    private let backgroundTintView = PassthroughView(frame: .zero)
    private let pointerLocationView = PointerLocationView(frame: .zero)
    private let joystickCaptureHUDView = JoystickCaptureHUDView(frame: .zero)

    private var currentProfile: Profile
    private var isMinimized = false
    private var capturedJoystickButton: GamepadButton?
    private var authoredButtonFrames: [GamepadButton: NSRect] = [:]
    private var currentJoystickHUDState: JoystickCaptureHUDState?
    private var activeDwellButton: GamepadButton?
    private var virtualCursorPoint: NSPoint?
    private weak var virtualPrimaryButtonView: GamepadButtonView?
    private weak var virtualSecondaryButtonView: GamepadButtonView?
    private weak var virtualJoystickCaptureView: GamepadButtonView?
    private var captureStateObserver: NSObjectProtocol?

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

    deinit {
        if let captureStateObserver {
            NotificationCenter.default.removeObserver(captureStateObserver)
        }
    }

    // MARK: - Profile Reloading

    func reload(profile: Profile, minimized: Bool, preservesCapture: Bool = false) {
        if !preservesCapture {
            MouseDiagnosticController.shared.cancelCapture(reason: "profileReload")
        }

        releaseAllVirtualInputs()
        currentProfile = profile
        isMinimized = minimized
        updateBackgroundColor()
        updatePointerLocationVisibility(atScreenPoint: NSEvent.mouseLocation)
        updateHeader()
        updateLayout()
        buildButtons(profile: profile)

        if MouseDiagnosticController.shared.isCaptureActive {
            ensureVirtualCursorPoint()
            if let virtualCursorPoint {
                syncButtonHover(atContentPoint: virtualCursorPoint)
            }
        }
    }

    func setMinimized(_ minimized: Bool) {
        if minimized {
            MouseDiagnosticController.shared.cancelCapture(reason: "minimize")
            releaseAllVirtualInputs()
        }
        isMinimized = minimized
        updatePointerLocationVisibility(atScreenPoint: NSEvent.mouseLocation)
        updateHeader()
        updateLayout()
        buildButtons(profile: currentProfile)
    }

    func releaseAllInputs() {
        MouseDiagnosticController.shared.cancelCapture(reason: "releaseAllInputs")
        releaseAllVirtualInputs()
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
        syncButtonHover(atContentPoint: contentPoint)
    }

    private func syncButtonHover(atContentPoint contentPoint: NSPoint) {
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
        headerBar.onToggleCapture = {
            MouseDiagnosticController.shared.toggleCapture()
        }
        headerBar.onToggleTemporaryRelease = {
            MouseDiagnosticController.shared.toggleTemporaryRelease()
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
        padSurface.addSubview(joystickCaptureHUDView)

        addSubview(pointerLocationView)
        configureVirtualCursorCapture()
    }

    private func updateHeader() {
        headerBar.updateTitle(currentProfile.name)
        headerBar.updateForegroundColor(headerForegroundColor())
        headerBar.setMinimized(isMinimized)
        headerBar.updateCaptureState(
            isPending: MouseDiagnosticController.shared.isCapturePending,
            isActive: MouseDiagnosticController.shared.isCaptureActive,
            isTemporarilyReleased: MouseDiagnosticController.shared.isCaptureTemporarilyReleased,
            countdown: MouseDiagnosticController.shared.captureCountdownSeconds,
            temporaryReleaseCountdown: MouseDiagnosticController.shared.temporaryReleaseCountdownSeconds
        )
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
        syncJoystickCaptureHUDView()
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
            joystickCaptureHUDView.update(state: nil, joystickFrame: .zero, foregroundColor: headerForegroundColor())
            return
        }

        let padHeight = max(0, bounds.height - Self.headerHeight - Self.contentGap)
        padSurface.isHidden = false
        padSurface.frame = NSRect(x: 0, y: 0, width: bounds.width, height: padHeight)
        joystickCaptureHUDView.frame = padSurface.bounds
        syncJoystickCaptureHUDView()
    }

    private func updatePointerLocationVisibility(atScreenPoint screenPoint: NSPoint) {
        if MouseDiagnosticController.shared.isCaptureActive, !isMinimized {
            guard capturedJoystickButton == nil else {
                pointerLocationView.hide()
                return
            }

            ensureVirtualCursorPoint()
            if let virtualCursorPoint {
                pointerLocationView.show(centeredAt: virtualCursorPoint)
                return
            }
        }

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

    // MARK: - Virtual Cursor Capture

    private func configureVirtualCursorCapture() {
        let controller = MouseDiagnosticController.shared
        controller.onVirtualMouseDelta = { [weak self] delta in
            DispatchQueue.main.async {
                self?.moveVirtualCursor(by: delta)
            }
        }
        controller.onVirtualMouseButton = { [weak self] button, isDown in
            DispatchQueue.main.async {
                self?.routeVirtualMouseButton(button, isDown: isDown)
            }
        }
        controller.onVirtualScroll = { [weak self] delta in
            DispatchQueue.main.async {
                self?.routeVirtualScroll(delta)
            }
        }
        controller.onCaptureDeactivated = { [weak self] in
            DispatchQueue.main.async {
                self?.releaseAllVirtualInputs()
                self?.virtualCursorPoint = nil
                self?.updateHeader()
                self?.updatePointerLocationVisibility(atScreenPoint: NSEvent.mouseLocation)
            }
        }

        captureStateObserver = NotificationCenter.default.addObserver(
            forName: MouseDiagnosticController.stateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }

            if MouseDiagnosticController.shared.isCaptureActive {
                self.ensureVirtualCursorPoint()
            } else if !MouseDiagnosticController.shared.isCapturePending {
                self.releaseAllVirtualInputs()
            }

            self.updateHeader()
            self.updatePointerLocationVisibility(atScreenPoint: NSEvent.mouseLocation)
        }
    }

    private func ensureVirtualCursorPoint() {
        guard virtualCursorPoint == nil else {
            virtualCursorPoint = virtualCursorPoint.map(clampedVirtualCursorPoint)
            return
        }

        if let window {
            let windowPoint = window.convertPoint(fromScreen: NSEvent.mouseLocation)
            let contentPoint = convert(windowPoint, from: nil)
            if bounds.contains(contentPoint) {
                virtualCursorPoint = clampedVirtualCursorPoint(contentPoint)
                return
            }
        }

        virtualCursorPoint = clampedVirtualCursorPoint(NSPoint(x: padSurface.frame.midX, y: padSurface.frame.midY))
    }

    private func moveVirtualCursor(by delta: CGPoint) {
        guard MouseDiagnosticController.shared.isCaptureActive, !isMinimized else {
            return
        }

        if let virtualJoystickCaptureView {
            virtualJoystickCaptureView.updateVirtualJoystickCapture(delta: delta)
            onVirtualCursorActivity?()
            return
        }

        ensureVirtualCursorPoint()
        guard let currentPoint = virtualCursorPoint else {
            return
        }

        let nextPoint = clampedVirtualCursorPoint(NSPoint(
            x: currentPoint.x + delta.x,
            y: currentPoint.y + delta.y
        ))
        virtualCursorPoint = nextPoint
        pointerLocationView.show(centeredAt: nextPoint)
        syncButtonHover(atContentPoint: nextPoint)
        onVirtualCursorActivity?()

        if let virtualPrimaryButtonView,
           let event = syntheticMouseEvent(type: .leftMouseDragged, atContentPoint: nextPoint) {
            virtualPrimaryButtonView.mouseDragged(with: event)
        }

        if let virtualSecondaryButtonView,
           let event = syntheticMouseEvent(type: .rightMouseDragged, atContentPoint: nextPoint) {
            virtualSecondaryButtonView.rightMouseDragged(with: event)
        }
    }

    private func routeVirtualMouseButton(_ button: MouseDiagnosticController.VirtualMouseButton, isDown: Bool) {
        guard MouseDiagnosticController.shared.isCaptureActive, !isMinimized else {
            return
        }

        onVirtualCursorActivity?()
        ensureVirtualCursorPoint()
        guard let virtualCursorPoint else {
            return
        }

        if let virtualJoystickCaptureView {
            switch (button, isDown) {
            case (.left, true), (.left, false):
                virtualJoystickCaptureView.handleVirtualJoystickLeftClick(isDown: isDown)
            case (.right, true), (.right, false):
                let isStillCaptured = virtualJoystickCaptureView.handleVirtualJoystickRightClick(isDown: isDown)
                if !isStillCaptured {
                    self.virtualJoystickCaptureView = nil
                }
            }
            return
        }

        if button == .left,
           !isDown,
           headerBar.frame.contains(virtualCursorPoint),
           headerBar.handleVirtualPrimaryUp(at: headerBar.convert(virtualCursorPoint, from: self)) {
            return
        }

        let targetView = buttonView(atContentPoint: virtualCursorPoint)
        switch (button, isDown) {
        case (.left, true):
            guard let targetView else {
                return
            }

            if targetView.beginVirtualJoystickCapture() {
                virtualJoystickCaptureView = targetView
                virtualPrimaryButtonView = nil
                return
            }

            guard let event = syntheticMouseEvent(type: .leftMouseDown, atContentPoint: virtualCursorPoint) else {
                return
            }
            virtualPrimaryButtonView = targetView
            targetView.mouseDown(with: event)

        case (.left, false):
            guard let targetView = virtualPrimaryButtonView ?? targetView,
                  let event = syntheticMouseEvent(type: .leftMouseUp, atContentPoint: virtualCursorPoint) else {
                virtualPrimaryButtonView = nil
                return
            }

            targetView.mouseUp(with: event)
            virtualPrimaryButtonView = nil

        case (.right, true):
            guard let targetView,
                  let event = syntheticMouseEvent(type: .rightMouseDown, atContentPoint: virtualCursorPoint) else {
                return
            }

            virtualSecondaryButtonView = targetView
            targetView.rightMouseDown(with: event)

        case (.right, false):
            guard let targetView = virtualSecondaryButtonView ?? targetView,
                  let event = syntheticMouseEvent(type: .rightMouseUp, atContentPoint: virtualCursorPoint) else {
                virtualSecondaryButtonView = nil
                return
            }

            targetView.rightMouseUp(with: event)
            virtualSecondaryButtonView = nil
        }
    }

    private func routeVirtualScroll(_ delta: CGFloat) {
        guard MouseDiagnosticController.shared.isCaptureActive else {
            return
        }

        onVirtualCursorActivity?()
        if let virtualJoystickCaptureView {
            if !virtualJoystickCaptureView.handleVirtualScroll(delta: delta) {
                debugLog("[ContentView] virtualScroll swallowed delta=\(delta)")
            }
            return
        }

        ensureVirtualCursorPoint()
        guard let virtualCursorPoint,
              let targetView = buttonView(atContentPoint: virtualCursorPoint),
              targetView.handleVirtualScroll(delta: delta) else {
            debugLog("[ContentView] virtualScroll swallowed delta=\(delta)")
            return
        }

        debugLog("[ContentView] virtualScroll routed delta=\(delta) button=\(targetView.button.rawValue)")
    }

    private func releaseAllVirtualInputs() {
        var released = Set<ObjectIdentifier>()

        if let virtualJoystickCaptureView {
            released.insert(ObjectIdentifier(virtualJoystickCaptureView))
            virtualJoystickCaptureView.releaseIfNeeded()
        }

        if let virtualPrimaryButtonView {
            if !released.contains(ObjectIdentifier(virtualPrimaryButtonView)) {
                released.insert(ObjectIdentifier(virtualPrimaryButtonView))
                virtualPrimaryButtonView.releaseIfNeeded()
            }
        }

        if let virtualSecondaryButtonView,
           !released.contains(ObjectIdentifier(virtualSecondaryButtonView)) {
            virtualSecondaryButtonView.releaseIfNeeded()
        }

        virtualJoystickCaptureView = nil
        virtualPrimaryButtonView = nil
        virtualSecondaryButtonView = nil
        clearButtonHover()
    }

    private func buttonView(atContentPoint contentPoint: NSPoint) -> GamepadButtonView? {
        guard bounds.contains(contentPoint), padSurface.frame.contains(contentPoint) else {
            return nil
        }

        let padPoint = padSurface.convert(contentPoint, from: self)
        for button in currentProfile.orderedButtonIDs.reversed() {
            guard let view = buttonViews[button], !view.isHidden else {
                continue
            }

            let localPoint = view.convert(padPoint, from: padSurface)
            if view.hitTest(localPoint) != nil {
                return view
            }
        }

        return nil
    }

    private func syntheticMouseEvent(type: NSEvent.EventType, atContentPoint contentPoint: NSPoint) -> NSEvent? {
        guard let window else {
            return nil
        }

        return NSEvent.mouseEvent(
            with: type,
            location: convert(contentPoint, to: nil),
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )
    }

    private func clampedVirtualCursorPoint(_ point: NSPoint) -> NSPoint {
        let targetBounds = isMinimized ? bounds : padSurface.frame.union(headerBar.frame).intersection(bounds)
        guard !targetBounds.isEmpty else {
            return NSPoint(x: bounds.midX, y: bounds.midY)
        }

        return NSPoint(
            x: min(max(point.x, targetBounds.minX), targetBounds.maxX),
            y: min(max(point.y, targetBounds.minY), targetBounds.maxY)
        )
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
            authoredButtonFrames.removeAll()
            capturedJoystickButton = nil
            currentJoystickHUDState = nil
            joystickCaptureHUDView.update(state: nil, joystickFrame: .zero, foregroundColor: headerForegroundColor())
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
            authoredButtonFrames.removeValue(forKey: button)
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
            authoredButtonFrames[button] = frame
            let displayFrame = capturedJoystickButton == button
                ? centeredCapturedJoystickFrame(for: frame)
                : frame

            if let view = buttonViews[button] {
                view.frame = displayFrame
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
                view.onJoystickCaptureHUDChanged = { [weak self, weak view] state in
                    guard let self, let view else {
                        return
                    }
                    self.updateJoystickCaptureHUD(state, for: view.button)
                }
                view.onDwellActionToggled = { [weak self] button, config in
                    self?.onDwellActionToggled?(button, config) ?? false
                }
                view.frame = displayFrame
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
        currentJoystickHUDState = nil
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
            currentJoystickHUDState = nil
        } else if capturedJoystickButton == button {
            capturedJoystickButton = nil
            currentJoystickHUDState = nil
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
            let isCapturedButton = capturedJoystickButton == button
            view.isHidden = capturedJoystickButton.map { $0 != button } ?? false
            if let authoredFrame = authoredButtonFrames[button] {
                view.frame = isCapturedButton ? centeredCapturedJoystickFrame(for: authoredFrame) : authoredFrame
            }
        }

        syncJoystickCaptureHUDView()
    }

    private func centeredCapturedJoystickFrame(for authoredFrame: NSRect) -> NSRect {
        let size = authoredFrame.size
        let targetCenterX = padSurface.bounds.minX + (padSurface.bounds.width * 0.68)
        return NSRect(
            x: min(max(targetCenterX - size.width / 2, 0), max(0, padSurface.bounds.width - size.width)),
            y: min(max(padSurface.bounds.midY - size.height / 2, 0), max(0, padSurface.bounds.height - size.height)),
            width: size.width,
            height: size.height
        )
    }

    private func updateJoystickCaptureHUD(_ state: JoystickCaptureHUDState?, for button: GamepadButton) {
        guard capturedJoystickButton == button else {
            return
        }

        currentJoystickHUDState = state
        syncJoystickCaptureHUDView()
    }

    private func syncJoystickCaptureHUDView() {
        guard let capturedJoystickButton,
              let capturedView = buttonViews[capturedJoystickButton],
              let currentJoystickHUDState,
              !isMinimized,
              !padSurface.isHidden else {
            joystickCaptureHUDView.update(state: nil, joystickFrame: .zero, foregroundColor: headerForegroundColor())
            return
        }

        joystickCaptureHUDView.frame = padSurface.bounds
        joystickCaptureHUDView.update(
            state: currentJoystickHUDState,
            joystickFrame: capturedView.frame,
            foregroundColor: headerForegroundColor()
        )
        padSurface.addSubview(joystickCaptureHUDView, positioned: .above, relativeTo: nil)
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
