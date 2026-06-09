import Cocoa

/// Stores overlay-wide display settings separately from profile data so every profile shares the same fade behavior.
enum GamepadSettings {
    static let fadeTimeoutDidChange = Notification.Name("GamepadFadeTimeoutDidChange")

    private static let fadeTimeoutDefaultsKey = "gamepadFadeTimeout"

    static let fadeAnimationDuration: TimeInterval = 0.18
    static let fadeTimeoutOptions: [(title: String, seconds: TimeInterval?)] = [
        ("Never", nil),
        ("3 Seconds", 3),
        ("5 Seconds", 5),
        ("10 Seconds", 10),
        ("30 Seconds", 30),
    ]

    static var fadeTimeout: TimeInterval? {
        get {
            let defaults = UserDefaults.standard
            guard defaults.object(forKey: fadeTimeoutDefaultsKey) != nil else {
                return 5
            }

            let value = defaults.double(forKey: fadeTimeoutDefaultsKey)
            return value > 0 ? value : nil
        }
        set {
            let defaults = UserDefaults.standard

            if let newValue {
                defaults.set(newValue, forKey: fadeTimeoutDefaultsKey)
            } else {
                defaults.set(0, forKey: fadeTimeoutDefaultsKey)
            }

            NotificationCenter.default.post(name: fadeTimeoutDidChange, object: nil)
        }
    }
}

/// Borderless, non-activating overlay panel that stays above other apps while avoiding keyboard focus.
final class GamepadWindow: NSPanel, NSWindowDelegate {

    // Window state is intentionally small: content owns button input, while the panel owns visibility and fading.
    private var isMinimized = false
    private var inactivityTimer: Timer?
    private var isFadedForInactivity = false
    private var isJoystickCaptureActive = false
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var loadedActiveProfileID: UUID?
    private let dwellActionController = DwellActionController()

    convenience init() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        var profile = ProfileStore.shared.activeResolvedProfile
        profile.name = ProfileStore.shared.activeProfile.name
        MouseDiagnosticController.shared.configureCaptureTiming(
            armDelaySeconds: profile.mouseCaptureArmDelaySeconds,
            temporaryReleaseSeconds: profile.mouseCaptureTemporaryReleaseSeconds
        )
        let size = GamepadContentView.windowSize(for: profile, minimized: false)
        let origin = NSPoint(
            x: screen.visibleFrame.minX + (screen.visibleFrame.width - size.width) / 2,
            y: screen.visibleFrame.minY + 20
        )
        let frame = NSRect(origin: origin, size: size)

        self.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        loadedActiveProfileID = ProfileStore.shared.activeProfileID

        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        delegate = self
        contentMinSize = Self.minimumContentSize
        contentMaxSize = maximumContentSize()
        showsResizeIndicator = true

        let content = GamepadContentView(frame: NSRect(origin: .zero, size: size), profile: profile)
        content.onToggleMinimize = { [weak self] in
            self?.toggleMinimized()
        }
        content.onHideOverlay = { [weak self] in
            self?.hideOverlay()
        }
        content.onJoystickCaptureChanged = { [weak self] isCaptured in
            self?.setJoystickCaptureActive(isCaptured)
        }
        content.onDwellActionToggled = { [weak self] button, config in
            guard let self else {
                return false
            }

            return self.dwellActionController.toggle(
                button: button,
                config: config,
                currentMouseLocation: NSEvent.mouseLocation
            )
        }
        content.onVirtualCursorActivity = { [weak self] in
            self?.noteUserActivity()
        }
        content.menuProvider = {
            (NSApp.delegate as? AppDelegate)?.makeGamepadMenu()
        }
        contentView = content

        dwellActionController.onActiveButtonChanged = { [weak self] activeButton in
            (self?.contentView as? GamepadContentView)?.setActiveDwellButton(activeButton)
        }

        alphaValue = profile.opacity
        startInactivityMonitoring()
        noteUserActivity()
        debugLog("[GamepadWindow] Created. level=\(level.rawValue) ignoresMouseEvents=\(ignoresMouseEvents) canBecomeKey=\(canBecomeKey)")
    }

    // Keeping both false preserves the focused game/app while users interact with the overlay.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    deinit {
        dwellActionController.deactivate()
        inactivityTimer?.invalidate()
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
        }
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
        }
        NotificationCenter.default.removeObserver(self)
    }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel:
            dwellActionController.notePhysicalMouseInterrupt(event, at: NSEvent.mouseLocation)
            dwellActionController.noteMouseLocation(NSEvent.mouseLocation, from: event)
            noteUserActivity()
            syncButtonHoverToMouseLocation()
            syncPointerLocationToMouseLocation()
        case .leftMouseUp, .leftMouseDragged,
             .rightMouseUp, .rightMouseDragged,
             .otherMouseUp, .otherMouseDragged,
             .mouseMoved:
            if shouldInterruptDwell(for: event) {
                dwellActionController.notePhysicalMouseInterrupt(event, at: NSEvent.mouseLocation)
            }
            dwellActionController.noteMouseLocation(NSEvent.mouseLocation, from: event)
            noteUserActivity()
            syncButtonHoverToMouseLocation()
            syncPointerLocationToMouseLocation()
        default:
            break
        }

        super.sendEvent(event)
    }

    private func shouldInterruptDwell(for event: NSEvent) -> Bool {
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown,
             .leftMouseUp, .rightMouseUp, .otherMouseUp,
             .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
             .scrollWheel:
            return true
        default:
            return false
        }
    }

    // MARK: - Visibility and Profile Reloading

    func showGamepad() {
        orderFrontRegardless()
        noteUserActivity()
    }

    func hideGamepad() {
        releaseAllInputs()
        inactivityTimer?.invalidate()
        orderOut(nil)
    }

    func releaseAllInputs() {
        dwellActionController.deactivate()
        (contentView as? GamepadContentView)?.releaseAllInputs()
    }

    func reloadProfile() {
        let store = ProfileStore.shared
        let activeProfileID = store.activeProfileID
        let preservesCapture = MouseDiagnosticController.shared.hasCaptureState
            && loadedActiveProfileID == activeProfileID
        var profile = store.activeResolvedProfile
        profile.name = store.activeProfile.name
        MouseDiagnosticController.shared.configureCaptureTiming(
            armDelaySeconds: profile.mouseCaptureArmDelaySeconds,
            temporaryReleaseSeconds: profile.mouseCaptureTemporaryReleaseSeconds
        )
        reconcileActiveDwellAction(with: profile)
        updateResizeConstraints()
        resizeForCurrentState(using: profile)
        (contentView as? GamepadContentView)?.reload(
            profile: profile,
            minimized: isMinimized,
            preservesCapture: preservesCapture
        )
        (contentView as? GamepadContentView)?.setActiveDwellButton(dwellActionController.activeButton)
        applyCurrentAlpha(animated: false)
        resetInactivityTimer()
        loadedActiveProfileID = activeProfileID
    }

    @objc private func hideOverlay() {
        hideGamepad()
    }

    private func toggleMinimized() {
        isMinimized.toggle()
        if isMinimized {
            dwellActionController.deactivate()
        }
        var profile = ProfileStore.shared.activeResolvedProfile
        profile.name = ProfileStore.shared.activeProfile.name
        updateResizeConstraints()
        resizeForCurrentState(using: profile)
        (contentView as? GamepadContentView)?.setMinimized(isMinimized)
        noteUserActivity()
        debugLog("[GamepadWindow] toggleMinimized minimized=\(isMinimized)")
    }

    // MARK: - Resizing

    private func resizeForCurrentState(using profile: Profile) {
        updateResizeConstraints()
        let newSize = GamepadContentView.windowSize(for: profile, minimized: isMinimized)
        guard frame.size != newSize else { return }

        let currentFrame = frame
        let newOrigin = NSPoint(x: currentFrame.minX, y: currentFrame.maxY - newSize.height)
        setFrame(NSRect(origin: newOrigin, size: newSize), display: true)
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        guard !isMinimized else {
            return GamepadContentView.minimizedTileSize
        }

        updateResizeConstraints()

        let minimumFrame = frameRect(forContentRect: NSRect(origin: .zero, size: Self.minimumContentSize)).size
        let maximumFrame = frameRect(forContentRect: NSRect(origin: .zero, size: maximumContentSize())).size

        return NSSize(
            width: min(max(frameSize.width, minimumFrame.width), maximumFrame.width),
            height: min(max(frameSize.height, minimumFrame.height), maximumFrame.height)
        )
    }

    func windowDidResize(_ notification: Notification) {
        updateResizeConstraints()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        persistCurrentWindowSize()
        updateResizeConstraints()
    }

    // MARK: - Inactivity Fade

    private func startInactivityMonitoring() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleFadeTimeoutDidChange),
            name: GamepadSettings.fadeTimeoutDidChange,
            object: nil
        )

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .leftMouseDown, .rightMouseDown, .otherMouseDown, .leftMouseUp, .rightMouseUp, .otherMouseUp, .scrollWheel]
        ) { [weak self] event in
            if self?.shouldInterruptDwell(for: event) == true {
                self?.dwellActionController.notePhysicalMouseInterrupt(event, at: NSEvent.mouseLocation)
            }
            self?.dwellActionController.noteMouseLocation(NSEvent.mouseLocation, from: event)
            self?.syncButtonHoverToMouseLocation()
            self?.syncPointerLocationToMouseLocation()
            self?.wakeIfMouseIsOverWindow()
        }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .leftMouseDown, .rightMouseDown, .otherMouseDown, .leftMouseUp, .rightMouseUp, .otherMouseUp, .scrollWheel]
        ) { [weak self] event in
            if self?.shouldInterruptDwell(for: event) == true {
                self?.dwellActionController.notePhysicalMouseInterrupt(event, at: NSEvent.mouseLocation)
            }
            self?.dwellActionController.noteMouseLocation(NSEvent.mouseLocation, from: event)
            return event
        }
    }

    private func updateResizeConstraints() {
        if isMinimized {
            let minimizedSize = GamepadContentView.minimizedTileSize
            contentMinSize = minimizedSize
            contentMaxSize = minimizedSize
            return
        }

        contentMinSize = Self.minimumContentSize
        contentMaxSize = maximumContentSize()
    }

    private func noteUserActivity() {
        guard isVisible else { return }

        if isFadedForInactivity {
            isFadedForInactivity = false
            applyCurrentAlpha(animated: true)
        }

        resetInactivityTimer()
    }

    private func resetInactivityTimer() {
        inactivityTimer?.invalidate()

        guard isVisible, !isJoystickCaptureActive, let fadeTimeout = GamepadSettings.fadeTimeout else {
            if isFadedForInactivity {
                isFadedForInactivity = false
                applyCurrentAlpha(animated: true)
            }
            return
        }

        inactivityTimer = Timer.scheduledTimer(withTimeInterval: fadeTimeout, repeats: false) { [weak self] _ in
            self?.fadeForInactivity()
        }
    }

    private func fadeForInactivity() {
        guard isVisible, !isJoystickCaptureActive, !isFadedForInactivity else { return }
        isFadedForInactivity = true
        applyCurrentAlpha(animated: true)
    }

    private func wakeIfMouseIsOverWindow() {
        guard isFadedForInactivity, isVisible, frame.contains(NSEvent.mouseLocation) else { return }
        noteUserActivity()
    }

    private func syncButtonHoverToMouseLocation() {
        guard isVisible else { return }
        (contentView as? GamepadContentView)?.syncButtonHover(atScreenPoint: NSEvent.mouseLocation)
    }

    private func syncPointerLocationToMouseLocation() {
        guard isVisible else { return }
        (contentView as? GamepadContentView)?.syncPointerLocation(atScreenPoint: NSEvent.mouseLocation)
    }

    private func reconcileActiveDwellAction(with profile: Profile) {
        guard let activeButton = dwellActionController.activeButton else {
            return
        }

        guard let config = profile.buttons[activeButton.rawValue],
              config.enabled,
              config.type == .dwellAction else {
            dwellActionController.deactivate()
            return
        }

        dwellActionController.updateActiveConfig(config.dwellAction, for: activeButton)
    }

    private func applyCurrentAlpha(animated: Bool) {
        let targetAlpha = isFadedForInactivity ? 0.0 : ProfileStore.shared.activeResolvedProfile.opacity

        guard animated else {
            alphaValue = targetAlpha
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = GamepadSettings.fadeAnimationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animator().alphaValue = targetAlpha
        }
    }

    @objc private func handleFadeTimeoutDidChange() {
        noteUserActivity()
    }

    private func setJoystickCaptureActive(_ active: Bool) {
        guard isJoystickCaptureActive != active else {
            return
        }

        isJoystickCaptureActive = active
        noteUserActivity()
    }

    private func persistCurrentWindowSize() {
        guard !isMinimized else { return }

        let padHeight = max(
            GamepadContentView.minimumPadSize.height,
            contentLayoutRect.height - GamepadContentView.headerHeight - GamepadContentView.contentGap
        )
        let padWidth = max(GamepadContentView.minimumPadSize.width, contentLayoutRect.width)
        ProfileStore.shared.updateActiveProfileDisplaySize(width: padWidth, height: padHeight)
        debugLog("[GamepadWindow] Live resize ended width=\(padWidth) height=\(padHeight)")
    }

    private func maximumContentSize() -> NSSize {
        let visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let maxWidth = max(GamepadContentView.minimumPadSize.width, visibleFrame.maxX - frame.minX - 12)
        let maxHeight = max(
            GamepadContentView.minimumPadSize.height + GamepadContentView.headerHeight + GamepadContentView.contentGap,
            visibleFrame.maxY - frame.minY - 12
        )
        return NSSize(width: maxWidth, height: maxHeight)
    }

    private static var minimumContentSize: NSSize {
        NSSize(
            width: GamepadContentView.minimumPadSize.width,
            height: GamepadContentView.minimumPadSize.height + GamepadContentView.headerHeight + GamepadContentView.contentGap
        )
    }
}
