import Cocoa

/// Coordinates passive mouse diagnostics and the experimental virtual-cursor capture mode.
final class MouseDiagnosticController {
    enum VirtualMouseButton {
        case left
        case right
    }

    static let shared = MouseDiagnosticController()

    static let stateDidChange = Notification.Name("MouseDiagnosticControllerStateDidChange")
    private static let escapeUnlockCount = 5
    private static let escapeSequenceMaximumGap: TimeInterval = 2
    private static let escapeKeyCode: Int64 = 53

    var onVirtualMouseDelta: ((CGPoint) -> Void)?
    var onVirtualMouseButton: ((VirtualMouseButton, Bool) -> Void)?
    var onVirtualScroll: ((CGFloat) -> Void)?
    var onCaptureDeactivated: (() -> Void)?

    /// Passive logging requested by the status-menu diagnostic toggle.
    private(set) var isEnabled = false
    private(set) var isCapturePending = false
    private(set) var isCaptureActive = false
    private(set) var captureCountdownSeconds = 0
    private(set) var isCaptureTemporarilyReleased = false
    private(set) var temporaryReleaseCountdownSeconds = 0
    private(set) var captureArmDelaySeconds = Profile.defaultMouseCaptureArmDelaySeconds
    private(set) var temporaryReleaseDurationSeconds = Profile.defaultMouseCaptureTemporaryReleaseSeconds

    private var mouseEventTap: CFMachPort?
    private var mouseEventTapRunLoopSource: CFRunLoopSource?
    private var keyboardEventTap: CFMachPort?
    private var keyboardEventTapRunLoopSource: CFRunLoopSource?
    private var captureStartTimer: Timer?
    private var temporaryReleaseTimer: Timer?
    private var escapePressCount = 0
    private var lastEscapePressTime: TimeInterval?

    private init() {}

    deinit {
        cancelTemporaryRelease(reason: "deinit")
        deactivateCapture(reason: "deinit")
        cancelPendingCapture(reason: "deinit")
        setEnabled(false)
    }

    var hasCaptureState: Bool {
        isCapturePending || isCaptureActive || isCaptureTemporarilyReleased
    }

    func configureCaptureTiming(armDelaySeconds: Int, temporaryReleaseSeconds: Int) {
        captureArmDelaySeconds = max(1, armDelaySeconds)
        temporaryReleaseDurationSeconds = max(1, temporaryReleaseSeconds)
    }

    @discardableResult
    func setEnabled(_ enabled: Bool) -> Bool {
        if enabled {
            guard installMouseEventTapIfNeeded() else {
                return false
            }

            isEnabled = true
            debugLog("[MouseDiagnostic] enabled")
            NotificationCenter.default.post(name: Self.stateDidChange, object: self)
            return true
        }

        guard isEnabled else {
            return true
        }

        isEnabled = false
        debugLog("[MouseDiagnostic] disabled")
        uninstallMouseEventTapIfIdle()
        NotificationCenter.default.post(name: Self.stateDidChange, object: self)
        return true
    }

    @discardableResult
    func toggle() -> Bool {
        setEnabled(!isEnabled)
    }

    @discardableResult
    func setCaptureEnabled(_ enabled: Bool) -> Bool {
        if enabled {
            return armCapture()
        }

        cancelPendingCapture(reason: "manual")
        cancelTemporaryRelease(reason: "manual")
        deactivateCapture(reason: "manual")
        return true
    }

    @discardableResult
    func toggleCapture() -> Bool {
        setCaptureEnabled(!hasCaptureState)
    }

    func cancelCapture(reason: String) {
        cancelPendingCapture(reason: reason)
        cancelTemporaryRelease(reason: reason)
        deactivateCapture(reason: reason)
    }

    @discardableResult
    func toggleTemporaryRelease() -> Bool {
        if isCaptureTemporarilyReleased {
            return resumeCaptureAfterTemporaryRelease(reason: "manual")
        }

        return temporarilyReleaseCapture()
    }

    @discardableResult
    private func armCapture() -> Bool {
        guard !isCaptureActive else {
            return true
        }

        guard !isCaptureTemporarilyReleased else {
            return true
        }

        guard !isCapturePending else {
            return true
        }

        guard installKeyboardEventTapIfNeeded() else {
            return false
        }

        isCapturePending = true
        captureCountdownSeconds = captureArmDelaySeconds
        resetEscapeSequence()
        scheduleCaptureStartTimer()
        debugLog("[MouseDiagnostic] captureArmed delaySeconds=\(captureArmDelaySeconds)")
        NotificationCenter.default.post(name: Self.stateDidChange, object: self)
        return true
    }

    private func cancelPendingCapture(reason: String) {
        guard isCapturePending else {
            captureStartTimer?.invalidate()
            captureStartTimer = nil
            return
        }

        captureStartTimer?.invalidate()
        captureStartTimer = nil
        isCapturePending = false
        captureCountdownSeconds = 0
        resetEscapeSequence()
        uninstallKeyboardEventTapIfIdle()
        debugLog("[MouseDiagnostic] captureDisarmed reason=\(reason)")
        NotificationCenter.default.post(name: Self.stateDidChange, object: self)
    }

    private func scheduleCaptureStartTimer() {
        captureStartTimer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] timer in
            guard let self, self.isCapturePending else {
                timer.invalidate()
                return
            }

            self.captureCountdownSeconds = max(0, self.captureCountdownSeconds - 1)
            NotificationCenter.default.post(name: Self.stateDidChange, object: self)

            guard self.captureCountdownSeconds <= 0 else {
                return
            }

            timer.invalidate()
            self.captureStartTimer = nil
            self.isCapturePending = false
            _ = self.activateCapture()
        }
        RunLoop.main.add(timer, forMode: .common)
        captureStartTimer = timer
    }

    @discardableResult
    private func activateCapture() -> Bool {
        guard !isCaptureActive else {
            return true
        }

        guard installMouseEventTapIfNeeded() else {
            uninstallKeyboardEventTapIfIdle()
            NotificationCenter.default.post(name: Self.stateDidChange, object: self)
            return false
        }

        guard installKeyboardEventTapIfNeeded() else {
            uninstallMouseEventTapIfIdle()
            NotificationCenter.default.post(name: Self.stateDidChange, object: self)
            return false
        }

        isCaptureActive = true
        captureCountdownSeconds = 0
        resetEscapeSequence()
        debugLog("[MouseDiagnostic] captureEnabled")
        NotificationCenter.default.post(name: Self.stateDidChange, object: self)
        return true
    }

    private func deactivateCapture(reason: String) {
        guard isCaptureActive else { return }

        isCaptureActive = false
        resetEscapeSequence()
        debugLog("[MouseDiagnostic] captureDisabled reason=\(reason)")
        onCaptureDeactivated?()
        uninstallMouseEventTapIfIdle()
        uninstallKeyboardEventTapIfIdle()
        NotificationCenter.default.post(name: Self.stateDidChange, object: self)
    }

    @discardableResult
    private func temporarilyReleaseCapture() -> Bool {
        guard isCaptureActive else {
            return false
        }

        isCaptureActive = false
        isCaptureTemporarilyReleased = true
        temporaryReleaseCountdownSeconds = temporaryReleaseDurationSeconds
        resetEscapeSequence()
        debugLog("[MouseDiagnostic] captureTemporarilyReleased durationSeconds=\(temporaryReleaseDurationSeconds)")
        onCaptureDeactivated?()
        uninstallMouseEventTapIfIdle()
        scheduleTemporaryReleaseTimer()
        NotificationCenter.default.post(name: Self.stateDidChange, object: self)
        return true
    }

    @discardableResult
    private func resumeCaptureAfterTemporaryRelease(reason: String) -> Bool {
        guard isCaptureTemporarilyReleased else {
            return true
        }

        temporaryReleaseTimer?.invalidate()
        temporaryReleaseTimer = nil
        isCaptureTemporarilyReleased = false
        temporaryReleaseCountdownSeconds = 0
        resetEscapeSequence()
        debugLog("[MouseDiagnostic] captureTemporaryReleaseEnded reason=\(reason)")

        let activated = activateCapture()
        if !activated {
            uninstallKeyboardEventTapIfIdle()
            NotificationCenter.default.post(name: Self.stateDidChange, object: self)
        }
        return activated
    }

    private func cancelTemporaryRelease(reason: String) {
        guard isCaptureTemporarilyReleased else {
            temporaryReleaseTimer?.invalidate()
            temporaryReleaseTimer = nil
            temporaryReleaseCountdownSeconds = 0
            return
        }

        temporaryReleaseTimer?.invalidate()
        temporaryReleaseTimer = nil
        isCaptureTemporarilyReleased = false
        temporaryReleaseCountdownSeconds = 0
        resetEscapeSequence()
        debugLog("[MouseDiagnostic] captureTemporaryReleaseCancelled reason=\(reason)")
        uninstallKeyboardEventTapIfIdle()
        NotificationCenter.default.post(name: Self.stateDidChange, object: self)
    }

    private func scheduleTemporaryReleaseTimer() {
        temporaryReleaseTimer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] timer in
            guard let self, self.isCaptureTemporarilyReleased else {
                timer.invalidate()
                return
            }

            self.temporaryReleaseCountdownSeconds = max(0, self.temporaryReleaseCountdownSeconds - 1)
            NotificationCenter.default.post(name: Self.stateDidChange, object: self)

            guard self.temporaryReleaseCountdownSeconds <= 0 else {
                return
            }

            timer.invalidate()
            self.temporaryReleaseTimer = nil
            _ = self.resumeCaptureAfterTemporaryRelease(reason: "timer")
        }
        RunLoop.main.add(timer, forMode: .common)
        temporaryReleaseTimer = timer
    }

    @discardableResult
    private func installMouseEventTapIfNeeded() -> Bool {
        guard mouseEventTap == nil else {
            return true
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: Self.mouseEventMask,
            callback: Self.mouseEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            errorLog("[MouseDiagnostic] ERROR: mouseEventTapCreationFailed")
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        mouseEventTap = tap
        mouseEventTapRunLoopSource = source
        debugLog("[MouseDiagnostic] mouseEventTapInstalled")
        return true
    }

    private func uninstallMouseEventTapIfIdle() {
        guard !isEnabled, !isCaptureActive else {
            return
        }

        uninstallMouseEventTap()
    }

    private func uninstallMouseEventTap() {
        guard mouseEventTap != nil || mouseEventTapRunLoopSource != nil else {
            return
        }

        if let mouseEventTapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), mouseEventTapRunLoopSource, .commonModes)
            self.mouseEventTapRunLoopSource = nil
        }

        if let mouseEventTap {
            CGEvent.tapEnable(tap: mouseEventTap, enable: false)
            self.mouseEventTap = nil
        }

        debugLog("[MouseDiagnostic] mouseEventTapUninstalled")
    }

    @discardableResult
    private func installKeyboardEventTapIfNeeded() -> Bool {
        guard keyboardEventTap == nil else {
            return true
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: Self.keyboardEventMask,
            callback: Self.keyboardEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            errorLog("[MouseDiagnostic] ERROR: keyboardEventTapCreationFailed")
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        keyboardEventTap = tap
        keyboardEventTapRunLoopSource = source
        debugLog("[MouseDiagnostic] keyboardEventTapInstalled")
        return true
    }

    private func uninstallKeyboardEventTapIfIdle() {
        guard !isCapturePending, !isCaptureActive, !isCaptureTemporarilyReleased else {
            return
        }

        uninstallKeyboardEventTap()
    }

    private func uninstallKeyboardEventTap() {
        guard keyboardEventTap != nil || keyboardEventTapRunLoopSource != nil else {
            return
        }

        if let keyboardEventTapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), keyboardEventTapRunLoopSource, .commonModes)
            self.keyboardEventTapRunLoopSource = nil
        }

        if let keyboardEventTap {
            CGEvent.tapEnable(tap: keyboardEventTap, enable: false)
            self.keyboardEventTap = nil
        }

        debugLog("[MouseDiagnostic] keyboardEventTapUninstalled")
    }

    private static var mouseEventMask: CGEventMask {
        eventMask(for: .mouseMoved)
            | eventMask(for: .leftMouseDown)
            | eventMask(for: .leftMouseUp)
            | eventMask(for: .leftMouseDragged)
            | eventMask(for: .rightMouseDown)
            | eventMask(for: .rightMouseUp)
            | eventMask(for: .rightMouseDragged)
            | eventMask(for: .otherMouseDown)
            | eventMask(for: .otherMouseUp)
            | eventMask(for: .otherMouseDragged)
            | eventMask(for: .scrollWheel)
    }

    private static var keyboardEventMask: CGEventMask {
        eventMask(for: .keyDown)
    }

    private static let mouseEventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }

        let controller = Unmanaged<MouseDiagnosticController>.fromOpaque(userInfo).takeUnretainedValue()
        return controller.handleMouseEventTap(type: type, event: event)
    }

    private static let keyboardEventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }

        let controller = Unmanaged<MouseDiagnosticController>.fromOpaque(userInfo).takeUnretainedValue()
        return controller.handleKeyboardEventTap(type: type, event: event)
    }

    private static func eventMask(for type: CGEventType) -> CGEventMask {
        CGEventMask(1 << type.rawValue)
    }

    private func handleMouseEventTap(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            errorLog("[MouseDiagnostic] mouseEventTapDisabled type=\(name(for: type)); reenable=true")
            if let mouseEventTap {
                CGEvent.tapEnable(tap: mouseEventTap, enable: true)
            }
            return nil

        default:
            routeMouseEvent(type: type, event: event)
            log(event: event, type: type, swallowed: isCaptureActive)
            return isCaptureActive ? nil : Unmanaged.passUnretained(event)
        }
    }

    private func routeMouseEvent(type: CGEventType, event: CGEvent) {
        guard isCaptureActive else {
            return
        }

        switch type {
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            let deltaX = CGFloat(event.getIntegerValueField(.mouseEventDeltaX))
            let deltaY = CGFloat(-event.getIntegerValueField(.mouseEventDeltaY))
            guard deltaX != 0 || deltaY != 0 else {
                return
            }

            onVirtualMouseDelta?(CGPoint(x: deltaX, y: deltaY))

        case .leftMouseDown:
            onVirtualMouseButton?(.left, true)
        case .leftMouseUp:
            onVirtualMouseButton?(.left, false)
        case .rightMouseDown:
            onVirtualMouseButton?(.right, true)
        case .rightMouseUp:
            onVirtualMouseButton?(.right, false)
        case .scrollWheel:
            let delta = CGFloat(event.getIntegerValueField(.scrollWheelEventDeltaAxis1))
            onVirtualScroll?(delta)
        default:
            return
        }
    }

    private func handleKeyboardEventTap(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            errorLog("[MouseDiagnostic] keyboardEventTapDisabled type=\(name(for: type)); reenable=true")
            if let keyboardEventTap {
                CGEvent.tapEnable(tap: keyboardEventTap, enable: true)
            }
            return nil

        case .keyDown:
            handleKeyDown(event)
            return Unmanaged.passUnretained(event)

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleKeyDown(_ event: CGEvent) {
        guard hasCaptureState else {
            resetEscapeSequence()
            return
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard keyCode == Self.escapeKeyCode else {
            resetEscapeSequence()
            return
        }

        let now = ProcessInfo.processInfo.systemUptime
        if let lastEscapePressTime,
           now - lastEscapePressTime > Self.escapeSequenceMaximumGap {
            escapePressCount = 0
        }

        escapePressCount += 1
        lastEscapePressTime = now
        debugLog("[MouseDiagnostic] escapeUnlockProgress count=\(escapePressCount)")

        guard escapePressCount >= Self.escapeUnlockCount else {
            return
        }

        cancelPendingCapture(reason: "escape")
        cancelTemporaryRelease(reason: "escape")
        deactivateCapture(reason: "escape")
    }

    private func resetEscapeSequence() {
        escapePressCount = 0
        lastEscapePressTime = nil
    }

    private func log(event: CGEvent, type: CGEventType, swallowed: Bool) {
        let location = event.location
        let deltaX = event.getIntegerValueField(.mouseEventDeltaX)
        let deltaY = event.getIntegerValueField(.mouseEventDeltaY)
        let button = event.getIntegerValueField(.mouseEventButtonNumber)
        let scrollX = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
        let scrollY = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let timestampSeconds = Double(event.timestamp) / 1_000_000_000
        let eventAgeMilliseconds = max(0, (ProcessInfo.processInfo.systemUptime - timestampSeconds) * 1000)

        debugLog(
            String(
                format: "[MouseDiagnostic] type=%@ swallowed=%@ capture=%@ dx=%lld dy=%lld button=%lld scrollX=%lld scrollY=%lld loc=(%.1f,%.1f) flags=%llu eventAge=%.3fms",
                name(for: type),
                swallowed ? "true" : "false",
                isCaptureActive ? "true" : "false",
                deltaX,
                deltaY,
                button,
                scrollX,
                scrollY,
                location.x,
                location.y,
                event.flags.rawValue,
                eventAgeMilliseconds
            )
        )
    }

    private func name(for type: CGEventType) -> String {
        switch type {
        case .mouseMoved:
            return "mouseMoved"
        case .leftMouseDown:
            return "leftMouseDown"
        case .leftMouseUp:
            return "leftMouseUp"
        case .leftMouseDragged:
            return "leftMouseDragged"
        case .rightMouseDown:
            return "rightMouseDown"
        case .rightMouseUp:
            return "rightMouseUp"
        case .rightMouseDragged:
            return "rightMouseDragged"
        case .otherMouseDown:
            return "otherMouseDown"
        case .otherMouseUp:
            return "otherMouseUp"
        case .otherMouseDragged:
            return "otherMouseDragged"
        case .scrollWheel:
            return "scrollWheel"
        case .keyDown:
            return "keyDown"
        case .tapDisabledByTimeout:
            return "tapDisabledByTimeout"
        case .tapDisabledByUserInput:
            return "tapDisabledByUserInput"
        default:
            return "type\(type.rawValue)"
        }
    }
}
