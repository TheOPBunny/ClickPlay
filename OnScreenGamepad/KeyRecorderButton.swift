import Cocoa

final class KeyRecorderButton: NSView {

    var onKeyRecorded: ((Int, NSEvent.ModifierFlags) -> Void)?

    private(set) var recordedCode: Int = 49
    private(set) var recordedModifiers: NSEvent.ModifierFlags = []

    private var isRecording = false {
        didSet {
            updateAppearance()
        }
    }

    private let button = NSButton()
    private var monitor: Any?

    override init(frame: NSRect) {
        super.init(frame: frame)

        button.bezelStyle = .rounded
        button.target = self
        button.action = #selector(toggleRecording)
        button.translatesAutoresizingMaskIntoConstraints = false

        addSubview(button)

        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: topAnchor),
            button.bottomAnchor.constraint(equalTo: bottomAnchor),
            button.leadingAnchor.constraint(equalTo: leadingAnchor),
            button.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setKey(code: Int, modifiers: NSEvent.ModifierFlags = []) {
        recordedCode = code
        recordedModifiers = modifiers
        updateAppearance()
    }

    @objc private func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKey(event)
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false

        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private func handleKey(_ event: NSEvent) {
        let modifierOnlyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
        guard !modifierOnlyCodes.contains(event.keyCode) else {
            return
        }

        recordedCode = Int(event.keyCode)
        recordedModifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        stopRecording()
        onKeyRecorded?(recordedCode, recordedModifiers)
    }

    private func updateAppearance() {
        if isRecording {
            button.title = "Press a key…"
            button.contentTintColor = .systemOrange
            return
        }

        button.title = keyDisplayName(code: recordedCode, modifiers: recordedModifiers)
        button.contentTintColor = .labelColor
    }

    private func keyDisplayName(code: Int, modifiers: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []

        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }

        parts.append(Self.keyName(code))
        return parts.joined()
    }

    private static func keyName(_ code: Int) -> String {
        let keyNames: [Int: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
            11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 31: "O", 32: "U",
            34: "I", 35: "P", 37: "L", 38: "J", 40: "K", 45: "N", 46: "M",
            36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋",
            123: "←", 124: "→", 125: "↓", 126: "↑",
            96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9",
            103: "F11", 109: "F10", 111: "F12",
            115: "Home", 116: "PgUp", 117: "Del", 119: "End", 121: "PgDn",
        ]

        return keyNames[code] ?? "key(\(code))"
    }

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
