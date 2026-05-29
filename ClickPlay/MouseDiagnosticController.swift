import Cocoa

/// Passive mouse-event visibility diagnostic for testing whether target apps expose input through Quartz event taps.
final class MouseDiagnosticController {
    static let shared = MouseDiagnosticController()

    static let stateDidChange = Notification.Name("MouseDiagnosticControllerStateDidChange")

    private(set) var isEnabled = false
    private var eventTap: CFMachPort?
    private var eventTapRunLoopSource: CFRunLoopSource?

    private init() {}

    deinit {
        stop()
    }

    @discardableResult
    func setEnabled(_ enabled: Bool) -> Bool {
        if enabled {
            return start()
        }

        stop()
        return true
    }

    @discardableResult
    func toggle() -> Bool {
        setEnabled(!isEnabled)
    }

    @discardableResult
    private func start() -> Bool {
        guard !isEnabled else {
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
        isEnabled = true
        debugLog("[MouseDiagnostic] enabled")
        NotificationCenter.default.post(name: Self.stateDidChange, object: self)
        return true
    }

    private func stop() {
        guard isEnabled || eventTap != nil || eventTapRunLoopSource != nil else {
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

        isEnabled = false
        debugLog("[MouseDiagnostic] disabled")
        NotificationCenter.default.post(name: Self.stateDidChange, object: self)
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

        default:
            log(event: event, type: type)
            return Unmanaged.passUnretained(event)
        }
    }

    private func log(event: CGEvent, type: CGEventType) {
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
                format: "[MouseDiagnostic] type=%@ dx=%lld dy=%lld button=%lld scrollX=%lld scrollY=%lld loc=(%.1f,%.1f) flags=%llu eventAge=%.3fms",
                name(for: type),
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
