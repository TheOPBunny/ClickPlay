import Cocoa

final class ButtonDetailPanel: NSView {

    var onChanged: ((GamepadButton, ButtonConfig) -> Void)?
    var onDelete: ((GamepadButton) -> Void)?

    private var config: ButtonConfig?
    private var button: GamepadButton?

    private let titleLabel = NSTextField(labelWithString: "Select a button")
    private let contentStack = NSStackView()
    private let labelField = NSTextField()
    private let keyRecorder = KeyRecorderButton()
    private let keyClearButton = NSButton(title: "Clear", target: nil, action: nil)
    private var keyRow: NSStackView?
    private let rightClickRecorder = KeyRecorderButton()
    private let rightClickFallbackCheckbox = NSButton(checkboxWithTitle: "Use left-click key when unset", target: nil, action: nil)
    private let rightClickModePopup = NSPopUpButton()
    private let rightClickClearButton = NSButton(title: "Clear", target: nil, action: nil)
    private var rightClickSectionLabel: NSTextField?
    private var rightClickKeyRow: NSStackView?
    private var rightClickFallbackRow: NSView?
    private var rightClickModeRow: NSStackView?
    private let colorWell = NSColorWell()
    private let labelSizeField = NSTextField()
    private let labelSizeStepper = NSStepper()
    private let labelBoldCheckbox = NSButton(checkboxWithTitle: "Bold", target: nil, action: nil)
    private let labelItalicCheckbox = NSButton(checkboxWithTitle: "Italic", target: nil, action: nil)
    private let xField = NSTextField()
    private let yField = NSTextField()
    private let widthField = NSTextField()
    private let heightField = NSTextField()
    private let shapePopup = NSPopUpButton()
    private let interactionModePopup = NSPopUpButton()
    private var interactionModeRow: NSStackView?
    private let multiKeyActivationModePopup = NSPopUpButton()
    private var multiKeyActivationModeRow: NSStackView?
    private let enabledCheckbox = NSButton(checkboxWithTitle: "Enabled", target: nil, action: nil)
    private let applyButton = NSButton(title: "Apply Changes", target: nil, action: nil)
    private let deleteButton = NSButton(title: "Delete Button", target: nil, action: nil)
    private var isCollapsed = false

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
        [labelField, labelSizeField, xField, yField, widthField, heightField].forEach { $0.stringValue = "" }
        keyRecorder.setKeyBindings([ButtonKeyBinding(keyCode: 49, keyModifiers: 0)])
        rightClickRecorder.setOptionalKeyBindings(nil)
        rightClickFallbackCheckbox.state = .on
        rightClickModePopup.selectItem(withTag: Self.sameAsLeftModeTag)
        labelBoldCheckbox.state = .off
        labelItalicCheckbox.state = .off
        shapePopup.selectItem(withTag: ButtonShape.roundedRectangle.tag)
        interactionModePopup.selectItem(withTag: ButtonInteractionMode.momentary.tag)
        multiKeyActivationModePopup.selectItem(withTag: MultiKeyActivationMode.sequential.tag)
        updateMultiKeyActivationModeVisibility()
        applyButton.isEnabled = false
        deleteButton.isEnabled = false
        setProtectedSwitchControlsHidden(false)
    }

    func load(button: GamepadButton, config: ButtonConfig) {
        self.button = button
        self.config = config
        applyButton.isEnabled = true
        deleteButton.isEnabled = true
        let isProtectedSwitch = config.action.isProtectedSwitch
        titleLabel.stringValue = isProtectedSwitch ? "Editing switch: \(config.resolvedDisplayLabel)" : "Editing: \(config.resolvedDisplayLabel)"
        labelField.stringValue = config.label
        syncLabelSizeControls(to: config.labelFontSize)
        labelBoldCheckbox.state = config.labelBold ? .on : .off
        labelItalicCheckbox.state = config.labelItalic ? .on : .off
        colorWell.color = NSColor(hex: config.colorHex)
        xField.stringValue = String(format: "%.1f", config.x)
        yField.stringValue = String(format: "%.1f", config.y)
        widthField.stringValue = String(format: "%.1f", config.editorWidth > 0 ? config.editorWidth : config.width)
        heightField.stringValue = String(format: "%.1f", config.editorHeight > 0 ? config.editorHeight : config.height)
        shapePopup.selectItem(withTag: config.shape.tag)
        enabledCheckbox.state = config.enabled ? .on : .off
        interactionModePopup.selectItem(withTag: config.interactionMode.tag)
        multiKeyActivationModePopup.selectItem(withTag: config.multiKeyActivationMode.tag)
        rightClickRecorder.setOptionalKeyBindings(config.rightClickKeyBindings)
        rightClickFallbackCheckbox.state = config.rightClickFallsBackToPrimary ? .on : .off
        rightClickModePopup.selectItem(withTag: config.rightClickInteractionMode?.tag ?? Self.sameAsLeftModeTag)
        updateMultiKeyActivationModeVisibility()
        keyRecorder.setKeyBindings(config.keyBindings)
        setProtectedSwitchControlsHidden(isProtectedSwitch)
    }

    func refreshPosition(x: Double, y: Double, config: ButtonConfig) {
        guard self.config != nil else {
            return
        }

        self.config = config
        xField.stringValue = String(format: "%.1f", x)
        yField.stringValue = String(format: "%.1f", y)
    }

    func refreshSize(width: Double, height: Double) {
        guard config != nil else {
            return
        }

        config?.editorWidth = width
        config?.editorHeight = height
        widthField.stringValue = String(format: "%.1f", width)
        heightField.stringValue = String(format: "%.1f", height)
    }

    func setCollapsed(_ collapsed: Bool) {
        isCollapsed = collapsed
        titleLabel.isHidden = collapsed
        contentStack.isHidden = collapsed
    }

    private func setup() {
        titleLabel.font = .boldSystemFont(ofSize: 14)
        titleLabel.lineBreakMode = .byTruncatingTail

        keyRecorder.translatesAutoresizingMaskIntoConstraints = false
        keyRecorder.widthAnchor.constraint(equalToConstant: 150).isActive = true
        keyRecorder.heightAnchor.constraint(equalToConstant: 28).isActive = true
        keyRecorder.onKeyRecorded = { [weak self] bindings in
            self?.applyKeyBindings(bindings)
            self?.emitChange()
        }
        keyClearButton.bezelStyle = .rounded
        keyClearButton.target = self
        keyClearButton.action = #selector(clearPrimaryKey)
        rightClickRecorder.allowsEmptyDisplay = true
        rightClickRecorder.emptyTitle = "Not Set"
        rightClickRecorder.translatesAutoresizingMaskIntoConstraints = false
        rightClickRecorder.widthAnchor.constraint(equalToConstant: 110).isActive = true
        rightClickRecorder.heightAnchor.constraint(equalToConstant: 28).isActive = true
        rightClickRecorder.onKeyRecorded = { [weak self] bindings in
            self?.applyRightClickKeyBindings(bindings)
            self?.emitChange()
        }

        applyButton.bezelStyle = .rounded
        applyButton.target = self
        applyButton.action = #selector(applyPressed)
        applyButton.isEnabled = false
        deleteButton.bezelStyle = .rounded
        deleteButton.target = self
        deleteButton.action = #selector(deletePressed)
        deleteButton.isEnabled = false

        widthField.bezelStyle = .roundedBezel
        widthField.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        widthField.widthAnchor.constraint(equalToConstant: 58).isActive = true
        widthField.target = self
        widthField.action = #selector(applyPressed)
        heightField.bezelStyle = .roundedBezel
        heightField.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        heightField.widthAnchor.constraint(equalToConstant: 58).isActive = true
        heightField.target = self
        heightField.action = #selector(applyPressed)
        labelSizeField.bezelStyle = .roundedBezel
        labelSizeField.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        labelSizeField.widthAnchor.constraint(equalToConstant: 44).isActive = true
        labelSizeField.target = self
        labelSizeField.action = #selector(applyPressed)
        labelSizeStepper.minValue = 6
        labelSizeStepper.maxValue = 36
        labelSizeStepper.increment = 1
        labelSizeStepper.target = self
        labelSizeStepper.action = #selector(labelSizeStepperChanged)
        labelBoldCheckbox.target = self
        labelBoldCheckbox.action = #selector(applyPressed)
        labelItalicCheckbox.target = self
        labelItalicCheckbox.action = #selector(applyPressed)
        shapePopup.target = self
        shapePopup.action = #selector(applyPressed)
        populateShapes()
        interactionModePopup.target = self
        interactionModePopup.action = #selector(applyPressed)
        populateInteractionModes()
        multiKeyActivationModePopup.target = self
        multiKeyActivationModePopup.action = #selector(applyPressed)
        populateMultiKeyActivationModes()
        rightClickModePopup.target = self
        rightClickModePopup.action = #selector(applyPressed)
        populateRightClickModes()
        rightClickFallbackCheckbox.target = self
        rightClickFallbackCheckbox.action = #selector(applyPressed)
        rightClickClearButton.bezelStyle = .rounded
        rightClickClearButton.target = self
        rightClickClearButton.action = #selector(clearRightClickKey)

        let header = NSStackView(views: [
            titleLabel,
            NSView(),
        ])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 6
        header.edgeInsets = NSEdgeInsets(top: 4, left: 6, bottom: 4, right: 6)
        header.translatesAutoresizingMaskIntoConstraints = false

        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 10
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        contentStack.addArrangedSubview(makeRow(label: "Label:", control: labelField))
        contentStack.addArrangedSubview(makeLabelStyleRow())
        let keyRow = makeKeyRow()
        self.keyRow = keyRow
        contentStack.addArrangedSubview(keyRow)
        contentStack.addArrangedSubview(makeRow(label: "Color:", control: colorWell))
        contentStack.addArrangedSubview(makeRow(label: "X (px):", control: xField))
        contentStack.addArrangedSubview(makeRow(label: "Y (px):", control: yField))
        contentStack.addArrangedSubview(makeRow(label: "Shape:", control: shapePopup))
        let interactionModeRow = makeRow(label: "Mode:", control: interactionModePopup)
        self.interactionModeRow = interactionModeRow
        contentStack.addArrangedSubview(interactionModeRow)
        let multiKeyRow = makeRow(label: "Keys:", control: multiKeyActivationModePopup)
        multiKeyActivationModeRow = multiKeyRow
        contentStack.addArrangedSubview(multiKeyRow)
        let rightClickSectionLabel = makeSectionLabel("Right Click")
        self.rightClickSectionLabel = rightClickSectionLabel
        contentStack.addArrangedSubview(rightClickSectionLabel)
        let rightClickKeyRow = makeRightClickKeyRow()
        self.rightClickKeyRow = rightClickKeyRow
        contentStack.addArrangedSubview(rightClickKeyRow)
        rightClickFallbackRow = rightClickFallbackCheckbox
        contentStack.addArrangedSubview(rightClickFallbackCheckbox)
        let rightClickModeRow = makeRow(label: "Mode:", control: rightClickModePopup)
        self.rightClickModeRow = rightClickModeRow
        contentStack.addArrangedSubview(rightClickModeRow)
        contentStack.addArrangedSubview(enabledCheckbox)
        contentStack.addArrangedSubview(makeSizeRow())
        contentStack.addArrangedSubview(applyButton)
        contentStack.addArrangedSubview(deleteButton)

        addSubview(header)
        addSubview(contentStack)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor),
            header.leadingAnchor.constraint(equalTo: leadingAnchor),
            header.trailingAnchor.constraint(equalTo: trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 32),
            contentStack.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            contentStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
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

    private func makeSectionLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .boldSystemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func makeKeyRow() -> NSStackView {
        let controls = NSStackView(views: [keyRecorder, keyClearButton])
        controls.orientation = .horizontal
        controls.spacing = 6

        let row = NSStackView(views: [makeFieldLabel("Key:"), controls])
        row.orientation = .horizontal
        row.spacing = 8
        return row
    }

    private func makeRightClickKeyRow() -> NSStackView {
        let controls = NSStackView(views: [rightClickRecorder, rightClickClearButton])
        controls.orientation = .horizontal
        controls.spacing = 6

        let row = NSStackView(views: [makeFieldLabel("Key:"), controls])
        row.orientation = .horizontal
        row.spacing = 8
        return row
    }

    private func makeSizeRow() -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 4
        row.addArrangedSubview(makeFieldLabel("Size:"))
        row.addArrangedSubview(widthField)

        let separator = NSTextField(labelWithString: "×")
        separator.font = .systemFont(ofSize: 12)
        row.addArrangedSubview(separator)
        row.addArrangedSubview(heightField)

        let note = NSTextField(labelWithString: "px")
        note.font = .systemFont(ofSize: 10)
        note.textColor = .tertiaryLabelColor
        row.addArrangedSubview(note)
        return row
    }

    private func makeLabelStyleRow() -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 6
        row.alignment = .centerY
        row.addArrangedSubview(makeFieldLabel("Font:"))
        row.addArrangedSubview(labelSizeField)
        row.addArrangedSubview(labelSizeStepper)
        row.addArrangedSubview(labelBoldCheckbox)
        row.addArrangedSubview(labelItalicCheckbox)
        return row
    }

    @objc private func applyPressed() {
        emitChange()
    }

    @objc private func labelSizeStepperChanged() {
        labelSizeField.stringValue = "\(Int(labelSizeStepper.doubleValue))"
        emitChange()
    }

    @objc private func clearPrimaryKey() {
        applyKeyBindings([Self.defaultKeyBinding])
        emitChange()
    }

    @objc private func clearRightClickKey() {
        applyRightClickKeyBindings(nil)
        emitChange()
    }

    @objc private func deletePressed() {
        guard let button else {
            return
        }

        onDelete?(button)
    }

    private func populateInteractionModes() {
        interactionModePopup.removeAllItems()

        for mode in ButtonInteractionMode.allCases {
            interactionModePopup.addItem(withTitle: mode.displayName)
            interactionModePopup.lastItem?.tag = mode.tag
        }

        interactionModePopup.selectItem(withTag: ButtonInteractionMode.momentary.tag)
    }

    private func populateMultiKeyActivationModes() {
        multiKeyActivationModePopup.removeAllItems()

        for mode in MultiKeyActivationMode.allCases {
            multiKeyActivationModePopup.addItem(withTitle: mode.displayName)
            multiKeyActivationModePopup.lastItem?.tag = mode.tag
        }

        multiKeyActivationModePopup.selectItem(withTag: MultiKeyActivationMode.sequential.tag)
    }

    private func populateRightClickModes() {
        rightClickModePopup.removeAllItems()
        rightClickModePopup.addItem(withTitle: "Same as Left")
        rightClickModePopup.lastItem?.tag = Self.sameAsLeftModeTag

        for mode in ButtonInteractionMode.allCases {
            rightClickModePopup.addItem(withTitle: mode.displayName)
            rightClickModePopup.lastItem?.tag = mode.tag
        }

        rightClickModePopup.selectItem(withTag: Self.sameAsLeftModeTag)
    }

    private func populateShapes() {
        shapePopup.removeAllItems()

        for shape in ButtonShape.allCases {
            shapePopup.addItem(withTitle: shape.displayName)
            shapePopup.lastItem?.tag = shape.tag
        }

        shapePopup.selectItem(withTag: ButtonShape.roundedRectangle.tag)
    }

    private func emitChange() {
        guard var config, let button else {
            return
        }

        config.label = labelField.stringValue
        config.labelFontSize = clampedLabelSize(from: labelSizeField.stringValue, fallback: config.labelFontSize)
        syncLabelSizeControls(to: config.labelFontSize)
        config.labelBold = labelBoldCheckbox.state == .on
        config.labelItalic = labelItalicCheckbox.state == .on
        config.colorHex = colorWell.color.hexString
        config.x = Double(xField.stringValue) ?? config.x
        config.y = Double(yField.stringValue) ?? config.y
        config.editorWidth = sizeValue(from: widthField.stringValue, fallback: config.editorWidth > 0 ? config.editorWidth : config.width)
        config.editorHeight = sizeValue(from: heightField.stringValue, fallback: config.editorHeight > 0 ? config.editorHeight : config.height)
        config.shape = ButtonShape(tag: shapePopup.selectedTag()) ?? .roundedRectangle
        if config.action.isProtectedSwitch {
            config.enabled = true
            config.interactionMode = .momentary
            config.multiKeyActivationMode = .sequential
            config.rightClickKeyBindings = nil
            config.rightClickFallsBackToPrimary = true
            config.rightClickInteractionMode = nil
            enabledCheckbox.state = .on
            interactionModePopup.selectItem(withTag: ButtonInteractionMode.momentary.tag)
            multiKeyActivationModePopup.selectItem(withTag: MultiKeyActivationMode.sequential.tag)
            rightClickRecorder.setOptionalKeyBindings(nil)
            rightClickFallbackCheckbox.state = .on
            rightClickModePopup.selectItem(withTag: Self.sameAsLeftModeTag)
        } else {
            config.enabled = enabledCheckbox.state == .on
            config.interactionMode = ButtonInteractionMode(tag: interactionModePopup.selectedTag()) ?? .momentary
            if config.interactionMode == .toggleHold {
                config.multiKeyActivationMode = MultiKeyActivationMode(tag: multiKeyActivationModePopup.selectedTag()) ?? .sequential
            } else {
                config.multiKeyActivationMode = .sequential
                multiKeyActivationModePopup.selectItem(withTag: MultiKeyActivationMode.sequential.tag)
            }
            config.rightClickFallsBackToPrimary = rightClickFallbackCheckbox.state == .on
            config.rightClickInteractionMode = ButtonInteractionMode(tag: rightClickModePopup.selectedTag())
        }

        self.config = config
        updateMultiKeyActivationModeVisibility()
        onChanged?(button, config)
    }

    private func applyKeyBindings(_ bindings: [ButtonKeyBinding]) {
        guard config?.action.isProtectedSwitch != true else {
            return
        }

        guard !bindings.isEmpty else {
            return
        }

        config?.keyBindings = bindings
        config?.keyCode = bindings[0].keyCode
        config?.keyModifiers = bindings[0].keyModifiers
        config?.multiKeyActivationMode = .sequential
        multiKeyActivationModePopup.selectItem(withTag: MultiKeyActivationMode.sequential.tag)
        updateMultiKeyActivationModeVisibility(for: bindings)
    }

    private func applyRightClickKeyBindings(_ bindings: [ButtonKeyBinding]?) {
        guard config?.action.isProtectedSwitch != true else {
            return
        }

        config?.rightClickKeyBindings = bindings?.isEmpty == true ? nil : bindings
        rightClickRecorder.setOptionalKeyBindings(config?.rightClickKeyBindings)
    }

    private func updateMultiKeyActivationModeVisibility(for bindings: [ButtonKeyBinding]? = nil) {
        let currentBindings = bindings ?? config?.keyBindings ?? []
        let interactionMode = ButtonInteractionMode(tag: interactionModePopup.selectedTag()) ?? config?.interactionMode ?? .momentary
        multiKeyActivationModeRow?.isHidden = currentBindings.count <= 1 || interactionMode != .toggleHold
    }

    private func setProtectedSwitchControlsHidden(_ hidden: Bool) {
        keyRow?.isHidden = hidden
        interactionModeRow?.isHidden = hidden
        rightClickSectionLabel?.isHidden = hidden
        rightClickKeyRow?.isHidden = hidden
        rightClickFallbackRow?.isHidden = hidden
        rightClickModeRow?.isHidden = hidden
        if hidden {
            multiKeyActivationModeRow?.isHidden = true
        } else {
            updateMultiKeyActivationModeVisibility()
        }
        enabledCheckbox.isHidden = hidden
        deleteButton.isHidden = hidden
        deleteButton.isEnabled = !hidden && button != nil
    }

    private func clampedLabelSize(from stringValue: String, fallback: Double) -> Double {
        guard let parsedValue = Double(stringValue), parsedValue.isFinite else {
            return fallback
        }

        return min(max(parsedValue, 6), 36)
    }

    private func sizeValue(from stringValue: String, fallback: Double) -> Double {
        guard let parsedValue = Double(stringValue), parsedValue.isFinite else {
            return fallback
        }

        return parsedValue
    }

    private func syncLabelSizeControls(to size: Double) {
        let clampedSize = min(max(size, 6), 36)
        labelSizeField.stringValue = "\(Int(clampedSize))"
        labelSizeStepper.doubleValue = clampedSize
    }
}

private extension ButtonDetailPanel {
    static let sameAsLeftModeTag = -1
    static let defaultKeyBinding = ButtonKeyBinding(keyCode: 49, keyModifiers: 0)
}

private extension ButtonShape {
    static var allCases: [ButtonShape] {
        [.roundedRectangle, .oval]
    }

    var displayName: String {
        switch self {
        case .roundedRectangle:
            return "Rounded Rectangle"
        case .oval:
            return "Circle/Oval"
        }
    }

    var tag: Int {
        switch self {
        case .roundedRectangle:
            return 0
        case .oval:
            return 1
        }
    }

    init?(tag: Int) {
        switch tag {
        case 0:
            self = .roundedRectangle
        case 1:
            self = .oval
        default:
            return nil
        }
    }
}

private extension ButtonInteractionMode {
    static var allCases: [ButtonInteractionMode] {
        [.momentary, .toggleHold, .turbo]
    }

    var displayName: String {
        switch self {
        case .momentary:
            return "Momentary"
        case .toggleHold:
            return "Toggle Hold"
        case .turbo:
            return "Turbo"
        }
    }

    var tag: Int {
        switch self {
        case .momentary:
            return 0
        case .toggleHold:
            return 1
        case .turbo:
            return 2
        }
    }

    init?(tag: Int) {
        switch tag {
        case 0:
            self = .momentary
        case 1:
            self = .toggleHold
        case 2:
            self = .turbo
        default:
            return nil
        }
    }
}

private extension MultiKeyActivationMode {
    static var allCases: [MultiKeyActivationMode] {
        [.sequential, .simultaneous]
    }

    var displayName: String {
        switch self {
        case .sequential:
            return "Sequential"
        case .simultaneous:
            return "Simultaneous"
        }
    }

    var tag: Int {
        switch self {
        case .sequential:
            return 0
        case .simultaneous:
            return 1
        }
    }

    init?(tag: Int) {
        switch tag {
        case 0:
            self = .sequential
        case 1:
            self = .simultaneous
        default:
            return nil
        }
    }
}
