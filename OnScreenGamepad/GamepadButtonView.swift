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

    private static let compatibilityTapDuration: TimeInterval = 0.033

    let button: GamepadButton
    private var config: ButtonConfig
    private var compatibilityModeEnabled: Bool
    private var activeSubProfileID: UUID?
    private let primaryState = PressState()
    private let secondaryState = PressState()
    private let shapeLayer = CAShapeLayer()
    private let label = CenteredLabelView(frame: .zero)
    private var isSwitchPressed = false
    private var trackingArea: NSTrackingArea?

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
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
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
        if isSubProfileSwitch {
            handleSubProfileSwitchPressStarted()
            return
        }

        handlePressStarted(source: .primary)
    }

    override func mouseUp(with event: NSEvent) {
        NSLog("[Button \(button.rawValue)] mouseUp")
        if isSubProfileSwitch {
            handleSubProfileSwitchPressEnded(inside: containsInteractivePoint(convert(event.locationInWindow, from: nil)))
            return
        }

        handlePressEnded(source: .primary)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard containsInteractivePoint(convert(event.locationInWindow, from: nil)), !isSubProfileSwitch else {
            return
        }

        NSLog("[Button \(button.rawValue)] rightMouseDown")
        handlePressStarted(source: .secondary)
    }

    override func rightMouseUp(with event: NSEvent) {
        guard !isSubProfileSwitch else {
            return
        }

        NSLog("[Button \(button.rawValue)] rightMouseUp")
        handlePressEnded(source: .secondary)
    }

    override func mouseDragged(with event: NSEvent) {
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
        guard !isSubProfileSwitch else {
            return
        }

        handleDrag(source: .secondary, event: event)
    }

    override func mouseExited(with event: NSEvent) {
        NSLog("[Button \(button.rawValue)] mouseExited")
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
        isSwitchPressed || primaryState.isPressed || secondaryState.isPressed
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
