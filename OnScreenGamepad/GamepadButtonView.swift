import Cocoa

final class GamepadButtonView: NSView {

    private final class CenteredLabelView: NSView {
        var stringValue = "" {
            didSet { needsDisplay = true }
        }
        var font: NSFont = .systemFont(ofSize: 11) {
            didSet { needsDisplay = true }
        }

        override var isFlipped: Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)

            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            let attributedLabel = NSAttributedString(
                string: stringValue,
                attributes: [
                    .font: font,
                    .foregroundColor: NSColor.white,
                    .paragraphStyle: paragraphStyle,
                ]
            )
            let measuredSize = attributedLabel.size()
            let drawRect = CGRect(
                x: 2,
                y: max(0, bounds.midY - ceil(measuredSize.height) / 2),
                width: max(0, bounds.width - 4),
                height: ceil(measuredSize.height)
            )
            attributedLabel.draw(in: drawRect)
        }
    }

    private enum PressSource {
        case primary
        case secondary
    }

    private final class PressState {
        var pressedBinding: (keyCode: CGKeyCode, modifiers: NSEvent.ModifierFlags)?
        var pressedBindings: [(keyCode: CGKeyCode, modifiers: NSEvent.ModifierFlags)] = []
        var isPressed = false
        var autoReleaseWorkItem: DispatchWorkItem?
        var sequenceRepeatWorkItem: DispatchWorkItem?
    }

    private struct ResolvedInput {
        let bindings: [ButtonKeyBinding]
        let mode: ButtonInteractionMode
        let multiKeyActivationMode: MultiKeyActivationMode
    }

    private enum JoystickDirection: CaseIterable {
        case up
        case upRight
        case right
        case downRight
        case down
        case downLeft
        case left
        case upLeft
    }

    private static let compatibilityTapDuration: TimeInterval = 0.033
    private static let joystickDeadzoneRadius: CGFloat = 18
    private static let joystickIdleReturnDelay: TimeInterval = 0.055
    private static let joystickOuterInsetFraction: CGFloat = 0.08
    private static let joystickCardinalDominanceRatio: CGFloat = 1.75
    private static let joystickMinimumDeltaForAxisReset: CGFloat = 0.5
    private static let joystickParkingDeltaTolerance: CGFloat = 1.5
    private static let joystickParkSuppressionWindow: TimeInterval = 0.04

    let button: GamepadButton
    private var config: ButtonConfig
    private var compatibilityModeEnabled: Bool
    private var activeSubProfileID: UUID?
    private let primaryState = PressState()
    private let secondaryState = PressState()
    private let shapeLayer = CAShapeLayer()
    private let joystickOuterLayer = CAShapeLayer()
    private let joystickKnobLayer = CAShapeLayer()
    private let label = CenteredLabelView(frame: .zero)
    private var isSwitchPressed = false
    private var isJoystickCaptured = false
    private var joystickOffset = CGPoint.zero
    private var activeJoystickDirection: JoystickDirection?
    private var activeJoystickBindings: [(keyCode: CGKeyCode, modifiers: NSEvent.ModifierFlags)] = []
    private var joystickLocalMonitor: Any?
    private var joystickGlobalMonitor: Any?
    private var joystickIdleReturnWorkItem: DispatchWorkItem?
    private var pendingJoystickParkDelta: CGPoint?
    private var pendingJoystickParkEventDeadline: TimeInterval = 0
    private var isJoystickCursorHidden = false
    private var trackingArea: NSTrackingArea?
    var onJoystickCaptureChanged: ((Bool) -> Void)?

    init(button: GamepadButton, config: ButtonConfig, compatibilityModeEnabled: Bool, activeSubProfileID: UUID?) {
        self.button = button
        self.config = config
        self.compatibilityModeEnabled = compatibilityModeEnabled
        self.activeSubProfileID = activeSubProfileID
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        wantsLayer = true
        layer?.masksToBounds = false
        shapeLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        layer?.addSublayer(shapeLayer)
        joystickOuterLayer.contentsScale = shapeLayer.contentsScale
        joystickKnobLayer.contentsScale = shapeLayer.contentsScale
        layer?.addSublayer(joystickOuterLayer)
        layer?.addSublayer(joystickKnobLayer)

        label.stringValue = config.resolvedDisplayLabel
        label.font = config.resolvedLabelFont
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        updateAppearance(animated: false)
        NSLog("[Button \(button.rawValue)] Created frame will be set by parent, keyBindings=\(config.keyBindings.map(\.keyCode))")
    }

    override func layout() {
        super.layout()
        updateShapePath()
    }

    func updateConfig(_ newConfig: ButtonConfig, compatibilityModeEnabled: Bool, activeSubProfileID: UUID?) {
        releaseIfNeeded()
        config = newConfig
        self.compatibilityModeEnabled = compatibilityModeEnabled
        self.activeSubProfileID = activeSubProfileID
        label.stringValue = config.resolvedDisplayLabel
        label.font = config.resolvedLabelFont
        updateAppearance(animated: false)
    }

    func releaseIfNeeded() {
        releaseJoystickCapture(warpCursorToCenter: false)

        if isSubProfileSwitch {
            isSwitchPressed = false
            updateAppearance(animated: false)
            return
        }

        releaseState(primaryState)
        releaseState(secondaryState)
        updateAppearance(animated: false)
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        NSLog("[Button \(button.rawValue)] acceptsFirstMouse called -> true")
        return true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard containsAnyInteractivePointCandidate(point) else {
            return nil
        }

        return self
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }

    override func mouseDown(with event: NSEvent) {
        guard containsInteractivePoint(convert(event.locationInWindow, from: nil)) else {
            return
        }

        NSLog("[Button \(button.rawValue)] mouseDown")
        if config.type == .joystick {
            beginJoystickCapture(with: event)
            return
        }

        if isSubProfileSwitch {
            handleSubProfileSwitchPressStarted()
            return
        }

        handlePressStarted(source: .primary)
    }

    override func mouseUp(with event: NSEvent) {
        NSLog("[Button \(button.rawValue)] mouseUp")
        if config.type == .joystick {
            return
        }

        if isSubProfileSwitch {
            handleSubProfileSwitchPressEnded(inside: containsInteractivePoint(convert(event.locationInWindow, from: nil)))
            return
        }

        handlePressEnded(source: .primary)
    }

    override func rightMouseDown(with event: NSEvent) {
        if config.type == .joystick {
            if isJoystickCaptured {
                releaseJoystickCapture(warpCursorToCenter: true)
            }
            return
        }

        guard containsInteractivePoint(convert(event.locationInWindow, from: nil)), !isSubProfileSwitch else {
            return
        }

        NSLog("[Button \(button.rawValue)] rightMouseDown")
        handlePressStarted(source: .secondary)
    }

    override func rightMouseUp(with event: NSEvent) {
        if config.type == .joystick {
            return
        }

        guard !isSubProfileSwitch else {
            return
        }

        NSLog("[Button \(button.rawValue)] rightMouseUp")
        handlePressEnded(source: .secondary)
    }

    override func mouseDragged(with event: NSEvent) {
        if config.type == .joystick {
            return
        }

        if isSubProfileSwitch {
            let inside = containsInteractivePoint(convert(event.locationInWindow, from: nil))
            if inside != isSwitchPressed {
                isSwitchPressed = inside
                updateAppearance(animated: true)
            }
            return
        }

        handleDrag(source: .primary, event: event)
    }

    override func rightMouseDragged(with event: NSEvent) {
        if config.type == .joystick, isJoystickCaptured {
            releaseJoystickCapture(warpCursorToCenter: true)
            return
        }

        guard !isSubProfileSwitch else {
            return
        }

        handleDrag(source: .secondary, event: event)
    }

    override func mouseExited(with event: NSEvent) {
        NSLog("[Button \(button.rawValue)] mouseExited")
        if config.type == .joystick {
            return
        }

        if isSubProfileSwitch {
            if isSwitchPressed {
                isSwitchPressed = false
                updateAppearance(animated: true)
            }
            return
        }

        releaseMomentaryOnExit(source: .primary)
        releaseMomentaryOnExit(source: .secondary)
    }

    override func mouseMoved(with event: NSEvent) {
        guard config.type != .joystick else { return }
    }

    private var isSubProfileSwitch: Bool {
        config.action.targetSubProfileID != nil
    }

    private var isCurrentSubProfileSwitch: Bool {
        guard let targetID = config.action.targetSubProfileID else {
            return false
        }

        return targetID == activeSubProfileID
    }

    private var isVisuallyPressed: Bool {
        isSwitchPressed || primaryState.isPressed || secondaryState.isPressed || isJoystickCaptured
    }

    private var isJoystick: Bool {
        config.type == .joystick
    }

    private func handleSubProfileSwitchPressStarted() {
        guard !isCurrentSubProfileSwitch else {
            return
        }

        isSwitchPressed = true
        updateAppearance(animated: true)
    }

    private func handleSubProfileSwitchPressEnded(inside: Bool) {
        defer {
            if isSwitchPressed {
                isSwitchPressed = false
                updateAppearance(animated: true)
            }
        }

        guard inside, !isCurrentSubProfileSwitch, let targetID = config.action.targetSubProfileID else {
            return
        }

        ProfileStore.shared.setActiveSubProfile(targetID)
    }

    private func beginJoystickCapture(with event: NSEvent) {
        guard !isJoystickCaptured else {
            return
        }

        isJoystickCaptured = true
        joystickOffset = .zero
        activeJoystickDirection = nil
        activeJoystickBindings = []
        pendingJoystickParkDelta = nil
        pendingJoystickParkEventDeadline = 0
        CGAssociateMouseAndMouseCursorPosition(boolean_t(0))
        parkJoystickCursor(suppressingNextDelta: nil, eventTimestamp: event.timestamp)
        hideJoystickCursorIfNeeded()
        installJoystickEventMonitors()
        onJoystickCaptureChanged?(true)
        updateAppearance(animated: true)
        NSLog("[Button \(button.rawValue)] joystickCaptureStarted")
    }

    private func updateJoystickCapture(with event: NSEvent) {
        guard isJoystickCaptured else {
            return
        }

        guard !consumeJoystickParkEventIfNeeded(event) else {
            return
        }

        let movementDelta = CGPoint(x: event.deltaX, y: -event.deltaY)
        joystickOffset = clampedJoystickOffset(joystickOffset(afterApplying: movementDelta))
        parkJoystickCursor(
            suppressingNextDelta: CGPoint(x: -event.deltaX, y: -event.deltaY),
            eventTimestamp: event.timestamp
        )

        let nextDirection = joystickDirection(for: joystickOffset)
        if nextDirection != activeJoystickDirection {
            setActiveJoystickDirection(nextDirection)
        }

        scheduleJoystickIdleReturnIfNeeded()
        updateAppearance(animated: false)
    }

    private func releaseJoystickCapture(warpCursorToCenter: Bool) {
        guard isJoystickCaptured || activeJoystickDirection != nil || !activeJoystickBindings.isEmpty else {
            return
        }

        releaseActiveJoystickBindings()
        activeJoystickDirection = nil
        joystickOffset = .zero
        joystickIdleReturnWorkItem?.cancel()
        joystickIdleReturnWorkItem = nil
        pendingJoystickParkDelta = nil
        pendingJoystickParkEventDeadline = 0

        if isJoystickCaptured {
            isJoystickCaptured = false
            removeJoystickEventMonitors()
            CGAssociateMouseAndMouseCursorPosition(boolean_t(1))
            unhideJoystickCursorIfNeeded()
            if warpCursorToCenter {
                warpCursorToJoystickCenter()
            }
            onJoystickCaptureChanged?(false)
            NSLog("[Button \(button.rawValue)] joystickCaptureEnded")
        }

        updateAppearance(animated: true)
    }

    private func installJoystickEventMonitors() {
        removeJoystickEventMonitors()

        joystickLocalMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDown, .rightMouseDragged]
        ) { [weak self] event in
            guard let self, self.isJoystickCaptured else {
                return event
            }

            switch event.type {
            case .rightMouseDown, .rightMouseDragged:
                self.releaseJoystickCapture(warpCursorToCenter: true)
                return nil
            case .mouseMoved, .leftMouseDragged:
                self.updateJoystickCapture(with: event)
                return nil
            default:
                break
            }

            return event
        }

        joystickGlobalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDown, .rightMouseDragged]
        ) { [weak self] event in
            DispatchQueue.main.async {
                guard let self, self.isJoystickCaptured else {
                    return
                }

                switch event.type {
                case .rightMouseDown, .rightMouseDragged:
                    self.releaseJoystickCapture(warpCursorToCenter: true)
                case .mouseMoved, .leftMouseDragged:
                    self.updateJoystickCapture(with: event)
                default:
                    break
                }
            }
        }
    }

    private func removeJoystickEventMonitors() {
        joystickIdleReturnWorkItem?.cancel()
        joystickIdleReturnWorkItem = nil
        pendingJoystickParkDelta = nil
        pendingJoystickParkEventDeadline = 0

        if let joystickLocalMonitor {
            NSEvent.removeMonitor(joystickLocalMonitor)
            self.joystickLocalMonitor = nil
        }

        if let joystickGlobalMonitor {
            NSEvent.removeMonitor(joystickGlobalMonitor)
            self.joystickGlobalMonitor = nil
        }
    }

    private func hideJoystickCursorIfNeeded() {
        guard !isJoystickCursorHidden else {
            return
        }

        NSCursor.hide()
        isJoystickCursorHidden = true
    }

    private func unhideJoystickCursorIfNeeded() {
        guard isJoystickCursorHidden else {
            return
        }

        NSCursor.unhide()
        isJoystickCursorHidden = false
    }

    private func scheduleJoystickIdleReturnIfNeeded() {
        joystickIdleReturnWorkItem?.cancel()

        guard hypot(joystickOffset.x, joystickOffset.y) > 0.5 else {
            joystickIdleReturnWorkItem = nil
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            self?.returnJoystickToDeadzone()
        }
        joystickIdleReturnWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.joystickIdleReturnDelay, execute: workItem)
    }

    private func returnJoystickToDeadzone() {
        guard isJoystickCaptured else {
            return
        }

        joystickIdleReturnWorkItem = nil
        joystickOffset = .zero
        setActiveJoystickDirection(nil)
        updateAppearance(animated: true)
    }

    private func consumeJoystickParkEventIfNeeded(_ event: NSEvent) -> Bool {
        guard let pendingJoystickParkDelta else {
            return false
        }

        guard event.timestamp <= pendingJoystickParkEventDeadline else {
            self.pendingJoystickParkDelta = nil
            pendingJoystickParkEventDeadline = 0
            return false
        }

        let deltaMatchesPark = abs(event.deltaX - pendingJoystickParkDelta.x) <= Self.joystickParkingDeltaTolerance
            && abs(event.deltaY - pendingJoystickParkDelta.y) <= Self.joystickParkingDeltaTolerance
        guard deltaMatchesPark else {
            self.pendingJoystickParkDelta = nil
            pendingJoystickParkEventDeadline = 0
            return false
        }

        self.pendingJoystickParkDelta = nil
        pendingJoystickParkEventDeadline = 0
        return true
    }

    private func joystickOffset(afterApplying movementDelta: CGPoint) -> CGPoint {
        var nextOffset = CGPoint(
            x: joystickOffset.x + movementDelta.x,
            y: joystickOffset.y + movementDelta.y
        )

        let absoluteX = abs(movementDelta.x)
        let absoluteY = abs(movementDelta.y)
        let minimumDelta = Self.joystickMinimumDeltaForAxisReset

        if absoluteY >= minimumDelta,
           absoluteY >= absoluteX * Self.joystickCardinalDominanceRatio {
            nextOffset.x = 0
        } else if absoluteX >= minimumDelta,
                  absoluteX >= absoluteY * Self.joystickCardinalDominanceRatio {
            nextOffset.y = 0
        }

        return nextOffset
    }

    private func joystickDirection(for offset: CGPoint) -> JoystickDirection? {
        let distance = hypot(offset.x, offset.y)
        let deadzoneRadius = effectiveJoystickDeadzoneRadius
        guard distance >= deadzoneRadius else {
            return nil
        }

        let axisThreshold = deadzoneRadius * 0.55
        let wantsRight = offset.x > axisThreshold
        let wantsLeft = offset.x < -axisThreshold
        let wantsUp = offset.y > axisThreshold
        let wantsDown = offset.y < -axisThreshold

        if wantsUp {
            if wantsRight {
                return .upRight
            }
            if wantsLeft {
                return .upLeft
            }
            return .up
        }

        if wantsDown {
            if wantsRight {
                return .downRight
            }
            if wantsLeft {
                return .downLeft
            }
            return .down
        }

        if wantsRight {
            return .right
        }

        if wantsLeft {
            return .left
        }

        return abs(offset.x) >= abs(offset.y)
            ? (offset.x >= 0 ? .right : .left)
            : (offset.y >= 0 ? .up : .down)
    }

    private func setActiveJoystickDirection(_ direction: JoystickDirection?) {
        releaseActiveJoystickBindings()
        activeJoystickDirection = direction

        guard let direction else {
            return
        }

        activeJoystickBindings = uniqueInputBindings(bindings(for: direction))
        for binding in activeJoystickBindings {
            KeyInjector.shared.pressRaw(binding.keyCode, modifiers: binding.modifiers)
        }
        NSLog("[Button \(button.rawValue)] joystickDirection=\(direction) bindings=\(activeJoystickBindings.map { $0.keyCode })")
    }

    private func releaseActiveJoystickBindings() {
        for binding in activeJoystickBindings.reversed() {
            KeyInjector.shared.releaseRaw(binding.keyCode, modifiers: binding.modifiers)
        }
        activeJoystickBindings = []
    }

    private func bindings(for direction: JoystickDirection) -> [ButtonKeyBinding] {
        switch direction {
        case .up:
            return [config.joystick.up]
        case .upRight:
            return [config.joystick.up, config.joystick.right]
        case .right:
            return [config.joystick.right]
        case .downRight:
            return [config.joystick.down, config.joystick.right]
        case .down:
            return [config.joystick.down]
        case .downLeft:
            return [config.joystick.down, config.joystick.left]
        case .left:
            return [config.joystick.left]
        case .upLeft:
            return [config.joystick.up, config.joystick.left]
        }
    }

    private func warpCursorToJoystickCenter() {
        warpCursor(to: CGPoint(x: bounds.midX, y: bounds.midY))
    }

    private func parkJoystickCursor(suppressingNextDelta delta: CGPoint?, eventTimestamp: TimeInterval) {
        pendingJoystickParkDelta = delta
        pendingJoystickParkEventDeadline = delta == nil ? 0 : eventTimestamp + Self.joystickParkSuppressionWindow
        warpCursorToJoystickCenter()
    }

    private func warpCursor(to localPoint: CGPoint) {
        guard let window, let screen = window.screen else {
            return
        }

        let windowPoint = convert(localPoint, to: nil)
        let screenPoint = window.convertPoint(toScreen: windowPoint)
        let quartzPoint = CGPoint(
            x: screenPoint.x,
            y: screen.frame.maxY - screenPoint.y
        )
        CGWarpMouseCursorPosition(quartzPoint)
    }

    private func handlePressStarted(source: PressSource) {
        guard let input = resolvedInput(for: source) else {
            return
        }

        if input.mode == .turbo {
            toggleTurboRepeat(source: source, input: input)
            return
        }

        if usesSequentialMultiKey(input) {
            if input.mode == .toggleHold {
                toggleSequentialRepeat(source: source, input: input)
                return
            }

            playSequentialBindings(source: source, input: input)
            return
        }

        if usesSimultaneousMultiKey(input) {
            if input.mode == .toggleHold {
                setSimultaneousPressed(!state(for: source).isPressed, source: source, input: input)
                return
            }

            if usesCompatibilityTap(input) {
                setSimultaneousPressed(true, source: source, input: input)
                scheduleCompatibilityRelease(source: source, input: input)
                return
            }

            setSimultaneousPressed(true, source: source, input: input)
            return
        }

        if input.mode == .toggleHold {
            setPressed(!state(for: source).isPressed, source: source, input: input)
            return
        }

        if usesCompatibilityTap(input) {
            setPressed(true, source: source, input: input)
            scheduleCompatibilityRelease(source: source, input: input)
            return
        }

        setPressed(true, source: source, input: input)
    }

    private func handlePressEnded(source: PressSource) {
        guard let input = resolvedInput(for: source) else {
            return
        }

        guard input.mode != .turbo,
              !usesSequentialMultiKey(input),
              input.mode != .toggleHold,
              !usesCompatibilityTap(input) else {
            return
        }

        if usesSimultaneousMultiKey(input) {
            setSimultaneousPressed(false, source: source, input: input)
            return
        }

        setPressed(false, source: source, input: input)
    }

    private func handleDrag(source: PressSource, event: NSEvent) {
        guard let input = resolvedInput(for: source),
              input.mode != .turbo,
              !usesSequentialMultiKey(input),
              input.mode != .toggleHold,
              !usesCompatibilityTap(input) else {
            return
        }

        let inside = containsInteractivePoint(convert(event.locationInWindow, from: nil))
        let state = state(for: source)
        if inside != state.isPressed {
            setCurrentPressed(inside, source: source, input: input)
        }
    }

    private func releaseMomentaryOnExit(source: PressSource) {
        guard let input = resolvedInput(for: source),
              input.mode != .turbo,
              !usesSequentialMultiKey(input),
              input.mode != .toggleHold,
              !usesCompatibilityTap(input),
              state(for: source).isPressed else {
            return
        }

        setCurrentPressed(false, source: source, input: input)
    }

    private func resolvedInput(for source: PressSource) -> ResolvedInput? {
        let primaryBindings = config.keyBindings.isEmpty
            ? [ButtonKeyBinding(keyCode: config.keyCode, keyModifiers: config.keyModifiers)]
            : config.keyBindings

        switch source {
        case .primary:
            return ResolvedInput(
                bindings: primaryBindings,
                mode: config.interactionMode,
                multiKeyActivationMode: config.multiKeyActivationMode
            )
        case .secondary:
            if let rightClickBindings = config.rightClickKeyBindings, !rightClickBindings.isEmpty {
                return ResolvedInput(
                    bindings: rightClickBindings,
                    mode: config.rightClickInteractionMode ?? config.interactionMode,
                    multiKeyActivationMode: config.multiKeyActivationMode
                )
            }

            guard config.rightClickFallsBackToPrimary else {
                return nil
            }

            return ResolvedInput(
                bindings: primaryBindings,
                mode: config.rightClickInteractionMode ?? config.interactionMode,
                multiKeyActivationMode: config.multiKeyActivationMode
            )
        }
    }

    private func state(for source: PressSource) -> PressState {
        switch source {
        case .primary:
            return primaryState
        case .secondary:
            return secondaryState
        }
    }

    private func usesCompatibilityTap(_ input: ResolvedInput) -> Bool {
        compatibilityModeEnabled && input.mode == .momentary
    }

    private func usesSequentialMultiKey(_ input: ResolvedInput) -> Bool {
        input.bindings.count > 1 && input.multiKeyActivationMode == .sequential
    }

    private func usesSimultaneousMultiKey(_ input: ResolvedInput) -> Bool {
        input.bindings.count > 1 && input.multiKeyActivationMode == .simultaneous
    }

    private func scheduleCompatibilityRelease(source: PressSource, input: ResolvedInput) {
        let state = state(for: source)
        state.autoReleaseWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.setCurrentPressed(false, source: source, input: input)
        }
        state.autoReleaseWorkItem = workItem

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.compatibilityTapDuration, execute: workItem)
    }

    private func playSequentialBindings(source: PressSource, input: ResolvedInput) {
        let state = state(for: source)
        state.autoReleaseWorkItem?.cancel()

        state.isPressed = true
        updateAppearance(animated: true)

        NSLog("[Button \(button.rawValue)] playSequential source=\(source) keyBindings=\(input.bindings.map(\.keyCode)) mode=\(input.mode.rawValue) compatibilityMode=\(compatibilityModeEnabled)")
        postSequentialBindings(input)

        let workItem = DispatchWorkItem { [weak self, weak state] in
            state?.isPressed = false
            self?.updateAppearance(animated: true)
            state?.autoReleaseWorkItem = nil
        }
        state.autoReleaseWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.compatibilityTapDuration, execute: workItem)
    }

    private func toggleSequentialRepeat(source: PressSource, input: ResolvedInput) {
        let state = state(for: source)
        if state.sequenceRepeatWorkItem != nil {
            stopSequentialRepeat(source: source)
            return
        }

        state.isPressed = true
        updateAppearance(animated: true)
        NSLog("[Button \(button.rawValue)] startSequentialRepeat source=\(source) keyBindings=\(input.bindings.map(\.keyCode))")
        repeatSequentialBindings(source: source, input: input)
    }

    private func toggleTurboRepeat(source: PressSource, input: ResolvedInput) {
        let state = state(for: source)
        if state.sequenceRepeatWorkItem != nil {
            stopTurboRepeat(source: source)
            return
        }

        state.isPressed = true
        updateAppearance(animated: true)
        NSLog("[Button \(button.rawValue)] startTurboRepeat source=\(source) keyBindings=\(input.bindings.map(\.keyCode)) activationMode=\(input.multiKeyActivationMode.rawValue)")
        repeatTurboActivation(source: source, input: input)
    }

    private func repeatSequentialBindings(source: PressSource, input: ResolvedInput) {
        postSequentialBindings(input)

        var workItem: DispatchWorkItem?
        workItem = DispatchWorkItem { [weak self] in
            guard workItem?.isCancelled == false else {
                return
            }

            self?.repeatSequentialBindings(source: source, input: input)
        }
        if let workItem {
            state(for: source).sequenceRepeatWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.compatibilityTapDuration, execute: workItem)
        }
    }

    private func stopSequentialRepeat(source: PressSource) {
        let state = state(for: source)
        state.sequenceRepeatWorkItem?.cancel()
        state.sequenceRepeatWorkItem = nil
        state.isPressed = false
        updateAppearance(animated: true)
        NSLog("[Button \(button.rawValue)] stopSequentialRepeat source=\(source)")
    }

    private func repeatTurboActivation(source: PressSource, input: ResolvedInput) {
        postTurboActivation(input)

        var workItem: DispatchWorkItem?
        workItem = DispatchWorkItem { [weak self] in
            guard workItem?.isCancelled == false else {
                return
            }

            self?.repeatTurboActivation(source: source, input: input)
        }
        if let workItem {
            state(for: source).sequenceRepeatWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.compatibilityTapDuration, execute: workItem)
        }
    }

    private func stopTurboRepeat(source: PressSource) {
        let state = state(for: source)
        state.sequenceRepeatWorkItem?.cancel()
        state.sequenceRepeatWorkItem = nil
        state.isPressed = false
        updateAppearance(animated: true)
        NSLog("[Button \(button.rawValue)] stopTurboRepeat source=\(source)")
    }

    private func postSequentialBindings(_ input: ResolvedInput) {
        for binding in input.bindings {
            let keyCode = CGKeyCode(binding.keyCode)
            let modifiers = NSEvent.ModifierFlags(rawValue: UInt(binding.keyModifiers))
            KeyInjector.shared.pressRaw(keyCode, modifiers: modifiers)
            KeyInjector.shared.releaseRaw(keyCode, modifiers: modifiers)
        }
    }

    private func postTurboActivation(_ input: ResolvedInput) {
        if usesSimultaneousMultiKey(input) {
            postSimultaneousTap(input)
            return
        }

        if usesSequentialMultiKey(input) {
            postSequentialBindings(input)
            return
        }

        guard let binding = input.bindings.first else {
            return
        }

        let keyCode = CGKeyCode(binding.keyCode)
        let modifiers = NSEvent.ModifierFlags(rawValue: UInt(binding.keyModifiers))
        KeyInjector.shared.pressRaw(keyCode, modifiers: modifiers)
        KeyInjector.shared.releaseRaw(keyCode, modifiers: modifiers)
    }

    private func postSimultaneousTap(_ input: ResolvedInput) {
        let bindings = uniqueInputBindings(input.bindings)

        for binding in bindings {
            KeyInjector.shared.pressRaw(binding.keyCode, modifiers: binding.modifiers)
        }

        for binding in bindings.reversed() {
            KeyInjector.shared.releaseRaw(binding.keyCode, modifiers: binding.modifiers)
        }
    }

    private func setPressed(_ pressed: Bool, source: PressSource, input: ResolvedInput) {
        let state = state(for: source)
        guard pressed != state.isPressed, let binding = input.bindings.first else { return }
        state.isPressed = pressed
        let keyCode = CGKeyCode(binding.keyCode)
        let modifiers = NSEvent.ModifierFlags(rawValue: UInt(binding.keyModifiers))
        NSLog("[Button \(button.rawValue)] setPressed=\(pressed) source=\(source) keyCode=\(keyCode) modifiers=\(binding.keyModifiers) mode=\(input.mode.rawValue) compatibilityMode=\(compatibilityModeEnabled)")
        if pressed {
            state.pressedBinding = (keyCode: keyCode, modifiers: modifiers)
            KeyInjector.shared.pressRaw(keyCode, modifiers: modifiers)
        } else {
            let bindingToRelease = state.pressedBinding ?? (keyCode: keyCode, modifiers: modifiers)
            KeyInjector.shared.releaseRaw(bindingToRelease.keyCode, modifiers: bindingToRelease.modifiers)
            state.pressedBinding = nil
            state.autoReleaseWorkItem?.cancel()
            state.autoReleaseWorkItem = nil
        }
        updateAppearance(animated: true)
    }

    private func setCurrentPressed(_ pressed: Bool, source: PressSource, input: ResolvedInput) {
        if usesSimultaneousMultiKey(input) {
            setSimultaneousPressed(pressed, source: source, input: input)
        } else {
            setPressed(pressed, source: source, input: input)
        }
    }

    private func setSimultaneousPressed(_ pressed: Bool, source: PressSource, input: ResolvedInput) {
        let state = state(for: source)
        guard pressed != state.isPressed else { return }
        state.isPressed = pressed
        NSLog("[Button \(button.rawValue)] setSimultaneousPressed=\(pressed) source=\(source) keyBindings=\(input.bindings.map(\.keyCode)) mode=\(input.mode.rawValue) compatibilityMode=\(compatibilityModeEnabled)")

        if pressed {
            state.pressedBindings = uniqueInputBindings(input.bindings)

            for binding in state.pressedBindings {
                KeyInjector.shared.pressRaw(binding.keyCode, modifiers: binding.modifiers)
            }
        } else {
            releasePressedBindings(state)
        }

        updateAppearance(animated: true)
    }

    private func releaseState(_ state: PressState) {
        state.autoReleaseWorkItem?.cancel()
        state.autoReleaseWorkItem = nil
        state.sequenceRepeatWorkItem?.cancel()
        state.sequenceRepeatWorkItem = nil

        if let pressedBinding = state.pressedBinding {
            KeyInjector.shared.releaseRaw(pressedBinding.keyCode, modifiers: pressedBinding.modifiers)
            state.pressedBinding = nil
        }

        releasePressedBindings(state)
        state.isPressed = false
    }

    private func releasePressedBindings(_ state: PressState) {
        for binding in state.pressedBindings.reversed() {
            KeyInjector.shared.releaseRaw(binding.keyCode, modifiers: binding.modifiers)
        }

        state.pressedBindings = []
        state.autoReleaseWorkItem?.cancel()
        state.autoReleaseWorkItem = nil
        state.isPressed = false
    }

    private func uniqueInputBindings(_ bindings: [ButtonKeyBinding]) -> [(keyCode: CGKeyCode, modifiers: NSEvent.ModifierFlags)] {
        var seenBindings = Set<ButtonKeyBinding>()
        return bindings.compactMap { binding in
            guard seenBindings.insert(binding).inserted else {
                return nil
            }

            return (
                keyCode: CGKeyCode(binding.keyCode),
                modifiers: NSEvent.ModifierFlags(rawValue: UInt(binding.keyModifiers))
            )
        }
    }

    deinit {
        releaseIfNeeded()
    }

    private func updateAppearance(animated: Bool) {
        let base = NSColor(hex: config.colorHex)
        let defaultAlpha = isCurrentSubProfileSwitch ? 0.32 : 0.75
        let target = isVisuallyPressed ? base.withAlphaComponent(1.0) : base.withAlphaComponent(defaultAlpha)
        let scale: CGFloat = isVisuallyPressed ? 0.92 : 1.0
        updateShapePath()
        updateJoystickLayers(baseColor: base)
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.05
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                shapeLayer.fillColor = target.cgColor
                layer?.transform = CATransform3DMakeScale(scale, scale, 1)
            }
        } else {
            shapeLayer.fillColor = target.cgColor
            layer?.transform = CATransform3DMakeScale(scale, scale, 1)
        }
    }

    private func updateShapePath() {
        shapeLayer.frame = bounds
        shapeLayer.path = buttonPath(in: bounds)
    }

    private func updateJoystickLayers(baseColor: NSColor) {
        let showsJoystick = isJoystick
        label.isHidden = showsJoystick
        joystickOuterLayer.isHidden = !showsJoystick
        joystickKnobLayer.isHidden = !showsJoystick
        shapeLayer.isHidden = showsJoystick

        guard showsJoystick else {
            return
        }

        let outerRect = joystickOuterRect
        joystickOuterLayer.frame = bounds
        joystickOuterLayer.path = CGPath(roundedRect: outerRect, cornerWidth: 8, cornerHeight: 8, transform: nil)
        joystickOuterLayer.fillColor = baseColor.withAlphaComponent(isJoystickCaptured ? 0.42 : 0.26).cgColor
        joystickOuterLayer.strokeColor = NSColor.white.withAlphaComponent(isJoystickCaptured ? 0.65 : 0.32).cgColor
        joystickOuterLayer.lineWidth = 2

        let knobDiameter = joystickKnobDiameter
        let clampedOffset = clampedJoystickOffset(joystickOffset)
        let knobRect = CGRect(
            x: bounds.midX + clampedOffset.x - knobDiameter / 2,
            y: bounds.midY + clampedOffset.y - knobDiameter / 2,
            width: knobDiameter,
            height: knobDiameter
        )
        joystickKnobLayer.frame = bounds
        joystickKnobLayer.path = CGPath(ellipseIn: knobRect, transform: nil)
        joystickKnobLayer.fillColor = baseColor.withAlphaComponent(isJoystickCaptured ? 0.95 : 0.72).cgColor
        joystickKnobLayer.strokeColor = NSColor.white.withAlphaComponent(0.78).cgColor
        joystickKnobLayer.lineWidth = 1
    }

    private func clampedJoystickOffset(_ offset: CGPoint) -> CGPoint {
        let travelLimits = joystickTravelLimits
        return CGPoint(
            x: min(max(offset.x, -travelLimits.width), travelLimits.width),
            y: min(max(offset.y, -travelLimits.height), travelLimits.height)
        )
    }

    private var joystickOuterRect: CGRect {
        let inset = max(4, min(bounds.width, bounds.height) * Self.joystickOuterInsetFraction)
        return bounds.insetBy(dx: inset, dy: inset)
    }

    private var joystickKnobDiameter: CGFloat {
        max(18, min(bounds.width, bounds.height) * 0.26)
    }

    private var joystickTravelLimits: CGSize {
        let outerRect = joystickOuterRect
        let knobRadius = joystickKnobDiameter / 2
        return CGSize(
            width: max(0, outerRect.width / 2 - knobRadius),
            height: max(0, outerRect.height / 2 - knobRadius)
        )
    }

    private var effectiveJoystickDeadzoneRadius: CGFloat {
        let shortestTravel = min(joystickTravelLimits.width, joystickTravelLimits.height)
        guard shortestTravel > 0 else {
            return Self.joystickDeadzoneRadius
        }

        return min(Self.joystickDeadzoneRadius, max(8, shortestTravel * 0.45))
    }

    private func buttonPath(in rect: CGRect) -> CGPath {
        switch config.shape {
        case .roundedRectangle:
            return CGPath(roundedRect: rect, cornerWidth: 8, cornerHeight: 8, transform: nil)
        case .oval:
            return CGPath(ellipseIn: rect, transform: nil)
        }
    }

    private func containsInteractivePoint(_ point: CGPoint) -> Bool {
        guard bounds.contains(point) else {
            return false
        }

        if isJoystick {
            return joystickOuterRect.contains(point)
        }

        switch config.shape {
        case .roundedRectangle:
            return true
        case .oval:
            guard bounds.width > 0, bounds.height > 0 else {
                return false
            }

            let normalizedX = (point.x - bounds.midX) / (bounds.width / 2)
            let normalizedY = (point.y - bounds.midY) / (bounds.height / 2)
            return (normalizedX * normalizedX) + (normalizedY * normalizedY) <= 1
        }
    }

    private func containsAnyInteractivePointCandidate(_ point: CGPoint) -> Bool {
        if containsInteractivePoint(point) {
            return true
        }

        guard let superview else {
            return false
        }

        return containsInteractivePoint(convert(point, from: superview))
    }
}
