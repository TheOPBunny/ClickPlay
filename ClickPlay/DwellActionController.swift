import Cocoa

/// Runs one global mouse dwell action at a time and keeps the visual timer out of the gamepad event path.
final class DwellActionController {
    private final class ProgressView: NSView {
        var progress: CGFloat = 0 {
            didSet { needsDisplay = true }
        }

        override var isFlipped: Bool { true }

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)

            let trackRect = bounds.insetBy(dx: 0, dy: 2)
            let trackPath = NSBezierPath(roundedRect: trackRect, xRadius: 1.5, yRadius: 1.5)
            NSColor(calibratedWhite: 0.82, alpha: 0.92).setFill()
            trackPath.fill()

            let fillWidth = max(0, min(trackRect.width, trackRect.width * progress))
            guard fillWidth > 0 else {
                return
            }

            let fillRect = CGRect(
                x: trackRect.minX,
                y: trackRect.minY,
                width: fillWidth,
                height: trackRect.height
            )
            let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: 1.5, yRadius: 1.5)
            NSColor.systemBlue.withAlphaComponent(0.95).setFill()
            fillPath.fill()
        }
    }

    private final class ProgressWindow: NSPanel {
        private static let size = CGSize(width: 64, height: 10)
        private let progressView = ProgressView(frame: NSRect(origin: .zero, size: size))

        init() {
            super.init(
                contentRect: NSRect(origin: .zero, size: Self.size),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            isOpaque = false
            backgroundColor = .clear
            hasShadow = false
            ignoresMouseEvents = true
            level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
            collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            contentView = progressView
        }

        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }

        func show(progress: CGFloat, underCursorAt point: CGPoint) {
            progressView.progress = progress
            let origin = CGPoint(
                x: point.x - Self.size.width / 2,
                y: point.y - 26
            )
            setFrame(NSRect(origin: origin, size: Self.size), display: true)
            orderFrontRegardless()
        }

        func hide() {
            orderOut(nil)
            progressView.progress = 0
        }
    }

    private struct ActiveAction {
        var button: GamepadButton
        var config: DwellActionConfig
    }

    fileprivate enum HeldMouseButton: Equatable {
        case left
        case right
        case middle
    }

    private var activeAction: ActiveAction?
    private var heldMouseButton: HeldMouseButton?
    private var timer: Timer?
    private var anchorPoint: CGPoint?
    private var timerStartedAt: TimeInterval?
    private var movementReferencePoint: CGPoint?
    private var isWaitingForMovement = true
    private let progressWindow = ProgressWindow()

    var onActiveButtonChanged: ((GamepadButton?) -> Void)?

    var activeButton: GamepadButton? {
        activeAction?.button
    }

    @discardableResult
    func toggle(button: GamepadButton, config: DwellActionConfig, currentMouseLocation: CGPoint) -> Bool {
        if activeAction?.button == button {
            deactivate()
            return false
        }

        activate(button: button, config: config, currentMouseLocation: currentMouseLocation)
        return true
    }

    func updateActiveConfig(_ config: DwellActionConfig, for button: GamepadButton) {
        guard activeAction?.button == button else {
            return
        }

        activeAction?.config = config
    }

    func deactivate() {
        guard activeAction != nil || heldMouseButton != nil else {
            return
        }

        stopTimer()
        releaseHeldMouseButtonIfNeeded()
        let previousButton = activeAction?.button
        activeAction = nil
        anchorPoint = nil
        movementReferencePoint = nil
        timerStartedAt = nil
        isWaitingForMovement = true
        progressWindow.hide()

        if previousButton != nil {
            onActiveButtonChanged?(nil)
        }
    }

    func noteMouseLocation(_ point: CGPoint) {
        guard let activeAction else {
            return
        }

        if movementReferencePoint == nil {
            movementReferencePoint = point
        }

        if isWaitingForMovement {
            let referencePoint = movementReferencePoint ?? point
            guard distance(from: referencePoint, to: point) > activeAction.config.movementTolerance else {
                return
            }

            startTimer(anchor: point)
            return
        }

        guard let anchorPoint else {
            startTimer(anchor: point)
            return
        }

        if distance(from: anchorPoint, to: point) > activeAction.config.movementTolerance {
            startTimer(anchor: point)
        } else {
            updateProgress(at: point)
        }
    }

    private func activate(button: GamepadButton, config: DwellActionConfig, currentMouseLocation: CGPoint) {
        if activeAction?.button != button {
            releaseHeldMouseButtonIfNeeded()
        }

        stopTimer()
        activeAction = ActiveAction(button: button, config: config)
        anchorPoint = nil
        timerStartedAt = nil
        movementReferencePoint = currentMouseLocation
        isWaitingForMovement = true
        progressWindow.hide()
        onActiveButtonChanged?(button)
    }

    private func startTimer(anchor point: CGPoint) {
        stopTimer()
        anchorPoint = point
        movementReferencePoint = point
        timerStartedAt = ProcessInfo.processInfo.systemUptime
        isWaitingForMovement = false
        updateProgress(at: point)

        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        progressWindow.hide()
    }

    private func tick() {
        guard let activeAction, let anchorPoint, let timerStartedAt else {
            stopTimer()
            return
        }

        let currentPoint = NSEvent.mouseLocation
        if distance(from: anchorPoint, to: currentPoint) > activeAction.config.movementTolerance {
            startTimer(anchor: currentPoint)
            return
        }

        let elapsed = ProcessInfo.processInfo.systemUptime - timerStartedAt
        let duration = max(0.1, activeAction.config.timerDuration)
        updateProgress(at: currentPoint, elapsed: elapsed, duration: duration)

        guard elapsed >= duration else {
            return
        }

        perform(action: activeAction.config.kind, at: currentPoint)
        stopTimer()
        self.anchorPoint = nil
        self.timerStartedAt = nil
        movementReferencePoint = currentPoint
        isWaitingForMovement = true
    }

    private func updateProgress(at point: CGPoint) {
        guard let timerStartedAt, let activeAction else {
            return
        }

        let elapsed = ProcessInfo.processInfo.systemUptime - timerStartedAt
        updateProgress(
            at: point,
            elapsed: elapsed,
            duration: max(0.1, activeAction.config.timerDuration)
        )
    }

    private func updateProgress(at point: CGPoint, elapsed: TimeInterval, duration: TimeInterval) {
        let progress = CGFloat(min(max(elapsed / duration, 0), 1))
        progressWindow.show(progress: progress, underCursorAt: point)
    }

    private func perform(action: DwellActionKind, at point: CGPoint) {
        switch action {
        case .leftClick:
            MouseEventInjector.shared.click(.left, at: point)
        case .rightClick:
            MouseEventInjector.shared.click(.right, at: point)
        case .middleClick:
            MouseEventInjector.shared.click(.middle, at: point)
        case .holdLeftClick:
            toggleHold(.left, at: point)
        case .holdRightClick:
            toggleHold(.right, at: point)
        case .holdMiddleClick:
            toggleHold(.middle, at: point)
        case .scrollUp:
            MouseEventInjector.shared.scroll(lines: 5, at: point)
        case .scrollDown:
            MouseEventInjector.shared.scroll(lines: -5, at: point)
        }
    }

    private func toggleHold(_ button: HeldMouseButton, at point: CGPoint) {
        if heldMouseButton == button {
            MouseEventInjector.shared.mouseUp(button, at: point)
            heldMouseButton = nil
            return
        }

        releaseHeldMouseButtonIfNeeded()
        MouseEventInjector.shared.mouseDown(button, at: point)
        heldMouseButton = button
    }

    private func releaseHeldMouseButtonIfNeeded() {
        guard let heldMouseButton else {
            return
        }

        MouseEventInjector.shared.mouseUp(heldMouseButton, at: NSEvent.mouseLocation)
        self.heldMouseButton = nil
    }

    private func distance(from first: CGPoint, to second: CGPoint) -> CGFloat {
        hypot(first.x - second.x, first.y - second.y)
    }
}

private final class MouseEventInjector {
    static let shared = MouseEventInjector()

    private init() {}

    func click(_ button: DwellActionController.HeldMouseButton, at point: CGPoint) {
        mouseDown(button, at: point)
        mouseUp(button, at: point)
    }

    func mouseDown(_ button: DwellActionController.HeldMouseButton, at point: CGPoint) {
        postMouse(button: button, down: true, at: point)
    }

    func mouseUp(_ button: DwellActionController.HeldMouseButton, at point: CGPoint) {
        postMouse(button: button, down: false, at: point)
    }

    func scroll(lines: Int32, at point: CGPoint) {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let event = CGEvent(
                scrollWheelEvent2Source: source,
                units: .line,
                wheelCount: 1,
                wheel1: lines,
                wheel2: 0,
                wheel3: 0
              ) else {
            errorLog("[MouseEventInjector] ERROR: scroll event creation failed")
            return
        }

        event.location = point
        event.post(tap: .cghidEventTap)
    }

    private func postMouse(button: DwellActionController.HeldMouseButton, down: Bool, at point: CGPoint) {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let event = CGEvent(
                mouseEventSource: source,
                mouseType: eventType(for: button, down: down),
                mouseCursorPosition: point,
                mouseButton: cgButton(for: button)
              ) else {
            errorLog("[MouseEventInjector] ERROR: mouse event creation failed")
            return
        }

        event.post(tap: .cghidEventTap)
    }

    private func eventType(for button: DwellActionController.HeldMouseButton, down: Bool) -> CGEventType {
        switch button {
        case .left:
            return down ? .leftMouseDown : .leftMouseUp
        case .right:
            return down ? .rightMouseDown : .rightMouseUp
        case .middle:
            return down ? .otherMouseDown : .otherMouseUp
        }
    }

    private func cgButton(for button: DwellActionController.HeldMouseButton) -> CGMouseButton {
        switch button {
        case .left:
            return .left
        case .right:
            return .right
        case .middle:
            return .center
        }
    }
}
