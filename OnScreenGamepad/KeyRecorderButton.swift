import Cocoa

final class KeyRecorderButton: NSView {

    var onKeyRecorded: (([ButtonKeyBinding]) -> Void)?

    private(set) var recordedCode: Int = 49
    private(set) var recordedModifiers: NSEvent.ModifierFlags = []
    private(set) var recordedBindings: [ButtonKeyBinding] = [ButtonKeyBinding(keyCode: 49, keyModifiers: 0)]

    private var isRecording = false {
        didSet {
            updateAppearance()
        }
    }

    private let button = NSButton()
    private let recordingDot = NSView()
    private var monitor: Any?

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

    func setKey(code: Int, modifiers: NSEvent.ModifierFlags = []) {
        setKeyBindings([ButtonKeyBinding(keyCode: code, keyModifiers: Int(modifiers.rawValue))])
    }

    func setKeyBindings(_ bindings: [ButtonKeyBinding]) {
        recordedBindings = bindings.isEmpty ? [ButtonKeyBinding(keyCode: 49, keyModifiers: 0)] : bindings
        recordedCode = recordedBindings[0].keyCode
        recordedModifiers = NSEvent.ModifierFlags(rawValue: UInt(recordedBindings[0].keyModifiers))
        updateAppearance()
    }

    @objc private func toggleRecording() {
        isRecording ? stopRecording(commitPendingBindings: true) : startRecording()
    }

    private func startRecording() {
        stopRecording(commitPendingBindings: false)
        recordedBindings = []
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKey(event)
            return nil
        }
    }

    private func stopRecording(commitPendingBindings: Bool) {
        let capturedBindings = recordedBindings
        isRecording = false

        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }

        guard commitPendingBindings, !capturedBindings.isEmpty else {
            updateAppearance()
            return
        }

        recordedCode = capturedBindings[0].keyCode
        recordedModifiers = NSEvent.ModifierFlags(rawValue: UInt(capturedBindings[0].keyModifiers))
        onKeyRecorded?(capturedBindings)
    }

    private func handleKey(_ event: NSEvent) {
        let modifierOnlyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
        guard !modifierOnlyCodes.contains(event.keyCode) else {
            return
        }

        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        recordedBindings.append(ButtonKeyBinding(keyCode: Int(event.keyCode), keyModifiers: Int(modifiers.rawValue)))
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
