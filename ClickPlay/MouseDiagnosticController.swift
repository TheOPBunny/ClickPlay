import Cocoa

/// Passive mouse-event visibility diagnostic for testing whether target apps expose input through Quartz event taps.
final class MouseDiagnosticController {
    static let shared = MouseDiagnosticController()

    static let stateDidChange = Notification.Name("MouseDiagnosticControllerStateDidChange")
    private static let captureTestStartDelay: TimeInterval = 10
    private static let captureTestTimeout: TimeInterval = 180

    /// Passive logging requested by the status-menu diagnostic toggle.
    private(set) var isEnabled = false
    private(set) var isCaptureTestPending = false
    private(set) var isCaptureTestEnabled = false
    private var eventTap: CFMachPort?
    private var eventTapRunLoopSource: CFRunLoopSource?
    private var captureTestStartTimer: Timer?
    private var captureTestTimer: Timer?

    private init() {}

    deinit {
        stopCaptureTest(reason: "deinit")
        cancelPendingCaptureTest(reason: "deinit")
        setEnabled(false)
    }

    @discardableResult
    func setEnabled(_ enabled: Bool) -> Bool {
        if enabled {
            guard installEventTapIfNeeded() else {
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
        uninstallEventTapIfIdle()
        NotificationCenter.default.post(name: Self.stateDidChange, object: self)
        return true
    }

    @discardableResult
    func toggle() -> Bool {
        setEnabled(!isEnabled)
    }

    @discardableResult
    func setCaptureTestEnabled(_ enabled: Bool) -> Bool {
        if enabled {
            return armCaptureTest()
        }

        cancelPendingCaptureTest(reason: "manual")
        stopCaptureTest(reason: "manual")
        return true
    }

    @discardableResult
    func toggleCaptureTest() -> Bool {
        setCaptureTestEnabled(!isCaptureTestPending && !isCaptureTestEnabled)
    }

    @discardableResult
    private func installEventTapIfNeeded() -> Bool {
        guard eventTap == nil else {
            return true
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: Self.eventMask,
            callback: Self.eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            errorLog("[MouseDiagnostic] ERROR: eventTapCreationFailed")
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        eventTapRunLoopSource = source
        debugLog("[MouseDiagnostic] eventTapInstalled")
        return true
    }

    private func uninstallEventTapIfIdle() {
        guard !isEnabled, !isCaptureTestEnabled else {
            return
        }

        uninstallEventTap()
    }

    private func uninstallEventTap() {
        guard eventTap != nil || eventTapRunLoopSource != nil else {
            return
        }

        if let eventTapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapRunLoopSource, .commonModes)
            self.eventTapRunLoopSource = nil
        }

        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            self.eventTap = nil
        }

        debugLog("[MouseDiagnostic] eventTapUninstalled")
    }

    @discardableResult
    private func armCaptureTest() -> Bool {
        guard !isCaptureTestEnabled else {
            return true
        }

        guard !isCaptureTestPending else {
            return true
        }

        isCaptureTestPending = true
        scheduleCaptureTestStart()
        debugLog("[MouseDiagnostic] captureTestArmed delaySeconds=\(Self.captureTestStartDelay)")
        NotificationCenter.default.post(name: Self.stateDidChange, object: self)
        return true
    }

    private func cancelPendingCaptureTest(reason: String) {
        guard isCaptureTestPending else {
            captureTestStartTimer?.invalidate()
            captureTestStartTimer = nil
            return
        }

        captureTestStartTimer?.invalidate()
        captureTestStartTimer = nil
        isCaptureTestPending = false
        debugLog("[MouseDiagnostic] captureTestDisarmed reason=\(reason)")
        NotificationCenter.default.post(name: Self.stateDidChange, object: self)
    }

    private func scheduleCaptureTestStart() {
        captureTestStartTimer?.invalidate()
        let timer = Timer(timeInterval: Self.captureTestStartDelay, repeats: false) { [weak self] _ in
            guard let self, self.isCaptureTestPending else {
                return
            }

            self.captureTestStartTimer = nil
            self.isCaptureTestPending = false
            _ = self.startCaptureTest()
        }
        RunLoop.main.add(timer, forMode: .common)
        captureTestStartTimer = timer
    }

    @discardableResult
    private func startCaptureTest() -> Bool {
        guard !isCaptureTestEnabled else {
            return true
        }

        guard installEventTapIfNeeded() else {
            NotificationCenter.default.post(name: Self.stateDidChange, object: self)
            return false
        }

        isCaptureTestEnabled = true
        scheduleCaptureTestTimeout()
        debugLog("[MouseDiagnostic] captureTestEnabled timeoutSeconds=\(Self.captureTestTimeout)")
        NotificationCenter.default.post(name: Self.stateDidChange, object: self)
        return true
    }

    private func stopCaptureTest(reason: String) {
        guard isCaptureTestEnabled else {
            captureTestTimer?.invalidate()
            captureTestTimer = nil
            return
        }

        captureTestTimer?.invalidate()
        captureTestTimer = nil
        isCaptureTestEnabled = false
        debugLog("[MouseDiagnostic] captureTestDisabled reason=\(reason)")
        uninstallEventTapIfIdle()
        NotificationCenter.default.post(name: Self.stateDidChange, object: self)
    }

    private func scheduleCaptureTestTimeout() {
        captureTestTimer?.invalidate()
        let timer = Timer(timeInterval: Self.captureTestTimeout, repeats: false) { [weak self] _ in
            guard let self, self.isCaptureTestEnabled else {
                return
            }

            errorLog("[MouseDiagnostic] captureTestWatchdogReleased timeoutSeconds=\(Self.captureTestTimeout)")
            self.stopCaptureTest(reason: "watchdogTimeout")
        }
        RunLoop.main.add(timer, forMode: .common)
        captureTestTimer = timer
    }

    private static var eventMask: CGEventMask {
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

    private static let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }

        let controller = Unmanaged<MouseDiagnosticController>.fromOpaque(userInfo).takeUnretainedValue()
        return controller.handleEventTap(type: type, event: event)
    }

    private static func eventMask(for type: CGEventType) -> CGEventMask {
        CGEventMask(1 << type.rawValue)
    }

    private func handleEventTap(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            errorLog("[MouseDiagnostic] eventTapDisabled type=\(name(for: type)); reenable=true")
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return nil

        case .rightMouseDown, .rightMouseUp, .rightMouseDragged:
            guard isCaptureTestEnabled else {
                log(event: event, type: type, swallowed: false)
                return Unmanaged.passUnretained(event)
            }

            log(event: event, type: type, swallowed: true)
            if type == .rightMouseUp {
                stopCaptureTest(reason: "rightClick")
            }
            return nil

        default:
            log(event: event, type: type, swallowed: isCaptureTestEnabled)
            if isCaptureTestEnabled {
                return nil
            }

            return Unmanaged.passUnretained(event)
        }
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
                format: "[MouseDiagnostic] type=%@ swallowed=%@ captureTest=%@ dx=%lld dy=%lld button=%lld scrollX=%lld scrollY=%lld loc=(%.1f,%.1f) flags=%llu eventAge=%.3fms",
                name(for: type),
                swallowed ? "true" : "false",
                isCaptureTestEnabled ? "true" : "false",
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
        case .tapDisabledByTimeout:
            return "tapDisabledByTimeout"
        case .tapDisabledByUserInput:
            return "tapDisabledByUserInput"
        default:
            return "type\(type.rawValue)"
        }
    }
}
