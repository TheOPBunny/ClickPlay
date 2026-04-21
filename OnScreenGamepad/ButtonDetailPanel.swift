import Cocoa

final class ButtonDetailPanel: NSView {

    var onChanged: ((GamepadButton, ButtonConfig) -> Void)?

    private var config: ButtonConfig?
    private var button: GamepadButton?

    private let titleLabel = NSTextField(labelWithString: "Select a button")
    private let labelField = NSTextField()
    private let keyRecorder = KeyRecorderButton()
    private let colorWell = NSColorWell()
    private let xField = NSTextField()
    private let yField = NSTextField()
    private let widthLabel = NSTextField(labelWithString: "–")
    private let heightLabel = NSTextField(labelWithString: "–")
    private let enabledCheckbox = NSButton(checkboxWithTitle: "Enabled", target: nil, action: nil)
    private let applyButton = NSButton(title: "Apply Changes", target: nil, action: nil)

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func clear() {
        titleLabel.stringValue = "Select a button to edit"
        config = nil
        button = nil
        [labelField, xField, yField].forEach { $0.stringValue = "" }
        keyRecorder.setKey(code: 49)
        widthLabel.stringValue = "–"
        heightLabel.stringValue = "–"
        applyButton.isEnabled = false
    }

    func load(button: GamepadButton, config: ButtonConfig) {
        self.button = button
        self.config = config
        applyButton.isEnabled = true
        titleLabel.stringValue = "Editing: \(button.rawValue)"
        labelField.stringValue = config.label
        colorWell.color = NSColor(hex: config.colorHex)
        xField.stringValue = String(format: "%.4f", config.x)
        yField.stringValue = String(format: "%.4f", config.y)
        enabledCheckbox.state = config.enabled ? .on : .off
        keyRecorder.setKey(
            code: config.keyCode,
            modifiers: NSEvent.ModifierFlags(rawValue: UInt(config.keyModifiers))
        )
        widthLabel.stringValue = String(format: "%.3f", config.width)
        heightLabel.stringValue = String(format: "%.3f", config.height)
    }

    func refreshPosition(x: Double, y: Double, config: ButtonConfig) {
        guard self.config != nil else {
            return
        }

        self.config = config
        xField.stringValue = String(format: "%.4f", x)
        yField.stringValue = String(format: "%.4f", y)
    }

    func refreshSize(width: Double, height: Double) {
        guard config != nil else {
            return
        }

        config?.width = width
        config?.height = height
        widthLabel.stringValue = String(format: "%.3f", width)
        heightLabel.stringValue = String(format: "%.3f", height)
    }

    private func setup() {
        titleLabel.font = .boldSystemFont(ofSize: 14)

        keyRecorder.translatesAutoresizingMaskIntoConstraints = false
        keyRecorder.widthAnchor.constraint(equalToConstant: 150).isActive = true
        keyRecorder.heightAnchor.constraint(equalToConstant: 28).isActive = true
        keyRecorder.onKeyRecorded = { [weak self] code, modifiers in
            self?.config?.keyCode = code
            self?.config?.keyModifiers = Int(modifiers.rawValue)
            self?.emitChange()
        }

        applyButton.bezelStyle = .rounded
        applyButton.target = self
        applyButton.action = #selector(applyPressed)
        applyButton.isEnabled = false

        widthLabel.textColor = .secondaryLabelColor
        widthLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        heightLabel.textColor = .secondaryLabelColor
        heightLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(makeRow(label: "Label:", control: labelField))
        stack.addArrangedSubview(makeRow(label: "Key:", control: keyRecorder))
        stack.addArrangedSubview(makeRow(label: "Color:", control: colorWell))
        stack.addArrangedSubview(makeRow(label: "X (0–1):", control: xField))
        stack.addArrangedSubview(makeRow(label: "Y (0–1):", control: yField))
        stack.addArrangedSubview(enabledCheckbox)
        stack.addArrangedSubview(makeSizeRow())
        stack.addArrangedSubview(applyButton)

        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
        ])

        labelField.bezelStyle = .roundedBezel
        labelField.widthAnchor.constraint(equalToConstant: 115).isActive = true
        labelField.target = self
        labelField.action = #selector(applyPressed)

        xField.bezelStyle = .roundedBezel
        xField.widthAnchor.constraint(equalToConstant: 115).isActive = true
        xField.target = self
        xField.action = #selector(applyPressed)

        yField.bezelStyle = .roundedBezel
        yField.widthAnchor.constraint(equalToConstant: 115).isActive = true
        yField.target = self
        yField.action = #selector(applyPressed)

        colorWell.target = self
        colorWell.action = #selector(applyPressed)

        enabledCheckbox.target = self
        enabledCheckbox.action = #selector(applyPressed)

        clear()
    }

    private func makeRow(label: String, control: NSView) -> NSStackView {
        let row = NSStackView(views: [makeFieldLabel(label), control])
        row.orientation = .horizontal
        row.spacing = 8
        return row
    }

    private func makeFieldLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12)
        label.widthAnchor.constraint(equalToConstant: 60).isActive = true
        return label
    }

    private func makeSizeRow() -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 4
        row.addArrangedSubview(makeFieldLabel("Size:"))
        row.addArrangedSubview(widthLabel)

        let separator = NSTextField(labelWithString: "×")
        separator.font = .systemFont(ofSize: 12)
        row.addArrangedSubview(separator)
        row.addArrangedSubview(heightLabel)

        let note = NSTextField(labelWithString: "(drag corner in preview)")
        note.font = .systemFont(ofSize: 10)
        note.textColor = .tertiaryLabelColor
        row.addArrangedSubview(note)
        return row
    }

    @objc private func applyPressed() {
        emitChange()
    }

    private func emitChange() {
        guard var config, let button else {
            return
        }

        if !labelField.stringValue.isEmpty {
            config.label = labelField.stringValue
        }

        config.colorHex = colorWell.color.hexString
        config.x = Double(xField.stringValue) ?? config.x
        config.y = Double(yField.stringValue) ?? config.y
        config.enabled = enabledCheckbox.state == .on

        self.config = config
        onChanged?(button, config)
    }
}
