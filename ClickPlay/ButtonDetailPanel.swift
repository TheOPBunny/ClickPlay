import Cocoa

final class ButtonDetailPanel: NSView {
    private final class FlippedDocumentView: NSView {
        override var isFlipped: Bool { true }
    }

    private enum JoystickBindingDirection {
        case up
        case down
        case left
        case right
    }

    private enum JoystickInputTarget {
        case leftClick
        case scrollUp
        case scrollDown
    }

    private enum JoystickScrollDirection {
        case up
        case down
    }

    private enum Metrics {
        static let keyRecorderWidth: CGFloat = 150
        static let minimumKeyRecorderWidth: CGFloat = 60
        static let keyRecorderHeight: CGFloat = 28
    }

    var onChanged: ((GamepadButton, ButtonConfig) -> Void)?
    var onDelete: ((GamepadButton) -> Void)?
    var onDeleteGroup: ((UUID) -> Void)?
    var onGroupColorChanged: ((UUID, String) -> Void)?
    var onProfileBackgroundColorChanged: ((String) -> Void)?
    var onProfileBackgroundFrostedGlassIntensityChanged: ((Int) -> Void)?

    private var config: ButtonConfig?
    private var button: GamepadButton?
    private var groupID: UUID?

    private let profileSettingsStack = NSStackView()
    private let profileSettingsTitleLabel = NSTextField(labelWithString: "Profile")
    private let profileBackgroundColorWell = NSColorWell()
    private let profileBackgroundResetButton = NSButton(title: "Reset", target: nil, action: nil)
    private let profileBackgroundFrostedGlassPopup = NSPopUpButton()
    private let header = NSStackView()
    private let titleLabel = NSTextField(labelWithString: "Select a button")
    private let scrollView = NSScrollView()
    private let contentContainer = FlippedDocumentView()
    private let contentStack = NSStackView()
    private let labelField = NSTextField()
    private let buttonTypePopup = NSPopUpButton()
    private var buttonTypeRow: NSStackView?
    private let keyRecorder = KeyRecorderButton()
    private let keyClearButton = NSButton(title: "Clear", target: nil, action: nil)
    private var keyRow: NSStackView?
    private let joystickUpRecorder = KeyRecorderButton()
    private let joystickDownRecorder = KeyRecorderButton()
    private let joystickLeftRecorder = KeyRecorderButton()
    private let joystickRightRecorder = KeyRecorderButton()
    private let joystickUpClearButton = NSButton(title: "Clear", target: nil, action: nil)
    private let joystickDownClearButton = NSButton(title: "Clear", target: nil, action: nil)
    private let joystickLeftClearButton = NSButton(title: "Clear", target: nil, action: nil)
    private let joystickRightClearButton = NSButton(title: "Clear", target: nil, action: nil)
    private let joystickLeftClickRecorder = KeyRecorderButton()
    private let joystickLeftClickClearButton = NSButton(title: "Clear", target: nil, action: nil)
    private let joystickLeftClickModePopup = NSPopUpButton()
    private let joystickLeftClickMultiKeyPopup = NSPopUpButton()
    private let joystickScrollUpActionPopup = NSPopUpButton()
    private let joystickScrollDownActionPopup = NSPopUpButton()
    private let joystickScrollUpRecorder = KeyRecorderButton()
    private let joystickScrollDownRecorder = KeyRecorderButton()
    private let joystickScrollUpClearButton = NSButton(title: "Clear", target: nil, action: nil)
    private let joystickScrollDownClearButton = NSButton(title: "Clear", target: nil, action: nil)
    private let joystickScrollUpModePopup = NSPopUpButton()
    private let joystickScrollDownModePopup = NSPopUpButton()
    private let joystickScrollUpMultiKeyPopup = NSPopUpButton()
    private let joystickScrollDownMultiKeyPopup = NSPopUpButton()
    private var joystickSectionLabel: NSTextField?
    private var joystickUpRow: NSStackView?
    private var joystickDownRow: NSStackView?
    private var joystickLeftRow: NSStackView?
    private var joystickRightRow: NSStackView?
    private var joystickLeftClickKeyRow: NSStackView?
    private var joystickLeftClickModeRow: NSStackView?
    private var joystickLeftClickMultiKeyRow: NSStackView?
    private var joystickScrollSectionLabel: NSTextField?
    private var joystickScrollUpActionRow: NSStackView?
    private var joystickScrollDownActionRow: NSStackView?
    private var joystickScrollUpKeyRow: NSStackView?
    private var joystickScrollDownKeyRow: NSStackView?
    private var joystickScrollUpModeRow: NSStackView?
    private var joystickScrollDownModeRow: NSStackView?
    private var joystickScrollUpMultiKeyRow: NSStackView?
    private var joystickScrollDownMultiKeyRow: NSStackView?
    private let rightClickRecorder = KeyRecorderButton()
    private let rightClickFallbackCheckbox = NSButton(checkboxWithTitle: "Use left-click key when unset", target: nil, action: nil)
    private let rightClickModePopup = NSPopUpButton()
    private let rightClickClearButton = NSButton(title: "Clear", target: nil, action: nil)
    private var rightClickSectionLabel: NSTextField?
    private var rightClickKeyRow: NSStackView?
    private var rightClickFallbackRow: NSView?
    private var rightClickModeRow: NSStackView?
    private let colorWell = NSColorWell()
    private var colorRow: NSStackView?
    private let labelSizeField = NSTextField()
    private let labelSizeStepper = NSStepper()
    private let labelBoldCheckbox = NSButton(checkboxWithTitle: "Bold", target: nil, action: nil)
    private let labelItalicCheckbox = NSButton(checkboxWithTitle: "Italic", target: nil, action: nil)
    private let labelColorWell = NSColorWell()
    private var labelRow: NSStackView?
    private var labelStyleRow: NSStackView?
    private let xField = NSTextField()
    private let yField = NSTextField()
    private let widthField = NSTextField()
    private let heightField = NSTextField()
    private let shapePopup = NSPopUpButton()
    private let systemEventPopup = NSPopUpButton()
    private var systemEventRow: NSStackView?
    private let interactionModePopup = NSPopUpButton()
    private var interactionModeRow: NSStackView?
    private let multiKeyActivationModePopup = NSPopUpButton()
    private var multiKeyActivationModeRow: NSStackView?
    private let enabledCheckbox = NSButton(checkboxWithTitle: "Enabled", target: nil, action: nil)
    private let deleteButton = NSButton(title: "Delete Button", target: nil, action: nil)

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func clear() {
        loadProfileSettings(
            backgroundColorHex: Profile.defaultBackgroundColorHex,
            frostedGlassIntensity: Profile.defaultBackgroundFrostedGlassIntensity
        )
    }

    func loadProfileSettings(backgroundColorHex: String, frostedGlassIntensity: Int) {
        config = nil
        button = nil
        groupID = nil
        setShowsProfileSettings(true)
        profileBackgroundColorWell.color = NSColor(hex: backgroundColorHex)
        profileBackgroundFrostedGlassPopup.selectItem(withTag: frostedGlassIntensity)
        if profileBackgroundFrostedGlassPopup.selectedItem == nil {
            profileBackgroundFrostedGlassPopup.selectItem(withTag: Profile.defaultBackgroundFrostedGlassIntensity)
        }
        [labelField, labelSizeField, xField, yField, widthField, heightField].forEach { $0.stringValue = "" }
        buttonTypePopup.selectItem(withTag: ButtonType.keyboard.tag)
        systemEventPopup.selectItem(withTag: SystemEvent.brightnessDown.tag)
        keyRecorder.setKeyBindings([ButtonKeyBinding(keyCode: 49, keyModifiers: 0)])
        joystickUpRecorder.setKeyBindings([JoystickConfig.defaultBindings.up])
        joystickDownRecorder.setKeyBindings([JoystickConfig.defaultBindings.down])
        joystickLeftRecorder.setKeyBindings([JoystickConfig.defaultBindings.left])
        joystickRightRecorder.setKeyBindings([JoystickConfig.defaultBindings.right])
        syncJoystickInputControls(input: .empty, recorder: joystickLeftClickRecorder, modePopup: joystickLeftClickModePopup, multiKeyPopup: joystickLeftClickMultiKeyPopup)
        joystickScrollUpActionPopup.selectItem(withTag: JoystickScrollActionKind.off.tag)
        joystickScrollDownActionPopup.selectItem(withTag: JoystickScrollActionKind.off.tag)
        syncJoystickInputControls(input: .empty, recorder: joystickScrollUpRecorder, modePopup: joystickScrollUpModePopup, multiKeyPopup: joystickScrollUpMultiKeyPopup)
        syncJoystickInputControls(input: .empty, recorder: joystickScrollDownRecorder, modePopup: joystickScrollDownModePopup, multiKeyPopup: joystickScrollDownMultiKeyPopup)
        rightClickRecorder.setOptionalKeyBindings(nil)
        rightClickFallbackCheckbox.state = .on
        rightClickModePopup.selectItem(withTag: Self.sameAsLeftModeTag)
        labelBoldCheckbox.state = .off
        labelItalicCheckbox.state = .off
        labelColorWell.color = .white
        shapePopup.selectItem(withTag: ButtonShape.roundedRectangle.tag)
        interactionModePopup.selectItem(withTag: ButtonInteractionMode.momentary.tag)
        multiKeyActivationModePopup.selectItem(withTag: MultiKeyActivationMode.sequential.tag)
        updateMultiKeyActivationModeVisibility()
        deleteButton.title = "Delete Button"
        deleteButton.isEnabled = false
        updateControlVisibility()
    }

    func loadGroup(_ group: ButtonGroup, colorHex: String?) {
        config = nil
        button = nil
        groupID = group.id
        setShowsProfileSettings(false)
        titleLabel.stringValue = "Editing group: \(group.name)"
        colorWell.color = NSColor(hex: colorHex ?? "#888888")
        deleteButton.title = "Delete Group"
        deleteButton.isEnabled = true
        updateControlVisibility()
    }

    func load(button: GamepadButton, config: ButtonConfig) {
        self.button = button
        self.config = config
        groupID = nil
        setShowsProfileSettings(false)
        deleteButton.title = "Delete Button"
        deleteButton.isEnabled = true
        let isProtectedSwitch = config.action.isProtectedSwitch
        titleLabel.stringValue = isProtectedSwitch ? "Editing switch: \(config.resolvedDisplayLabel)" : "Editing: \(config.resolvedDisplayLabel)"
        labelField.stringValue = config.label
        buttonTypePopup.selectItem(withTag: config.type.tag)
        syncLabelSizeControls(to: config.labelFontSize)
        labelBoldCheckbox.state = config.labelBold ? .on : .off
        labelItalicCheckbox.state = config.labelItalic ? .on : .off
        labelColorWell.color = NSColor(hex: config.labelColorHex)
        colorWell.color = NSColor(hex: config.colorHex)
        xField.stringValue = String(format: "%.1f", config.x)
        yField.stringValue = String(format: "%.1f", config.y)
        widthField.stringValue = String(format: "%.1f", config.editorWidth > 0 ? config.editorWidth : config.width)
        heightField.stringValue = String(format: "%.1f", config.editorHeight > 0 ? config.editorHeight : config.height)
        shapePopup.selectItem(withTag: config.shape.tag)
        enabledCheckbox.state = config.enabled ? .on : .off
        interactionModePopup.selectItem(withTag: config.interactionMode.tag)
        multiKeyActivationModePopup.selectItem(withTag: config.multiKeyActivationMode.tag)
        systemEventPopup.selectItem(withTag: (config.action.systemEvent ?? .brightnessDown).tag)
        rightClickRecorder.setOptionalKeyBindings(config.rightClickKeyBindings)
        rightClickFallbackCheckbox.state = config.rightClickFallsBackToPrimary ? .on : .off
        rightClickModePopup.selectItem(withTag: config.rightClickInteractionMode?.tag ?? Self.sameAsLeftModeTag)
        joystickUpRecorder.setKeyBindings([config.joystick.up])
        joystickDownRecorder.setKeyBindings([config.joystick.down])
        joystickLeftRecorder.setKeyBindings([config.joystick.left])
        joystickRightRecorder.setKeyBindings([config.joystick.right])
        syncJoystickInputControls(
            input: config.joystick.leftClickInput,
            recorder: joystickLeftClickRecorder,
            modePopup: joystickLeftClickModePopup,
            multiKeyPopup: joystickLeftClickMultiKeyPopup
        )
        syncJoystickScrollControls(action: config.joystick.scrollUpAction, direction: .up)
        syncJoystickScrollControls(action: config.joystick.scrollDownAction, direction: .down)
        updateMultiKeyActivationModeVisibility()
        keyRecorder.setKeyBindings(config.keyBindings)
        updateControlVisibility()
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

    private func setup() {
        titleLabel.font = .boldSystemFont(ofSize: 14)
        titleLabel.lineBreakMode = .byTruncatingTail

        configureKeyRecorderLayout(keyRecorder)
        keyRecorder.onKeyRecorded = { [weak self] bindings in
            self?.applyKeyBindings(bindings)
            self?.emitChange()
        }
        configureJoystickRecorder(joystickUpRecorder, direction: .up)
        configureJoystickRecorder(joystickDownRecorder, direction: .down)
        configureJoystickRecorder(joystickLeftRecorder, direction: .left)
        configureJoystickRecorder(joystickRightRecorder, direction: .right)
        configureJoystickInputRecorder(joystickLeftClickRecorder, target: .leftClick)
        configureJoystickInputRecorder(joystickScrollUpRecorder, target: .scrollUp)
        configureJoystickInputRecorder(joystickScrollDownRecorder, target: .scrollDown)
        keyClearButton.bezelStyle = .rounded
        keyClearButton.target = self
        keyClearButton.action = #selector(clearPrimaryKey)
        joystickUpClearButton.bezelStyle = .rounded
        joystickUpClearButton.target = self
        joystickUpClearButton.action = #selector(clearJoystickUpKey)
        joystickDownClearButton.bezelStyle = .rounded
        joystickDownClearButton.target = self
        joystickDownClearButton.action = #selector(clearJoystickDownKey)
        joystickLeftClearButton.bezelStyle = .rounded
        joystickLeftClearButton.target = self
        joystickLeftClearButton.action = #selector(clearJoystickLeftKey)
        joystickRightClearButton.bezelStyle = .rounded
        joystickRightClearButton.target = self
        joystickRightClearButton.action = #selector(clearJoystickRightKey)
        configureOptionalJoystickRecorder(joystickLeftClickRecorder)
        configureOptionalJoystickRecorder(joystickScrollUpRecorder)
        configureOptionalJoystickRecorder(joystickScrollDownRecorder)
        joystickLeftClickClearButton.bezelStyle = .rounded
        joystickLeftClickClearButton.target = self
        joystickLeftClickClearButton.action = #selector(clearJoystickLeftClickKey)
        joystickScrollUpClearButton.bezelStyle = .rounded
        joystickScrollUpClearButton.target = self
        joystickScrollUpClearButton.action = #selector(clearJoystickScrollUpKey)
        joystickScrollDownClearButton.bezelStyle = .rounded
        joystickScrollDownClearButton.target = self
        joystickScrollDownClearButton.action = #selector(clearJoystickScrollDownKey)
        rightClickRecorder.allowsEmptyDisplay = true
        rightClickRecorder.emptyTitle = "Not Set"
        configureKeyRecorderLayout(rightClickRecorder)
        rightClickRecorder.onKeyRecorded = { [weak self] bindings in
            self?.applyRightClickKeyBindings(bindings)
            self?.emitChange()
        }
        deleteButton.bezelStyle = .rounded
        deleteButton.target = self
        deleteButton.action = #selector(deletePressed)
        deleteButton.isEnabled = false
        profileBackgroundColorWell.widthAnchor.constraint(equalToConstant: 44).isActive = true
        profileBackgroundColorWell.heightAnchor.constraint(equalToConstant: 22).isActive = true
        profileBackgroundColorWell.isContinuous = true
        profileBackgroundColorWell.target = self
        profileBackgroundColorWell.action = #selector(profileBackgroundColorChanged)
        profileBackgroundColorWell.toolTip = "Gamepad background color"
        profileBackgroundResetButton.bezelStyle = .rounded
        profileBackgroundResetButton.target = self
        profileBackgroundResetButton.action = #selector(resetProfileBackgroundColor)
        profileBackgroundFrostedGlassPopup.target = self
        profileBackgroundFrostedGlassPopup.action = #selector(profileBackgroundFrostedGlassChanged)
        populateProfileBackgroundFrostedGlassIntensities()

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
        labelColorWell.widthAnchor.constraint(equalToConstant: 44).isActive = true
        labelColorWell.heightAnchor.constraint(equalToConstant: 22).isActive = true
        labelColorWell.target = self
        labelColorWell.action = #selector(applyPressed)
        shapePopup.target = self
        shapePopup.action = #selector(applyPressed)
        populateShapes()
        systemEventPopup.target = self
        systemEventPopup.action = #selector(applyPressed)
        populateSystemEvents()
        buttonTypePopup.target = self
        buttonTypePopup.action = #selector(applyPressed)
        populateButtonTypes()
        interactionModePopup.target = self
        interactionModePopup.action = #selector(applyPressed)
        populateInteractionModes()
        multiKeyActivationModePopup.target = self
        multiKeyActivationModePopup.action = #selector(applyPressed)
        populateMultiKeyActivationModes()
        [joystickLeftClickModePopup, joystickScrollUpModePopup, joystickScrollDownModePopup].forEach { popup in
            popup.target = self
            popup.action = #selector(applyPressed)
            populateInteractionModes(popup)
        }
        [joystickLeftClickMultiKeyPopup, joystickScrollUpMultiKeyPopup, joystickScrollDownMultiKeyPopup].forEach { popup in
            popup.target = self
            popup.action = #selector(applyPressed)
            populateMultiKeyActivationModes(popup)
        }
        [joystickScrollUpActionPopup, joystickScrollDownActionPopup].forEach { popup in
            popup.target = self
            popup.action = #selector(applyPressed)
            populateJoystickScrollActions(popup)
        }
        rightClickModePopup.target = self
        rightClickModePopup.action = #selector(applyPressed)
        populateRightClickModes()
        rightClickFallbackCheckbox.target = self
        rightClickFallbackCheckbox.action = #selector(applyPressed)
        rightClickClearButton.bezelStyle = .rounded
        rightClickClearButton.target = self
        rightClickClearButton.action = #selector(clearRightClickKey)

        header.addArrangedSubview(titleLabel)
        header.addArrangedSubview(NSView())
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 6
        header.edgeInsets = NSEdgeInsets(top: 4, left: 6, bottom: 4, right: 6)
        header.translatesAutoresizingMaskIntoConstraints = false

        profileSettingsTitleLabel.font = .boldSystemFont(ofSize: 14)
        let profileBackgroundLabel = NSTextField(labelWithString: "Gamepad Color")
        profileBackgroundLabel.font = .systemFont(ofSize: 12)
        let profileBackgroundRow = NSStackView(views: [profileBackgroundLabel, profileBackgroundColorWell, profileBackgroundResetButton])
        profileBackgroundRow.orientation = .horizontal
        profileBackgroundRow.alignment = .centerY
        profileBackgroundRow.spacing = 8
        let profileFrostedGlassLabel = NSTextField(labelWithString: "Frosted Glass")
        profileFrostedGlassLabel.font = .systemFont(ofSize: 12)
        let profileFrostedGlassRow = NSStackView(views: [profileFrostedGlassLabel, profileBackgroundFrostedGlassPopup])
        profileFrostedGlassRow.orientation = .horizontal
        profileFrostedGlassRow.alignment = .centerY
        profileFrostedGlassRow.spacing = 8

        profileSettingsStack.orientation = .vertical
        profileSettingsStack.alignment = .leading
        profileSettingsStack.spacing = 12
        profileSettingsStack.translatesAutoresizingMaskIntoConstraints = false
        profileSettingsStack.addArrangedSubview(profileSettingsTitleLabel)
        profileSettingsStack.addArrangedSubview(profileBackgroundRow)
        profileSettingsStack.addArrangedSubview(profileFrostedGlassRow)

        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 10
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.translatesAutoresizingMaskIntoConstraints = false

        let labelRow = makeRow(label: "Label:", control: labelField)
        self.labelRow = labelRow
        contentStack.addArrangedSubview(labelRow)
        let buttonTypeRow = makeRow(label: "Type:", control: buttonTypePopup)
        self.buttonTypeRow = buttonTypeRow
        contentStack.addArrangedSubview(buttonTypeRow)
        let labelStyleRow = makeLabelStyleRow()
        self.labelStyleRow = labelStyleRow
        contentStack.addArrangedSubview(labelStyleRow)
        let keyRow = makeKeyRow()
        self.keyRow = keyRow
        contentStack.addArrangedSubview(keyRow)
        let systemEventRow = makeRow(label: "Event:", control: systemEventPopup)
        self.systemEventRow = systemEventRow
        contentStack.addArrangedSubview(systemEventRow)
        let joystickSectionLabel = makeSectionLabel("Joystick")
        self.joystickSectionLabel = joystickSectionLabel
        contentStack.addArrangedSubview(joystickSectionLabel)
        joystickUpRow = makeJoystickKeyRow(label: "Up:", recorder: joystickUpRecorder, clearButton: joystickUpClearButton)
        joystickDownRow = makeJoystickKeyRow(label: "Down:", recorder: joystickDownRecorder, clearButton: joystickDownClearButton)
        joystickLeftRow = makeJoystickKeyRow(label: "Left:", recorder: joystickLeftRecorder, clearButton: joystickLeftClearButton)
        joystickRightRow = makeJoystickKeyRow(label: "Right:", recorder: joystickRightRecorder, clearButton: joystickRightClearButton)
        [joystickUpRow, joystickDownRow, joystickLeftRow, joystickRightRow].compactMap { $0 }.forEach(contentStack.addArrangedSubview)
        joystickLeftClickKeyRow = makeJoystickInputKeyRow(label: "Click:", recorder: joystickLeftClickRecorder, clearButton: joystickLeftClickClearButton)
        joystickLeftClickModeRow = makeRow(label: "Mode:", control: joystickLeftClickModePopup)
        joystickLeftClickMultiKeyRow = makeRow(label: "Keys:", control: joystickLeftClickMultiKeyPopup)
        [joystickLeftClickKeyRow, joystickLeftClickModeRow, joystickLeftClickMultiKeyRow].compactMap { $0 }.forEach(contentStack.addArrangedSubview)
        let joystickScrollSectionLabel = makeSectionLabel("Joystick Scroll")
        self.joystickScrollSectionLabel = joystickScrollSectionLabel
        contentStack.addArrangedSubview(joystickScrollSectionLabel)
        joystickScrollUpActionRow = makeRow(label: "Up:", control: joystickScrollUpActionPopup)
        joystickScrollUpKeyRow = makeJoystickInputKeyRow(label: "Up Key:", recorder: joystickScrollUpRecorder, clearButton: joystickScrollUpClearButton)
        joystickScrollUpModeRow = makeRow(label: "Up Mode:", control: joystickScrollUpModePopup)
        joystickScrollUpMultiKeyRow = makeRow(label: "Up Keys:", control: joystickScrollUpMultiKeyPopup)
        joystickScrollDownActionRow = makeRow(label: "Down:", control: joystickScrollDownActionPopup)
        joystickScrollDownKeyRow = makeJoystickInputKeyRow(label: "Dn Key:", recorder: joystickScrollDownRecorder, clearButton: joystickScrollDownClearButton)
        joystickScrollDownModeRow = makeRow(label: "Dn Mode:", control: joystickScrollDownModePopup)
        joystickScrollDownMultiKeyRow = makeRow(label: "Dn Keys:", control: joystickScrollDownMultiKeyPopup)
        [
            joystickScrollUpActionRow,
            joystickScrollUpKeyRow,
            joystickScrollUpModeRow,
            joystickScrollUpMultiKeyRow,
            joystickScrollDownActionRow,
            joystickScrollDownKeyRow,
            joystickScrollDownModeRow,
            joystickScrollDownMultiKeyRow,
        ].compactMap { $0 }.forEach(contentStack.addArrangedSubview)
        let colorRow = makeRow(label: "Color:", control: colorWell)
        self.colorRow = colorRow
        contentStack.addArrangedSubview(colorRow)
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
        contentStack.addArrangedSubview(deleteButton)

        contentContainer.addSubview(contentStack)
        scrollView.documentView = contentContainer
        addSubview(header)
        addSubview(scrollView)
        addSubview(profileSettingsStack)

        let headerHeightConstraint = header.heightAnchor.constraint(equalToConstant: 32)
        headerHeightConstraint.priority = .defaultHigh
        let contentContainerMinHeightConstraint = contentContainer.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.contentView.heightAnchor)
        contentContainerMinHeightConstraint.priority = .defaultHigh

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor),
            header.leadingAnchor.constraint(equalTo: leadingAnchor),
            header.trailingAnchor.constraint(equalTo: trailingAnchor),
            headerHeightConstraint,
            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            profileSettingsStack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            profileSettingsStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            profileSettingsStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -14),
            contentContainer.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            contentContainerMinHeightConstraint,
            contentStack.topAnchor.constraint(equalTo: contentContainer.topAnchor, constant: 8),
            contentStack.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor, constant: 8),
            contentStack.trailingAnchor.constraint(lessThanOrEqualTo: contentContainer.trailingAnchor, constant: -8),
            contentStack.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor, constant: -12),
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

    private func setShowsProfileSettings(_ showsProfileSettings: Bool) {
        profileSettingsStack.isHidden = !showsProfileSettings
        header.isHidden = showsProfileSettings
        scrollView.isHidden = showsProfileSettings
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

    private func configureKeyRecorderLayout(_ recorder: KeyRecorderButton) {
        recorder.translatesAutoresizingMaskIntoConstraints = false
        let preferredWidthConstraint = recorder.widthAnchor.constraint(equalToConstant: Metrics.keyRecorderWidth)
        preferredWidthConstraint.priority = .defaultHigh
        NSLayoutConstraint.activate([
            recorder.widthAnchor.constraint(greaterThanOrEqualToConstant: Metrics.minimumKeyRecorderWidth),
            preferredWidthConstraint,
            recorder.heightAnchor.constraint(equalToConstant: Metrics.keyRecorderHeight),
        ])
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

    private func makeJoystickKeyRow(label: String, recorder: KeyRecorderButton, clearButton: NSButton) -> NSStackView {
        configureKeyRecorderLayout(recorder)

        let controls = NSStackView(views: [recorder, clearButton])
        controls.orientation = .horizontal
        controls.spacing = 6

        let row = NSStackView(views: [makeFieldLabel(label), controls])
        row.orientation = .horizontal
        row.spacing = 8
        return row
    }

    private func makeJoystickInputKeyRow(label: String, recorder: KeyRecorderButton, clearButton: NSButton) -> NSStackView {
        configureKeyRecorderLayout(recorder)

        let controls = NSStackView(views: [recorder, clearButton])
        controls.orientation = .horizontal
        controls.spacing = 6

        let row = NSStackView(views: [makeFieldLabel(label), controls])
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
        row.addArrangedSubview(labelColorWell)
        return row
    }

    @objc private func applyPressed() {
        emitChange()
    }

    @objc private func profileBackgroundColorChanged() {
        onProfileBackgroundColorChanged?(profileBackgroundColorWell.color.hexString)
    }

    @objc private func resetProfileBackgroundColor() {
        profileBackgroundColorWell.color = NSColor(hex: Profile.defaultBackgroundColorHex)
        onProfileBackgroundColorChanged?(Profile.defaultBackgroundColorHex)
    }

    @objc private func profileBackgroundFrostedGlassChanged() {
        onProfileBackgroundFrostedGlassIntensityChanged?(profileBackgroundFrostedGlassPopup.selectedTag())
    }

    @objc private func labelSizeStepperChanged() {
        labelSizeField.stringValue = "\(Int(labelSizeStepper.doubleValue))"
        emitChange()
    }

    @objc private func clearPrimaryKey() {
        applyKeyBindings([Self.defaultKeyBinding])
        emitChange()
    }

    @objc private func clearJoystickUpKey() {
        applyJoystickBinding(JoystickConfig.defaultBindings.up, direction: .up)
        emitChange()
    }

    @objc private func clearJoystickDownKey() {
        applyJoystickBinding(JoystickConfig.defaultBindings.down, direction: .down)
        emitChange()
    }

    @objc private func clearJoystickLeftKey() {
        applyJoystickBinding(JoystickConfig.defaultBindings.left, direction: .left)
        emitChange()
    }

    @objc private func clearJoystickRightKey() {
        applyJoystickBinding(JoystickConfig.defaultBindings.right, direction: .right)
        emitChange()
    }

    @objc private func clearRightClickKey() {
        applyRightClickKeyBindings(nil)
        emitChange()
    }

    @objc private func clearJoystickLeftClickKey() {
        applyJoystickInputKeyBindings(nil, target: .leftClick)
        emitChange()
    }

    @objc private func clearJoystickScrollUpKey() {
        applyJoystickInputKeyBindings(nil, target: .scrollUp)
        emitChange()
    }

    @objc private func clearJoystickScrollDownKey() {
        applyJoystickInputKeyBindings(nil, target: .scrollDown)
        emitChange()
    }

    @objc private func deletePressed() {
        if let groupID {
            onDeleteGroup?(groupID)
            return
        }

        guard let button else {
            return
        }

        onDelete?(button)
    }

    private func populateInteractionModes() {
        populateInteractionModes(interactionModePopup)
    }

    private func populateProfileBackgroundFrostedGlassIntensities() {
        profileBackgroundFrostedGlassPopup.removeAllItems()
        profileBackgroundFrostedGlassPopup.addItem(withTitle: "Off")
        profileBackgroundFrostedGlassPopup.lastItem?.tag = Profile.defaultBackgroundFrostedGlassIntensity

        for intensity in stride(from: 10, through: 100, by: 10) {
            profileBackgroundFrostedGlassPopup.addItem(withTitle: "\(intensity)%")
            profileBackgroundFrostedGlassPopup.lastItem?.tag = intensity
        }
    }

    private func populateInteractionModes(_ popup: NSPopUpButton) {
        popup.removeAllItems()

        for mode in ButtonInteractionMode.allCases {
            popup.addItem(withTitle: mode.displayName)
            popup.lastItem?.tag = mode.tag
        }

        popup.selectItem(withTag: ButtonInteractionMode.momentary.tag)
    }

    private func populateButtonTypes() {
        buttonTypePopup.removeAllItems()

        for type in ButtonType.allCases {
            buttonTypePopup.addItem(withTitle: type.displayName)
            buttonTypePopup.lastItem?.tag = type.tag
        }

        buttonTypePopup.selectItem(withTag: ButtonType.keyboard.tag)
    }

    private func populateSystemEvents() {
        systemEventPopup.removeAllItems()

        for event in SystemEvent.allCases {
            systemEventPopup.addItem(withTitle: "\(event.fallbackSymbol) \(event.displayName)")
            systemEventPopup.lastItem?.tag = event.tag
        }

        systemEventPopup.selectItem(withTag: SystemEvent.brightnessDown.tag)
    }

    private func populateMultiKeyActivationModes() {
        populateMultiKeyActivationModes(multiKeyActivationModePopup)
    }

    private func populateMultiKeyActivationModes(_ popup: NSPopUpButton) {
        popup.removeAllItems()

        for mode in MultiKeyActivationMode.allCases {
            popup.addItem(withTitle: mode.displayName)
            popup.lastItem?.tag = mode.tag
        }

        popup.selectItem(withTag: MultiKeyActivationMode.sequential.tag)
    }

    private func populateJoystickScrollActions(_ popup: NSPopUpButton) {
        popup.removeAllItems()

        for kind in JoystickScrollActionKind.allCases {
            popup.addItem(withTitle: kind.displayName)
            popup.lastItem?.tag = kind.tag
        }

        popup.selectItem(withTag: JoystickScrollActionKind.off.tag)
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
        if let groupID {
            onGroupColorChanged?(groupID, colorWell.color.hexString)
            return
        }

        guard var config, let button else {
            return
        }

        config.type = ButtonType(tag: buttonTypePopup.selectedTag()) ?? .keyboard
        config.label = labelField.stringValue
        config.labelFontSize = clampedLabelSize(from: labelSizeField.stringValue, fallback: config.labelFontSize)
        syncLabelSizeControls(to: config.labelFontSize)
        config.labelBold = labelBoldCheckbox.state == .on
        config.labelItalic = labelItalicCheckbox.state == .on
        config.labelColorHex = labelColorWell.color.hexString
        config.colorHex = colorWell.color.hexString
        config.x = Double(xField.stringValue) ?? config.x
        config.y = Double(yField.stringValue) ?? config.y
        config.editorWidth = sizeValue(from: widthField.stringValue, fallback: config.editorWidth > 0 ? config.editorWidth : config.width)
        config.editorHeight = sizeValue(from: heightField.stringValue, fallback: config.editorHeight > 0 ? config.editorHeight : config.height)
        config.shape = ButtonShape(tag: shapePopup.selectedTag()) ?? .roundedRectangle
        if config.action.isProtectedSwitch {
            config.type = .keyboard
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
            buttonTypePopup.selectItem(withTag: ButtonType.keyboard.tag)
        } else if config.type == .systemEvent {
            let systemEvent = SystemEvent(tag: systemEventPopup.selectedTag()) ?? config.action.systemEvent ?? .brightnessDown
            config.action = .systemEvent(systemEvent)
            config.enabled = true
            config.keyBindings = [Self.defaultKeyBinding]
            config.keyCode = Self.defaultKeyBinding.keyCode
            config.keyModifiers = Self.defaultKeyBinding.keyModifiers
            config.multiKeyActivationMode = .sequential
            config.interactionMode = .momentary
            config.rightClickKeyBindings = nil
            config.rightClickFallsBackToPrimary = false
            config.rightClickInteractionMode = nil
            config.label = ""
            config.labelBold = true
            config.labelItalic = false
            config.labelColorHex = "#FFFFFF"
            enabledCheckbox.state = .on
            keyRecorder.setKeyBindings([Self.defaultKeyBinding])
            interactionModePopup.selectItem(withTag: ButtonInteractionMode.momentary.tag)
            multiKeyActivationModePopup.selectItem(withTag: MultiKeyActivationMode.sequential.tag)
            rightClickRecorder.setOptionalKeyBindings(nil)
            rightClickFallbackCheckbox.state = .off
            rightClickModePopup.selectItem(withTag: Self.sameAsLeftModeTag)
            systemEventPopup.selectItem(withTag: systemEvent.tag)
        } else if config.type == .joystick {
            config.action = .keyboard
            config.enabled = enabledCheckbox.state == .on
            config.shape = .oval
            config.interactionMode = .momentary
            config.multiKeyActivationMode = .sequential
            config.rightClickKeyBindings = nil
            config.rightClickFallsBackToPrimary = false
            config.rightClickInteractionMode = nil
            config.joystick.leftClickInput = joystickInput(
                recorder: joystickLeftClickRecorder,
                modePopup: joystickLeftClickModePopup,
                multiKeyPopup: joystickLeftClickMultiKeyPopup
            )
            config.joystick.scrollUpAction = joystickScrollAction(direction: .up)
            config.joystick.scrollDownAction = joystickScrollAction(direction: .down)
            interactionModePopup.selectItem(withTag: ButtonInteractionMode.momentary.tag)
            multiKeyActivationModePopup.selectItem(withTag: MultiKeyActivationMode.sequential.tag)
            rightClickRecorder.setOptionalKeyBindings(nil)
            rightClickFallbackCheckbox.state = .off
            rightClickModePopup.selectItem(withTag: Self.sameAsLeftModeTag)
            shapePopup.selectItem(withTag: ButtonShape.oval.tag)
        } else {
            config.action = .keyboard
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

        let minimumSize = ButtonSizing.minimumSize(for: config.type)
        config.editorWidth = max(config.editorWidth, minimumSize.width)
        config.editorHeight = max(config.editorHeight, minimumSize.height)
        widthField.stringValue = String(format: "%.1f", config.editorWidth)
        heightField.stringValue = String(format: "%.1f", config.editorHeight)

        self.config = config
        updateMultiKeyActivationModeVisibility()
        updateControlVisibility()
        onChanged?(button, config)
    }

    private func applyKeyBindings(_ bindings: [ButtonKeyBinding]) {
        guard config?.action.isProtectedSwitch != true else {
            return
        }
        guard config?.type != .systemEvent else {
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
        guard config?.type != .systemEvent else {
            return
        }

        config?.rightClickKeyBindings = bindings?.isEmpty == true ? nil : bindings
        rightClickRecorder.setOptionalKeyBindings(config?.rightClickKeyBindings)
    }

    private func configureOptionalJoystickRecorder(_ recorder: KeyRecorderButton) {
        recorder.allowsEmptyDisplay = true
        recorder.emptyTitle = "Not Set"
    }

    private func configureJoystickRecorder(_ recorder: KeyRecorderButton, direction: JoystickBindingDirection) {
        recorder.onKeyRecorded = { [weak self] bindings in
            guard let binding = bindings.first else {
                return
            }

            self?.applyJoystickBinding(binding, direction: direction)
            self?.emitChange()
        }
    }

    private func configureJoystickInputRecorder(_ recorder: KeyRecorderButton, target: JoystickInputTarget) {
        recorder.onKeyRecorded = { [weak self] bindings in
            self?.applyJoystickInputKeyBindings(bindings, target: target)
            self?.emitChange()
        }
    }

    private func applyJoystickBinding(_ binding: ButtonKeyBinding, direction: JoystickBindingDirection) {
        guard config?.action.isProtectedSwitch != true else {
            return
        }

        switch direction {
        case .up:
            config?.joystick.up = binding
            joystickUpRecorder.setKeyBindings([binding])
        case .down:
            config?.joystick.down = binding
            joystickDownRecorder.setKeyBindings([binding])
        case .left:
            config?.joystick.left = binding
            joystickLeftRecorder.setKeyBindings([binding])
        case .right:
            config?.joystick.right = binding
            joystickRightRecorder.setKeyBindings([binding])
        }
    }

    private func applyJoystickInputKeyBindings(_ bindings: [ButtonKeyBinding]?, target: JoystickInputTarget) {
        guard config?.action.isProtectedSwitch != true else {
            return
        }

        let normalizedBindings = bindings?.isEmpty == true ? nil : bindings
        switch target {
        case .leftClick:
            config?.joystick.leftClickInput.keyBindings = normalizedBindings ?? []
            config?.joystick.leftClickInput.multiKeyActivationMode = .sequential
            joystickLeftClickRecorder.setOptionalKeyBindings(normalizedBindings)
            joystickLeftClickMultiKeyPopup.selectItem(withTag: MultiKeyActivationMode.sequential.tag)
        case .scrollUp:
            config?.joystick.scrollUpAction.input.keyBindings = normalizedBindings ?? []
            config?.joystick.scrollUpAction.input.multiKeyActivationMode = .sequential
            joystickScrollUpRecorder.setOptionalKeyBindings(normalizedBindings)
            joystickScrollUpMultiKeyPopup.selectItem(withTag: MultiKeyActivationMode.sequential.tag)
        case .scrollDown:
            config?.joystick.scrollDownAction.input.keyBindings = normalizedBindings ?? []
            config?.joystick.scrollDownAction.input.multiKeyActivationMode = .sequential
            joystickScrollDownRecorder.setOptionalKeyBindings(normalizedBindings)
            joystickScrollDownMultiKeyPopup.selectItem(withTag: MultiKeyActivationMode.sequential.tag)
        }
    }

    private func joystickInput(
        recorder: KeyRecorderButton,
        modePopup: NSPopUpButton,
        multiKeyPopup: NSPopUpButton
    ) -> JoystickInputConfig {
        let interactionMode = ButtonInteractionMode(tag: modePopup.selectedTag()) ?? .momentary
        let multiKeyActivationMode: MultiKeyActivationMode
        if interactionMode == .toggleHold {
            multiKeyActivationMode = MultiKeyActivationMode(tag: multiKeyPopup.selectedTag()) ?? .sequential
        } else {
            multiKeyActivationMode = .sequential
            multiKeyPopup.selectItem(withTag: MultiKeyActivationMode.sequential.tag)
        }

        return JoystickInputConfig(
            keyBindings: recorder.recordedBindings,
            interactionMode: interactionMode,
            multiKeyActivationMode: multiKeyActivationMode
        )
    }

    private func joystickScrollAction(direction: JoystickScrollDirection) -> JoystickScrollAction {
        let actionPopup: NSPopUpButton
        let recorder: KeyRecorderButton
        let modePopup: NSPopUpButton
        let multiKeyPopup: NSPopUpButton

        switch direction {
        case .up:
            actionPopup = joystickScrollUpActionPopup
            recorder = joystickScrollUpRecorder
            modePopup = joystickScrollUpModePopup
            multiKeyPopup = joystickScrollUpMultiKeyPopup
        case .down:
            actionPopup = joystickScrollDownActionPopup
            recorder = joystickScrollDownRecorder
            modePopup = joystickScrollDownModePopup
            multiKeyPopup = joystickScrollDownMultiKeyPopup
        }

        let kind = JoystickScrollActionKind(tag: actionPopup.selectedTag()) ?? .off
        switch kind {
        case .off:
            return .off
        case .axisLock:
            return .axisLock
        case .keyCombo:
            return JoystickScrollAction(
                kind: .keyCombo,
                input: joystickInput(recorder: recorder, modePopup: modePopup, multiKeyPopup: multiKeyPopup)
            )
        }
    }

    private func syncJoystickInputControls(
        input: JoystickInputConfig,
        recorder: KeyRecorderButton,
        modePopup: NSPopUpButton,
        multiKeyPopup: NSPopUpButton
    ) {
        recorder.setOptionalKeyBindings(input.keyBindings)
        modePopup.selectItem(withTag: input.interactionMode.tag)
        multiKeyPopup.selectItem(withTag: input.multiKeyActivationMode.tag)
    }

    private func syncJoystickScrollControls(action: JoystickScrollAction, direction: JoystickScrollDirection) {
        switch direction {
        case .up:
            joystickScrollUpActionPopup.selectItem(withTag: action.kind.tag)
            syncJoystickInputControls(
                input: action.input,
                recorder: joystickScrollUpRecorder,
                modePopup: joystickScrollUpModePopup,
                multiKeyPopup: joystickScrollUpMultiKeyPopup
            )
        case .down:
            joystickScrollDownActionPopup.selectItem(withTag: action.kind.tag)
            syncJoystickInputControls(
                input: action.input,
                recorder: joystickScrollDownRecorder,
                modePopup: joystickScrollDownModePopup,
                multiKeyPopup: joystickScrollDownMultiKeyPopup
            )
        }
    }

    private func updateMultiKeyActivationModeVisibility(for bindings: [ButtonKeyBinding]? = nil) {
        let currentBindings = bindings ?? config?.keyBindings ?? []
        let interactionMode = ButtonInteractionMode(tag: interactionModePopup.selectedTag()) ?? config?.interactionMode ?? .momentary
        multiKeyActivationModeRow?.isHidden = currentBindings.count <= 1 || interactionMode != .toggleHold
        updateJoystickInputVisibility()
    }

    private func updateJoystickInputVisibility() {
        let isJoystick = config?.type == .joystick

        joystickLeftClickMultiKeyRow?.isHidden = !isJoystick
            || joystickLeftClickRecorder.recordedBindings.count <= 1
            || ButtonInteractionMode(tag: joystickLeftClickModePopup.selectedTag()) != .toggleHold

        updateJoystickScrollInputVisibility(
            actionPopup: joystickScrollUpActionPopup,
            recorder: joystickScrollUpRecorder,
            modePopup: joystickScrollUpModePopup,
            keyRow: joystickScrollUpKeyRow,
            modeRow: joystickScrollUpModeRow,
            multiKeyRow: joystickScrollUpMultiKeyRow
        )
        updateJoystickScrollInputVisibility(
            actionPopup: joystickScrollDownActionPopup,
            recorder: joystickScrollDownRecorder,
            modePopup: joystickScrollDownModePopup,
            keyRow: joystickScrollDownKeyRow,
            modeRow: joystickScrollDownModeRow,
            multiKeyRow: joystickScrollDownMultiKeyRow
        )
    }

    private func updateJoystickScrollInputVisibility(
        actionPopup: NSPopUpButton,
        recorder: KeyRecorderButton,
        modePopup: NSPopUpButton,
        keyRow: NSStackView?,
        modeRow: NSStackView?,
        multiKeyRow: NSStackView?
    ) {
        let isJoystick = config?.type == .joystick
        let isKeyCombo = JoystickScrollActionKind(tag: actionPopup.selectedTag()) == .keyCombo
        keyRow?.isHidden = !isJoystick || !isKeyCombo
        modeRow?.isHidden = !isJoystick || !isKeyCombo
        multiKeyRow?.isHidden = !isJoystick
            || !isKeyCombo
            || recorder.recordedBindings.count <= 1
            || ButtonInteractionMode(tag: modePopup.selectedTag()) != .toggleHold
    }

    private func updateControlVisibility() {
        if groupID != nil {
            contentStack.arrangedSubviews.forEach { row in
                if let colorRow {
                    row.isHidden = row !== colorRow && row !== deleteButton
                } else {
                    row.isHidden = row !== deleteButton
                }
            }
            deleteButton.isHidden = false
            deleteButton.isEnabled = true
            return
        }

        contentStack.arrangedSubviews.forEach { row in
            row.isHidden = false
        }

        let isProtectedSwitch = config?.action.isProtectedSwitch == true
        let isJoystick = config?.type == .joystick
        let isSystemEvent = config?.type == .systemEvent
        let hidesKeyboardControls = isProtectedSwitch || isJoystick || isSystemEvent

        labelRow?.isHidden = isSystemEvent
        labelStyleRow?.isHidden = isSystemEvent
        buttonTypeRow?.isHidden = isProtectedSwitch || isSystemEvent
        systemEventRow?.isHidden = !isSystemEvent || isProtectedSwitch
        keyRow?.isHidden = hidesKeyboardControls
        interactionModeRow?.isHidden = hidesKeyboardControls
        rightClickSectionLabel?.isHidden = hidesKeyboardControls
        rightClickKeyRow?.isHidden = hidesKeyboardControls
        rightClickFallbackRow?.isHidden = hidesKeyboardControls
        rightClickModeRow?.isHidden = hidesKeyboardControls
        joystickSectionLabel?.isHidden = !isJoystick || isProtectedSwitch
        joystickUpRow?.isHidden = !isJoystick || isProtectedSwitch
        joystickDownRow?.isHidden = !isJoystick || isProtectedSwitch
        joystickLeftRow?.isHidden = !isJoystick || isProtectedSwitch
        joystickRightRow?.isHidden = !isJoystick || isProtectedSwitch
        joystickLeftClickKeyRow?.isHidden = !isJoystick || isProtectedSwitch
        joystickLeftClickModeRow?.isHidden = !isJoystick || isProtectedSwitch
        joystickScrollSectionLabel?.isHidden = !isJoystick || isProtectedSwitch
        joystickScrollUpActionRow?.isHidden = !isJoystick || isProtectedSwitch
        joystickScrollDownActionRow?.isHidden = !isJoystick || isProtectedSwitch

        if hidesKeyboardControls {
            multiKeyActivationModeRow?.isHidden = true
        } else {
            updateMultiKeyActivationModeVisibility()
        }
        updateJoystickInputVisibility()
        enabledCheckbox.isHidden = isProtectedSwitch || isSystemEvent
        deleteButton.isHidden = isProtectedSwitch
        deleteButton.isEnabled = !isProtectedSwitch && button != nil
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

private extension ButtonType {
    static var allCases: [ButtonType] {
        [.keyboard, .joystick, .systemEvent]
    }

    var displayName: String {
        switch self {
        case .keyboard:
            return "Keyboard"
        case .joystick:
            return "Joystick"
        case .systemEvent:
            return "System Event"
        }
    }

    var tag: Int {
        switch self {
        case .keyboard:
            return 0
        case .joystick:
            return 1
        case .systemEvent:
            return 2
        }
    }

    init?(tag: Int) {
        switch tag {
        case 0:
            self = .keyboard
        case 1:
            self = .joystick
        case 2:
            self = .systemEvent
        default:
            return nil
        }
    }
}

private extension ButtonShape {
    static var allCases: [ButtonShape] {
        [.roundedRectangle, .square, .oval]
    }

    var displayName: String {
        switch self {
        case .roundedRectangle:
            return "Rounded Rectangle"
        case .square:
            return "Square"
        case .oval:
            return "Circle/Oval"
        }
    }

    var tag: Int {
        switch self {
        case .roundedRectangle:
            return 0
        case .square:
            return 2
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
        case 2:
            self = .square
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

private extension JoystickScrollActionKind {
    static var allCases: [JoystickScrollActionKind] {
        [.off, .axisLock, .keyCombo]
    }

    var displayName: String {
        switch self {
        case .off:
            return "Off"
        case .axisLock:
            return "Axis Lock"
        case .keyCombo:
            return "Key/Combo"
        }
    }

    var tag: Int {
        switch self {
        case .off:
            return 0
        case .axisLock:
            return 1
        case .keyCombo:
            return 2
        }
    }

    init?(tag: Int) {
        switch tag {
        case 0:
            self = .off
        case 1:
            self = .axisLock
        case 2:
            self = .keyCombo
        default:
            return nil
        }
    }
}
