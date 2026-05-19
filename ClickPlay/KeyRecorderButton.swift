import Cocoa

/// Clickable recorder control that captures one or more keyboard bindings for editor fields.
final class KeyRecorderButton: NSView {

    var onKeyRecorded: (([ButtonKeyBinding]) -> Void)?
    var emptyTitle = "Not Set" {
        didSet { updateAppearance() }
    }
    var allowsEmptyDisplay = false {
        didSet { updateAppearance() }
    }

    private(set) var recordedCode: Int = 49
    private(set) var recordedModifiers: NSEvent.ModifierFlags = []
    private(set) var recordedBindings: [ButtonKeyBinding] = [ButtonKeyBinding(keyCode: 49, keyModifiers: 0)]

    // Recording state tracks modifier-only keys separately so shortcuts like Shift and Shift+A both serialize correctly.
    private var isRecording = false {
        didSet {
            updateAppearance()
        }
    }

    private let button = NSButton()
    private let recordingDot = NSView()
    private var monitor: Any?
    private var pendingModifierOnlyBindings: [Int: ButtonKeyBinding] = [:]
    private var pressedModifierKeyCodes = Set<Int>()
    private var modifierKeyCodesUsedInChord = Set<Int>()

    // MARK: - View Setup

    override init(frame: NSRect) {
        super.init(frame: frame)

        button.bezelStyle = .rounded
        button.target = self
        button.action = #selector(toggleRecording)
        button.translatesAutoresizingMaskIntoConstraints = false

        recordingDot.wantsLayer = true
        recordingDot.layer?.backgroundColor = NSColor.systemRed.cgColor
        recordingDot.layer?.cornerRadius = 4
        recordingDot.layer?.borderColor = NSColor.white.withAlphaComponent(0.85).cgColor
        recordingDot.layer?.borderWidth = 1
        recordingDot.translatesAutoresizingMaskIntoConstraints = false
        recordingDot.isHidden = true

        addSubview(button)
        addSubview(recordingDot)

        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: topAnchor),
            button.bottomAnchor.constraint(equalTo: bottomAnchor),
            button.leadingAnchor.constraint(equalTo: leadingAnchor),
            button.trailingAnchor.constraint(equalTo: trailingAnchor),
            recordingDot.widthAnchor.constraint(equalToConstant: 8),
            recordingDot.heightAnchor.constraint(equalToConstant: 8),
            recordingDot.centerYAnchor.constraint(equalTo: centerYAnchor),
            recordingDot.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9),
        ])

        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Public Value API

    func setKey(code: Int, modifiers: NSEvent.ModifierFlags = []) {
        setKeyBindings([ButtonKeyBinding(keyCode: code, keyModifiers: Int(modifiers.rawValue))])
    }

    func setKeyBindings(_ bindings: [ButtonKeyBinding]) {
        recordedBindings = bindings.isEmpty ? [ButtonKeyBinding(keyCode: 49, keyModifiers: 0)] : bindings
        recordedCode = recordedBindings[0].keyCode
        recordedModifiers = NSEvent.ModifierFlags(rawValue: UInt(recordedBindings[0].keyModifiers))
        updateAppearance()
    }

    func setOptionalKeyBindings(_ bindings: [ButtonKeyBinding]?) {
        guard let bindings, !bindings.isEmpty else {
            recordedBindings = []
            recordedCode = 49
            recordedModifiers = []
            updateAppearance()
            return
        }

        setKeyBindings(bindings)
    }

    @objc private func toggleRecording() {
        isRecording ? stopRecording(commitPendingBindings: true) : startRecording()
    }

    // MARK: - Recording

    private func startRecording() {
        stopRecording(commitPendingBindings: false)
        recordedBindings = []
        pendingModifierOnlyBindings = [:]
        pressedModifierKeyCodes = []
        modifierKeyCodesUsedInChord = []
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            self?.handle(event)
            return nil
        }
    }

    private func stopRecording(commitPendingBindings: Bool) {
        if commitPendingBindings {
            commitPendingModifierOnlyBindings()
        }

        let capturedBindings = recordedBindings
        isRecording = false

        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }

        pendingModifierOnlyBindings = [:]
        pressedModifierKeyCodes = []
        modifierKeyCodesUsedInChord = []

        guard commitPendingBindings, !capturedBindings.isEmpty else {
            updateAppearance()
            return
        }

        recordedCode = capturedBindings[0].keyCode
        recordedModifiers = NSEvent.ModifierFlags(rawValue: UInt(capturedBindings[0].keyModifiers))
        onKeyRecorded?(capturedBindings)
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .keyDown:
            handleKeyDown(event)
        case .flagsChanged:
            handleFlagsChanged(event)
        default:
            return
        }
    }

    private func handleKeyDown(_ event: NSEvent) {
        let keyCode = Int(event.keyCode)
        guard !ButtonConfig.isModifierKey(code: keyCode) else {
            return
        }

        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if !modifiers.isEmpty {
            modifierKeyCodesUsedInChord.formUnion(pressedModifierKeyCodes)
        }

        recordedBindings.append(ButtonKeyBinding(keyCode: keyCode, keyModifiers: Int(modifiers.rawValue)))
        updateAppearance()
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let keyCode = Int(event.keyCode)
        guard let modifierFlag = ButtonConfig.modifierFlag(forKeyCode: keyCode) else {
            return
        }

        if modifierFlag == .capsLock {
            appendModifierOnlyBinding(keyCode: keyCode)
            updateAppearance()
            return
        }

        let wasPressed = pressedModifierKeyCodes.contains(keyCode)
        let isPressed = event.modifierFlags.contains(modifierFlag)

        if isPressed && !wasPressed {
            pressedModifierKeyCodes.insert(keyCode)
            pendingModifierOnlyBindings[keyCode] = ButtonKeyBinding(keyCode: keyCode, keyModifiers: 0)
        } else if wasPressed {
            if !modifierKeyCodesUsedInChord.contains(keyCode) {
                appendModifierOnlyBinding(keyCode: keyCode)
            }

            pendingModifierOnlyBindings.removeValue(forKey: keyCode)
            pressedModifierKeyCodes.remove(keyCode)
            modifierKeyCodesUsedInChord.remove(keyCode)
        }

        updateAppearance()
    }

    private func appendModifierOnlyBinding(keyCode: Int) {
        let binding = pendingModifierOnlyBindings[keyCode] ?? ButtonKeyBinding(keyCode: keyCode, keyModifiers: 0)
        recordedBindings.append(binding)
    }

    private func commitPendingModifierOnlyBindings() {
        for keyCode in pendingModifierOnlyBindings.keys.sorted() where !modifierKeyCodesUsedInChord.contains(keyCode) {
            appendModifierOnlyBinding(keyCode: keyCode)
        }

        pendingModifierOnlyBindings = [:]
        pressedModifierKeyCodes = []
        modifierKeyCodesUsedInChord = []
        updateAppearance()
    }

    private func updateAppearance() {
        if isRecording {
            button.title = recordedBindings.isEmpty ? "Press keys…" : displayName(for: recordedBindings)
            button.contentTintColor = .systemOrange
            recordingDot.isHidden = false
            return
        }

        button.title = displayName(for: recordedBindings)
        button.contentTintColor = .labelColor
        recordingDot.isHidden = true
    }

    private func displayName(for bindings: [ButtonKeyBinding]) -> String {
        guard !bindings.isEmpty else {
            return allowsEmptyDisplay ? emptyTitle : ButtonConfig.keyDisplayName(code: recordedCode, modifiers: recordedModifiers)
        }

        guard bindings.count > 1 else {
            let binding = bindings.first ?? ButtonKeyBinding(keyCode: recordedCode, keyModifiers: Int(recordedModifiers.rawValue))
            return ButtonConfig.keyDisplayName(
                code: binding.keyCode,
                modifiers: NSEvent.ModifierFlags(rawValue: UInt(binding.keyModifiers))
            )
        }

        return "[" + bindings.map { binding in
            ButtonConfig.keyDisplayName(
                code: binding.keyCode,
                modifiers: NSEvent.ModifierFlags(rawValue: UInt(binding.keyModifiers))
            )
        }.joined() + "]"
    }

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
