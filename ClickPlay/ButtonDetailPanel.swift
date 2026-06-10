import Cocoa

/// Inspector panel for editing profile-wide visuals, selected buttons, joystick bindings, and groups.
final class ButtonDetailPanel: NSView, NSTextFieldDelegate {
    // The scroll document is flipped so vertical stack coordinates match normal top-to-bottom form layout.
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
        case rightClick
        case scrollUp
        case scrollDown
    }

    private enum JoystickScrollDirection {
        case up
        case down
    }

    // Fixed control sizing lives here so rows stay aligned as the inspector is resized.
    private enum Metrics {
        static let keyRecorderWidth: CGFloat = 132
        static let minimumKeyRecorderWidth: CGFloat = 60
        static let keyRecorderHeight: CGFloat = 28
    }

    var onChanged: ((GamepadButton, ButtonConfig) -> Void)?
    var onDelete: ((GamepadButton) -> Void)?
    var onDeleteGroup: ((UUID) -> Void)?
    var onGroupColorChanged: ((UUID, String) -> Void)?
    var onProfileBackgroundColorChanged: ((String) -> Void)?
    var onProfileBackgroundFrostedGlassIntensityChanged: ((Int) -> Void)?
    var onProfileMouseCaptureArmDelayChanged: ((Int) -> Void)?
    var onProfileMouseCaptureTemporaryReleaseChanged: ((Int) -> Void)?

    // Current selection context. Exactly one of button/group/profile mode drives the visible form sections.
    private var config: ButtonConfig?
    private var button: GamepadButton?
    private var groupID: UUID?

    private let profileSettingsStack = NSStackView()
    private let profileSettingsTitleLabel = NSTextField(labelWithString: "Profile")
    private let profileBackgroundColorWell = NSColorWell()
    private let profileBackgroundResetButton = NSButton(title: "Reset", target: nil, action: nil)
    private let profileBackgroundFrostedGlassPopup = NSPopUpButton()
    private let profileMouseCaptureArmDelayField = NSTextField()
    private let profileMouseCaptureTemporaryReleaseField = NSTextField()
    private var profileMouseCaptureArmDelayRow: NSStackView?
    private var profileMouseCaptureTemporaryReleaseRow: NSStackView?
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
    private let joystickLayerPopup = NSPopUpButton()
    private let joystickOperationModePopup = NSPopUpButton()
    private let joystickAxisLockModePopup = NSPopUpButton()
    private let joystickAxisLockHoldDurationField = NSTextField()
    private let joystickAxisUnlockHoldDurationField = NSTextField()
    private let joystickUpClearButton = NSButton(title: "Clear", target: nil, action: nil)
    private let joystickDownClearButton = NSButton(title: "Clear", target: nil, action: nil)
    private let joystickLeftClearButton = NSButton(title: "Clear", target: nil, action: nil)
    private let joystickRightClearButton = NSButton(title: "Clear", target: nil, action: nil)
    private let joystickLeftClickRecorder = KeyRecorderButton()
    private let joystickRightClickRecorder = KeyRecorderButton()
    private let joystickLeftClickActionPopup = NSPopUpButton()
    private let joystickRightClickActionPopup = NSPopUpButton()
    private let joystickLeftClickClearButton = NSButton(title: "Clear", target: nil, action: nil)
    private let joystickRightClickClearButton = NSButton(title: "Clear", target: nil, action: nil)
    private let joystickLeftClickModePopup = NSPopUpButton()
    private let joystickRightClickModePopup = NSPopUpButton()
    private let joystickLeftClickMultiKeyPopup = NSPopUpButton()
    private let joystickRightClickMultiKeyPopup = NSPopUpButton()
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
    private var selectedJoystickLayerIndex = 0
    private var joystickLayerRow: NSStackView?
    private var joystickOperationModeRow: NSStackView?
    private var joystickAxisLockModeRow: NSStackView?
    private var joystickAxisLockHoldDurationRow: NSStackView?
    private var joystickUpRow: NSStackView?
    private var joystickDownRow: NSStackView?
    private var joystickLeftRow: NSStackView?
    private var joystickRightRow: NSStackView?
    private var joystickLeftClickActionRow: NSStackView?
    private var joystickRightClickActionRow: NSStackView?
    private var joystickLeftClickKeyRow: NSStackView?
    private var joystickRightClickKeyRow: NSStackView?
    private var joystickLeftClickModeRow: NSStackView?
    private var joystickRightClickModeRow: NSStackView?
    private var joystickLeftClickMultiKeyRow: NSStackView?
    private var joystickRightClickMultiKeyRow: NSStackView?
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
    private let systemEventIconSizePopup = NSPopUpButton()
    private var systemEventIconSizeRow: NSStackView?
    private let dwellActionPopup = NSPopUpButton()
    private let dwellTimerField = NSTextField()
    private let dwellToleranceField = NSTextField()
    private var dwellActionRow: NSStackView?
    private var dwellTimerRow: NSStackView?
    private var dwellToleranceRow: NSStackView?
    private let interactionModePopup = NSPopUpButton()
    private var interactionModeRow: NSStackView?
    private let multiKeyActivationModePopup = NSPopUpButton()
    private var multiKeyActivationModeRow: NSStackView?
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
            frostedGlassIntensity: Profile.defaultBackgroundFrostedGlassIntensity,
            mouseCaptureArmDelaySeconds: Profile.defaultMouseCaptureArmDelaySeconds,
            mouseCaptureTemporaryReleaseSeconds: Profile.defaultMouseCaptureTemporaryReleaseSeconds,
            showsMouseCaptureTiming: true
        )
    }

    func loadProfileSettings(
        backgroundColorHex: String,
        frostedGlassIntensity: Int,
        mouseCaptureArmDelaySeconds: Int,
        mouseCaptureTemporaryReleaseSeconds: Int,
        showsMouseCaptureTiming: Bool
    ) {
        config = nil
        button = nil
        groupID = nil
        setShowsProfileSettings(true)
        profileBackgroundColorWell.color = NSColor(hex: backgroundColorHex)
        profileBackgroundFrostedGlassPopup.selectItem(withTag: frostedGlassIntensity)
        if profileBackgroundFrostedGlassPopup.selectedItem == nil {
            profileBackgroundFrostedGlassPopup.selectItem(withTag: Profile.defaultBackgroundFrostedGlassIntensity)
        }
        profileMouseCaptureArmDelayField.stringValue = "\(max(1, mouseCaptureArmDelaySeconds))"
        profileMouseCaptureTemporaryReleaseField.stringValue = "\(max(1, mouseCaptureTemporaryReleaseSeconds))"
        profileMouseCaptureArmDelayRow?.isHidden = !showsMouseCaptureTiming
        profileMouseCaptureTemporaryReleaseRow?.isHidden = !showsMouseCaptureTiming
        [labelField, labelSizeField, xField, yField, widthField, heightField].forEach { $0.stringValue = "" }
        buttonTypePopup.selectItem(withTag: ButtonType.keyboard.tag)
        systemEventPopup.selectItem(withTag: SystemEvent.brightnessDown.tag)
        systemEventIconSizePopup.selectItem(withTag: SystemEventIconSize.large.tag)
        dwellActionPopup.selectItem(withTag: DwellActionKind.leftClick.tag)
        dwellTimerField.stringValue = String(format: "%.1f", DwellActionConfig.defaultTimerDuration)
        dwellToleranceField.stringValue = String(format: "%.0f", DwellActionConfig.defaultMovementTolerance)
        keyRecorder.setKeyBindings([ButtonKeyBinding(keyCode: 49, keyModifiers: 0)])
        joystickOperationModePopup.selectItem(withTag: JoystickOperationMode.capture.tag)
        selectedJoystickLayerIndex = 0
        joystickLayerPopup.selectItem(withTag: 0)
        joystickAxisLockModePopup.selectItem(withTag: JoystickAxisLockMode.scrollWheel.tag)
        joystickAxisLockHoldDurationField.stringValue = String(format: "%.1f", JoystickConfig.defaultAxisLockHoldDuration)
        joystickAxisUnlockHoldDurationField.stringValue = String(format: "%.1f", JoystickConfig.defaultAxisUnlockHoldDuration)
        joystickUpRecorder.setKeyBindings([JoystickConfig.defaultBindings.up])
        joystickDownRecorder.setKeyBindings([JoystickConfig.defaultBindings.down])
        joystickLeftRecorder.setKeyBindings([JoystickConfig.defaultBindings.left])
        joystickRightRecorder.setKeyBindings([JoystickConfig.defaultBindings.right])
        syncJoystickTriggerControls(action: .off, actionPopup: joystickLeftClickActionPopup, recorder: joystickLeftClickRecorder, modePopup: joystickLeftClickModePopup, multiKeyPopup: joystickLeftClickMultiKeyPopup)
        syncJoystickTriggerControls(action: .off, actionPopup: joystickRightClickActionPopup, recorder: joystickRightClickRecorder, modePopup: joystickRightClickModePopup, multiKeyPopup: joystickRightClickMultiKeyPopup)
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
        xField.stringValue = geometryValueString(config.x)
        yField.stringValue = geometryValueString(config.y)
        widthField.stringValue = geometryValueString(config.editorWidth > 0 ? config.editorWidth : config.width)
        heightField.stringValue = geometryValueString(config.editorHeight > 0 ? config.editorHeight : config.height)
        shapePopup.selectItem(withTag: config.shape.tag)
        interactionModePopup.selectItem(withTag: config.interactionMode.tag)
        multiKeyActivationModePopup.selectItem(withTag: config.multiKeyActivationMode.tag)
        systemEventPopup.selectItem(withTag: (config.action.systemEvent ?? .brightnessDown).tag)
        systemEventIconSizePopup.selectItem(withTag: config.systemEventIconSize.tag)
        dwellActionPopup.selectItem(withTag: config.dwellAction.kind.tag)
        dwellTimerField.stringValue = String(format: "%.1f", config.dwellAction.timerDuration)
        dwellToleranceField.stringValue = geometryValueString(config.dwellAction.movementTolerance)
        rightClickRecorder.setOptionalKeyBindings(config.rightClickKeyBindings)
        rightClickFallbackCheckbox.state = config.rightClickFallsBackToPrimary ? .on : .off
        rightClickModePopup.selectItem(withTag: config.rightClickInteractionMode?.tag ?? Self.sameAsLeftModeTag)
        joystickOperationModePopup.selectItem(withTag: config.joystick.operationMode.tag)
        selectedJoystickLayerIndex = 0
        joystickLayerPopup.selectItem(withTag: selectedJoystickLayerIndex)
        joystickAxisLockModePopup.selectItem(withTag: config.joystick.axisLockMode.tag)
        joystickAxisLockHoldDurationField.stringValue = String(format: "%.1f", config.joystick.axisLockHoldDuration)
        joystickAxisUnlockHoldDurationField.stringValue = String(format: "%.1f", config.joystick.axisUnlockHoldDuration)
        syncJoystickLayerControls(from: config.joystick)
        updateJoystickScrollActionOptions(axisLockMode: config.joystick.axisLockMode)
        updateMultiKeyActivationModeVisibility()
        keyRecorder.setKeyBindings(config.keyBindings)
        updateControlVisibility()
    }

    func refreshPosition(x: Double, y: Double, config: ButtonConfig) {
        guard self.config != nil else {
            return
        }

        self.config = config
        xField.stringValue = geometryValueString(x)
        yField.stringValue = geometryValueString(y)
    }

    func refreshSize(width: Double, height: Double) {
        guard config != nil else {
            return
        }

        config?.editorWidth = width
        config?.editorHeight = height
        widthField.stringValue = geometryValueString(width)
        heightField.stringValue = geometryValueString(height)
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
        configureJoystickInputRecorder(joystickRightClickRecorder, target: .rightClick)
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
        configureOptionalJoystickRecorder(joystickRightClickRecorder)
        configureOptionalJoystickRecorder(joystickScrollUpRecorder)
        configureOptionalJoystickRecorder(joystickScrollDownRecorder)
        joystickLeftClickClearButton.bezelStyle = .rounded
        joystickLeftClickClearButton.target = self
        joystickLeftClickClearButton.action = #selector(clearJoystickLeftClickKey)
        joystickRightClickClearButton.bezelStyle = .rounded
        joystickRightClickClearButton.target = self
        joystickRightClickClearButton.action = #selector(clearJoystickRightClickKey)
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
        [profileMouseCaptureArmDelayField, profileMouseCaptureTemporaryReleaseField].forEach { field in
            field.bezelStyle = .roundedBezel
            field.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            field.widthAnchor.constraint(equalToConstant: 58).isActive = true
            field.target = self
            field.action = #selector(profileMouseCaptureTimingChanged(_:))
            field.delegate = self
        }

        widthField.bezelStyle = .roundedBezel
        widthField.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        widthField.widthAnchor.constraint(equalToConstant: 58).isActive = true
        configureApplyingTextField(widthField)
        heightField.bezelStyle = .roundedBezel
        heightField.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        heightField.widthAnchor.constraint(equalToConstant: 58).isActive = true
        configureApplyingTextField(heightField)
        labelSizeField.bezelStyle = .roundedBezel
        labelSizeField.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        labelSizeField.widthAnchor.constraint(equalToConstant: 44).isActive = true
        configureApplyingTextField(labelSizeField)
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
        systemEventIconSizePopup.target = self
        systemEventIconSizePopup.action = #selector(applyPressed)
        populateSystemEventIconSizes()
        dwellActionPopup.target = self
        dwellActionPopup.action = #selector(applyPressed)
        populateDwellActions()
        buttonTypePopup.target = self
        buttonTypePopup.action = #selector(applyPressed)
        populateButtonTypes()
        joystickOperationModePopup.target = self
        joystickOperationModePopup.action = #selector(applyPressed)
        populateJoystickOperationModes()
        joystickLayerPopup.target = self
        joystickLayerPopup.action = #selector(joystickLayerChanged)
        populateJoystickLayers()
        joystickAxisLockModePopup.target = self
        joystickAxisLockModePopup.action = #selector(applyPressed)
        populateJoystickAxisLockModes()
        interactionModePopup.target = self
        interactionModePopup.action = #selector(applyPressed)
        populateInteractionModes()
        multiKeyActivationModePopup.target = self
        multiKeyActivationModePopup.action = #selector(applyPressed)
        populateMultiKeyActivationModes()
        [joystickLeftClickModePopup, joystickRightClickModePopup, joystickScrollUpModePopup, joystickScrollDownModePopup].forEach { popup in
            popup.target = self
            popup.action = #selector(applyPressed)
            populateInteractionModes(popup)
        }
        [joystickLeftClickMultiKeyPopup, joystickRightClickMultiKeyPopup, joystickScrollUpMultiKeyPopup, joystickScrollDownMultiKeyPopup].forEach { popup in
            popup.target = self
            popup.action = #selector(applyPressed)
            populateMultiKeyActivationModes(popup)
        }
        joystickLeftClickActionPopup.target = self
        joystickLeftClickActionPopup.action = #selector(applyPressed)
        populateJoystickTriggerActions(joystickLeftClickActionPopup, includeNested: true)
        joystickRightClickActionPopup.target = self
        joystickRightClickActionPopup.action = #selector(applyPressed)
        populateJoystickTriggerActions(joystickRightClickActionPopup, includeNested: false)
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
        [joystickAxisLockHoldDurationField, joystickAxisUnlockHoldDurationField, dwellTimerField, dwellToleranceField].forEach { field in
            field.bezelStyle = .roundedBezel
            field.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            field.widthAnchor.constraint(equalToConstant: 58).isActive = true
            configureApplyingTextField(field)
        }

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
        profileMouseCaptureArmDelayRow = NSStackView(views: [
            profileSettingsLabel("Capture Arm"),
            makeUnitField(field: profileMouseCaptureArmDelayField, unit: "seconds")
        ])
        profileMouseCaptureTemporaryReleaseRow = NSStackView(views: [
            profileSettingsLabel("Temp Release"),
            makeUnitField(field: profileMouseCaptureTemporaryReleaseField, unit: "seconds")
        ])
        [profileMouseCaptureArmDelayRow, profileMouseCaptureTemporaryReleaseRow].compactMap { $0 }.forEach { row in
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 8
        }

        profileSettingsStack.orientation = .vertical
        profileSettingsStack.alignment = .leading
        profileSettingsStack.spacing = 12
        profileSettingsStack.translatesAutoresizingMaskIntoConstraints = false
        profileSettingsStack.addArrangedSubview(profileSettingsTitleLabel)
        profileSettingsStack.addArrangedSubview(profileBackgroundRow)
        profileSettingsStack.addArrangedSubview(profileFrostedGlassRow)
        [profileMouseCaptureArmDelayRow, profileMouseCaptureTemporaryReleaseRow].compactMap { $0 }.forEach(profileSettingsStack.addArrangedSubview)

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
        let systemEventIconSizeRow = makeRow(label: "Icon Size:", control: systemEventIconSizePopup)
        self.systemEventIconSizeRow = systemEventIconSizeRow
        contentStack.addArrangedSubview(systemEventIconSizeRow)
        let dwellActionRow = makeRow(label: "Action:", control: dwellActionPopup)
        self.dwellActionRow = dwellActionRow
        contentStack.addArrangedSubview(dwellActionRow)
        let dwellTimerRow = makeRow(label: "Timer:", control: makeUnitField(field: dwellTimerField, unit: "seconds"))
        self.dwellTimerRow = dwellTimerRow
        contentStack.addArrangedSubview(dwellTimerRow)
        let dwellToleranceRow = makeRow(label: "Tolerance:", control: makeUnitField(field: dwellToleranceField, unit: "px"))
        self.dwellToleranceRow = dwellToleranceRow
        contentStack.addArrangedSubview(dwellToleranceRow)
        let joystickSectionLabel = makeSectionLabel("Joystick")
        self.joystickSectionLabel = joystickSectionLabel
        contentStack.addArrangedSubview(joystickSectionLabel)
        joystickOperationModeRow = makeRow(label: "Operation:", control: joystickOperationModePopup)
        if let joystickOperationModeRow {
            contentStack.addArrangedSubview(joystickOperationModeRow)
        }
        joystickLayerRow = makeRow(label: "Layer:", control: joystickLayerPopup)
        if let joystickLayerRow {
            contentStack.addArrangedSubview(joystickLayerRow)
        }
        joystickAxisLockModeRow = makeRow(label: "Axis Lock:", control: joystickAxisLockModePopup)
        joystickAxisLockHoldDurationRow = makeRow(label: "Lock Timer:", control: joystickAxisLockHoldDurationField)
        [joystickAxisLockModeRow, joystickAxisLockHoldDurationRow, ].compactMap { $0 }.forEach(contentStack.addArrangedSubview)
        joystickUpRow = makeJoystickKeyRow(label: "Up:", recorder: joystickUpRecorder, clearButton: joystickUpClearButton)
        joystickDownRow = makeJoystickKeyRow(label: "Down:", recorder: joystickDownRecorder, clearButton: joystickDownClearButton)
        joystickLeftRow = makeJoystickKeyRow(label: "Left:", recorder: joystickLeftRecorder, clearButton: joystickLeftClearButton)
        joystickRightRow = makeJoystickKeyRow(label: "Right:", recorder: joystickRightRecorder, clearButton: joystickRightClearButton)
        [joystickUpRow, joystickDownRow, joystickLeftRow, joystickRightRow].compactMap { $0 }.forEach(contentStack.addArrangedSubview)
        joystickLeftClickActionRow = makeRow(label: "Left Click:", control: joystickLeftClickActionPopup)
        joystickLeftClickKeyRow = makeJoystickInputKeyRow(label: "Left Click:", recorder: joystickLeftClickRecorder, clearButton: joystickLeftClickClearButton)
        joystickLeftClickModeRow = makeRow(label: "L-click Mode:", control: joystickLeftClickModePopup)
        joystickLeftClickMultiKeyRow = makeRow(label: "L-click Keys:", control: joystickLeftClickMultiKeyPopup)
        joystickRightClickActionRow = makeRow(label: "Right Click:", control: joystickRightClickActionPopup)
        joystickRightClickKeyRow = makeJoystickInputKeyRow(label: "Right Click:", recorder: joystickRightClickRecorder, clearButton: joystickRightClickClearButton)
        joystickRightClickModeRow = makeRow(label: "R-click Mode:", control: joystickRightClickModePopup)
        joystickRightClickMultiKeyRow = makeRow(label: "R-click Keys:", control: joystickRightClickMultiKeyPopup)
        [
            joystickLeftClickActionRow,
            joystickLeftClickKeyRow,
            joystickLeftClickModeRow,
            joystickLeftClickMultiKeyRow,
            joystickRightClickActionRow,
            joystickRightClickKeyRow,
            joystickRightClickModeRow,
            joystickRightClickMultiKeyRow,
        ].compactMap { $0 }.forEach(contentStack.addArrangedSubview)
        let joystickScrollSectionLabel = makeSectionLabel("Scroll Wheel")
        self.joystickScrollSectionLabel = joystickScrollSectionLabel
        contentStack.addArrangedSubview(joystickScrollSectionLabel)
        joystickScrollUpActionRow = makeRow(label: "Up:", control: joystickScrollUpActionPopup)
        joystickScrollUpKeyRow = makeJoystickInputKeyRow(label: "Up Key:", recorder: joystickScrollUpRecorder, clearButton: joystickScrollUpClearButton)
        joystickScrollUpModeRow = makeRow(label: "Up Mode:", control: joystickScrollUpModePopup)
        joystickScrollUpMultiKeyRow = makeRow(label: "Up Keys:", control: joystickScrollUpMultiKeyPopup)
        joystickScrollDownActionRow = makeRow(label: "Down:", control: joystickScrollDownActionPopup)
        joystickScrollDownKeyRow = makeJoystickInputKeyRow(label: "Down Key:", recorder: joystickScrollDownRecorder, clearButton: joystickScrollDownClearButton)
        joystickScrollDownModeRow = makeRow(label: "Down Mode:", control: joystickScrollDownModePopup)
        joystickScrollDownMultiKeyRow = makeRow(label: "Down Keys:", control: joystickScrollDownMultiKeyPopup)
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
        contentStack.addArrangedSubview(makeRow(label: "X:", control: makeUnitField(field: xField, unit: "px")))
        contentStack.addArrangedSubview(makeRow(label: "Y:", control: makeUnitField(field: yField, unit: "px")))
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
        configureApplyingTextField(labelField)

        xField.bezelStyle = .roundedBezel
        xField.widthAnchor.constraint(equalToConstant: 115).isActive = true
        configureApplyingTextField(xField)

        yField.bezelStyle = .roundedBezel
        yField.widthAnchor.constraint(equalToConstant: 115).isActive = true
        configureApplyingTextField(yField)

        colorWell.target = self
        colorWell.action = #selector(applyPressed)


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

    private func makeUnitField(field: NSTextField, unit: String) -> NSStackView {
        let unitLabel = NSTextField(labelWithString: unit)
        unitLabel.font = .systemFont(ofSize: 12)
        unitLabel.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [field, unitLabel])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        return stack
    }

    private func makeFieldLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12)
        label.widthAnchor.constraint(equalToConstant: 75).isActive = true
        return label
    }

    private func profileSettingsLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12)
        label.widthAnchor.constraint(equalToConstant: 86).isActive = true
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
        separator.textColor = .secondaryLabelColor
        row.addArrangedSubview(separator)
        row.addArrangedSubview(heightField)

        let note = NSTextField(labelWithString: "px")
        note.font = .systemFont(ofSize: 12)
        note.textColor = .secondaryLabelColor
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

    @objc private func applyTextFieldAndEndEditing(_ sender: NSTextField) {
        emitChange()
        endEditing(sender)
    }

    private func configureApplyingTextField(_ field: NSTextField) {
        field.target = self
        field.action = #selector(applyTextFieldAndEndEditing(_:))
        field.delegate = self
        field.wantsLayer = true
        field.layer?.borderColor = NSColor.separatorColor.cgColor
        field.layer?.borderWidth = 2
        field.layer?.cornerRadius = 5
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard commandSelector == #selector(NSResponder.insertNewline(_:)),
              let textField = control as? NSTextField else {
            return false
        }

        textField.stringValue = textView.string
        if textField === profileMouseCaptureArmDelayField || textField === profileMouseCaptureTemporaryReleaseField {
            profileMouseCaptureTimingChanged(textField)
            endEditing(textField)
            return true
        }

        emitChange()
        endEditing(textField)
        return true
    }

    private func endEditing(_ textField: NSTextField) {
        textField.currentEditor()?.selectedRange = NSRange(location: textField.stringValue.utf16.count, length: 0)
        textField.window?.endEditing(for: textField)
        textField.window?.makeFirstResponder(nil)
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

    @objc private func profileMouseCaptureTimingChanged(_ sender: NSTextField) {
        let value = clampedWholeSeconds(from: sender.stringValue)
        sender.stringValue = "\(value)"

        if sender === profileMouseCaptureArmDelayField {
            onProfileMouseCaptureArmDelayChanged?(value)
        } else if sender === profileMouseCaptureTemporaryReleaseField {
            onProfileMouseCaptureTemporaryReleaseChanged?(value)
        }
    }

    @objc private func labelSizeStepperChanged() {
        labelSizeField.stringValue = "\(Int(labelSizeStepper.doubleValue))"
        emitChange()
    }

    @objc private func joystickLayerChanged() {
        selectedJoystickLayerIndex = min(
            max(0, joystickLayerPopup.selectedTag()),
            JoystickConfig.maxLayerCount - 1
        )
        guard var config, config.type == .joystick else {
            updateControlVisibility()
            return
        }

        ensureNestedJoystickLayers(in: &config.joystick, through: selectedJoystickLayerIndex)
        self.config = config
        syncJoystickLayerControls(from: config.joystick)
        updateControlVisibility()
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

    @objc private func clearJoystickRightClickKey() {
        applyJoystickInputKeyBindings(nil, target: .rightClick)
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

    private func populateJoystickOperationModes() {
        joystickOperationModePopup.removeAllItems()

        for mode in JoystickOperationMode.allCases {
            joystickOperationModePopup.addItem(withTitle: mode.displayName)
            joystickOperationModePopup.lastItem?.tag = mode.tag
        }

        joystickOperationModePopup.selectItem(withTag: JoystickOperationMode.capture.tag)
    }

    private func populateJoystickAxisLockModes() {
        joystickAxisLockModePopup.removeAllItems()

        for mode in JoystickAxisLockMode.allCases {
            joystickAxisLockModePopup.addItem(withTitle: mode.displayName)
            joystickAxisLockModePopup.lastItem?.tag = mode.tag
        }

        joystickAxisLockModePopup.selectItem(withTag: JoystickAxisLockMode.scrollWheel.tag)
    }

    private func populateSystemEvents() {
        systemEventPopup.removeAllItems()

        for event in SystemEvent.allCases {
            systemEventPopup.addItem(withTitle: "\(event.fallbackSymbol) \(event.displayName)")
            systemEventPopup.lastItem?.tag = event.tag
        }

        systemEventPopup.selectItem(withTag: SystemEvent.brightnessDown.tag)
    }

    private func populateSystemEventIconSizes() {
        systemEventIconSizePopup.removeAllItems()

        for size in SystemEventIconSize.allCases {
            systemEventIconSizePopup.addItem(withTitle: size.displayName)
            systemEventIconSizePopup.lastItem?.tag = size.tag
        }

        systemEventIconSizePopup.selectItem(withTag: SystemEventIconSize.large.tag)
    }

    private func populateDwellActions() {
        dwellActionPopup.removeAllItems()

        for action in DwellActionKind.allCases {
            dwellActionPopup.addItem(withTitle: action.displayName)
            dwellActionPopup.lastItem?.tag = action.tag
        }

        dwellActionPopup.selectItem(withTag: DwellActionKind.leftClick.tag)
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

    private func populateJoystickScrollActions(
        _ popup: NSPopUpButton,
        includeAxisLock: Bool = true,
        includeNested: Bool = true
    ) {
        popup.removeAllItems()

        for kind in JoystickScrollActionKind.allCases(includeAxisLock: includeAxisLock, includeNested: includeNested) {
            popup.addItem(withTitle: kind.displayName)
            popup.lastItem?.tag = kind.tag
        }

        popup.selectItem(withTag: JoystickScrollActionKind.off.tag)
    }

    private func populateJoystickLayers() {
        joystickLayerPopup.removeAllItems()

        for index in 0..<JoystickConfig.maxLayerCount {
            let title = index == 0 ? "Layer 1 (Base)" : "Layer \(index + 1)"
            joystickLayerPopup.addItem(withTitle: title)
            joystickLayerPopup.lastItem?.tag = index
        }

        joystickLayerPopup.selectItem(withTag: 0)
    }

    private func populateJoystickTriggerActions(_ popup: NSPopUpButton, includeNested: Bool) {
        popup.removeAllItems()

        for kind in JoystickTriggerActionKind.allCases(includeNested: includeNested) {
            popup.addItem(withTitle: kind.displayName)
            popup.lastItem?.tag = kind.tag
        }

        popup.selectItem(withTag: JoystickTriggerActionKind.off.tag)
    }

    private func updateJoystickScrollActionOptions(axisLockMode: JoystickAxisLockMode) {
        let includeAxisLock = axisLockMode == .scrollWheel
        let includeNested = selectedJoystickLayerIndex + 1 < JoystickConfig.maxLayerCount
        updateJoystickScrollActionOptions(
            joystickScrollUpActionPopup,
            includeAxisLock: includeAxisLock,
            includeNested: includeNested
        )
        updateJoystickScrollActionOptions(
            joystickScrollDownActionPopup,
            includeAxisLock: includeAxisLock,
            includeNested: includeNested
        )
    }

    private func updateJoystickScrollActionOptions(
        _ popup: NSPopUpButton,
        includeAxisLock: Bool,
        includeNested: Bool
    ) {
        let selectedKind = JoystickScrollActionKind(tag: popup.selectedTag()) ?? .off
        populateJoystickScrollActions(popup, includeAxisLock: includeAxisLock, includeNested: includeNested)

        if (!includeAxisLock && selectedKind == .axisLock) || (!includeNested && selectedKind == .nestedJoystick) {
            popup.selectItem(withTag: JoystickScrollActionKind.off.tag)
        } else {
            popup.selectItem(withTag: selectedKind.tag)
        }
    }

    private func updateJoystickTriggerActionOptions() {
        let selectedKind = JoystickTriggerActionKind(tag: joystickLeftClickActionPopup.selectedTag()) ?? .off
        let includeNested = selectedJoystickLayerIndex + 1 < JoystickConfig.maxLayerCount
        populateJoystickTriggerActions(joystickLeftClickActionPopup, includeNested: includeNested)
        joystickLeftClickActionPopup.selectItem(
            withTag: includeNested || selectedKind != .nestedJoystick
                ? selectedKind.tag
                : JoystickTriggerActionKind.off.tag
        )
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
        config.x = geometryValue(from: xField.stringValue, fallback: config.x)
        config.y = geometryValue(from: yField.stringValue, fallback: config.y)
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
            interactionModePopup.selectItem(withTag: ButtonInteractionMode.momentary.tag)
            multiKeyActivationModePopup.selectItem(withTag: MultiKeyActivationMode.sequential.tag)
            rightClickRecorder.setOptionalKeyBindings(nil)
            rightClickFallbackCheckbox.state = .on
            rightClickModePopup.selectItem(withTag: Self.sameAsLeftModeTag)
            buttonTypePopup.selectItem(withTag: ButtonType.keyboard.tag)
        } else if config.type == .systemEvent {
            let systemEvent = SystemEvent(tag: systemEventPopup.selectedTag()) ?? config.action.systemEvent ?? .brightnessDown
            let iconSize = SystemEventIconSize(tag: systemEventIconSizePopup.selectedTag()) ?? config.systemEventIconSize
            config.action = .systemEvent(systemEvent)
            config.systemEventIconSize = iconSize
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
            keyRecorder.setKeyBindings([Self.defaultKeyBinding])
            interactionModePopup.selectItem(withTag: ButtonInteractionMode.momentary.tag)
            multiKeyActivationModePopup.selectItem(withTag: MultiKeyActivationMode.sequential.tag)
            rightClickRecorder.setOptionalKeyBindings(nil)
            rightClickFallbackCheckbox.state = .off
            rightClickModePopup.selectItem(withTag: Self.sameAsLeftModeTag)
            systemEventPopup.selectItem(withTag: systemEvent.tag)
            systemEventIconSizePopup.selectItem(withTag: iconSize.tag)
        } else if config.type == .dwellAction {
            let dwellActionKind = DwellActionKind(tag: dwellActionPopup.selectedTag()) ?? config.dwellAction.kind
            let iconSize = SystemEventIconSize(tag: systemEventIconSizePopup.selectedTag()) ?? config.systemEventIconSize
            config.action = .keyboard
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
            config.systemEventIconSize = iconSize
            config.dwellAction = DwellActionConfig(
                kind: dwellActionKind,
                timerDuration: durationValue(
                    from: dwellTimerField.stringValue,
                    fallback: config.dwellAction.timerDuration
                ),
                movementTolerance: toleranceValue(
                    from: dwellToleranceField.stringValue,
                    fallback: config.dwellAction.movementTolerance
                )
            )
            keyRecorder.setKeyBindings([Self.defaultKeyBinding])
            interactionModePopup.selectItem(withTag: ButtonInteractionMode.momentary.tag)
            multiKeyActivationModePopup.selectItem(withTag: MultiKeyActivationMode.sequential.tag)
            rightClickRecorder.setOptionalKeyBindings(nil)
            rightClickFallbackCheckbox.state = .off
            rightClickModePopup.selectItem(withTag: Self.sameAsLeftModeTag)
            dwellActionPopup.selectItem(withTag: dwellActionKind.tag)
            systemEventIconSizePopup.selectItem(withTag: iconSize.tag)
            dwellTimerField.stringValue = String(format: "%.1f", config.dwellAction.timerDuration)
            dwellToleranceField.stringValue = geometryValueString(config.dwellAction.movementTolerance)
        } else if config.type == .joystick {
            config.action = .keyboard
            config.shape = .oval
            config.interactionMode = .momentary
            config.multiKeyActivationMode = .sequential
            config.rightClickKeyBindings = nil
            config.rightClickFallsBackToPrimary = false
            config.rightClickInteractionMode = nil
            let operationMode = JoystickOperationMode(tag: joystickOperationModePopup.selectedTag()) ?? .capture
            config.joystick.operationMode = operationMode
            let axisLockMode = JoystickAxisLockMode(tag: joystickAxisLockModePopup.selectedTag()) ?? .scrollWheel
            config.joystick.axisLockMode = axisLockMode
            updateJoystickScrollActionOptions(axisLockMode: axisLockMode)
            config.joystick.axisLockHoldDuration = durationValue(
                from: joystickAxisLockHoldDurationField.stringValue,
                fallback: config.joystick.axisLockHoldDuration
            )
            config.joystick.axisUnlockHoldDuration = durationValue(
                from: joystickAxisUnlockHoldDurationField.stringValue,
                fallback: config.joystick.axisUnlockHoldDuration
            )
            ensureNestedJoystickLayers(in: &config.joystick, through: selectedJoystickLayerIndex)
            if selectedJoystickLayerIndex == 0 {
                config.joystick.up = joystickUpRecorder.recordedBindings.first ?? config.joystick.up
                config.joystick.down = joystickDownRecorder.recordedBindings.first ?? config.joystick.down
                config.joystick.left = joystickLeftRecorder.recordedBindings.first ?? config.joystick.left
                config.joystick.right = joystickRightRecorder.recordedBindings.first ?? config.joystick.right
                config.joystick.leftClickAction = joystickTriggerAction(
                    actionPopup: joystickLeftClickActionPopup,
                    recorder: joystickLeftClickRecorder,
                    modePopup: joystickLeftClickModePopup,
                    multiKeyPopup: joystickLeftClickMultiKeyPopup
                )
                config.joystick.rightClickAction = operationMode == .clickDrag
                    ? joystickTriggerAction(
                        actionPopup: joystickRightClickActionPopup,
                        recorder: joystickRightClickRecorder,
                        modePopup: joystickRightClickModePopup,
                        multiKeyPopup: joystickRightClickMultiKeyPopup
                    )
                    : .off
                config.joystick.scrollUpAction = joystickScrollAction(direction: .up)
                config.joystick.scrollDownAction = joystickScrollAction(direction: .down)
            } else {
                var layer = config.joystick.nestedLayers[selectedJoystickLayerIndex - 1]
                layer.up = joystickUpRecorder.recordedBindings.first ?? layer.up
                layer.down = joystickDownRecorder.recordedBindings.first ?? layer.down
                layer.left = joystickLeftRecorder.recordedBindings.first ?? layer.left
                layer.right = joystickRightRecorder.recordedBindings.first ?? layer.right
                layer.leftClickAction = joystickTriggerAction(
                    actionPopup: joystickLeftClickActionPopup,
                    recorder: joystickLeftClickRecorder,
                    modePopup: joystickLeftClickModePopup,
                    multiKeyPopup: joystickLeftClickMultiKeyPopup
                )
                layer.scrollUpAction = joystickScrollAction(direction: .up)
                layer.scrollDownAction = joystickScrollAction(direction: .down)
                config.joystick.nestedLayers[selectedJoystickLayerIndex - 1] = layer
            }
            ensureNextNestedJoystickLayerIfNeeded(in: &config.joystick)
            interactionModePopup.selectItem(withTag: ButtonInteractionMode.momentary.tag)
            multiKeyActivationModePopup.selectItem(withTag: MultiKeyActivationMode.sequential.tag)
            rightClickRecorder.setOptionalKeyBindings(nil)
            rightClickFallbackCheckbox.state = .off
            rightClickModePopup.selectItem(withTag: Self.sameAsLeftModeTag)
            shapePopup.selectItem(withTag: ButtonShape.oval.tag)
            joystickAxisLockModePopup.selectItem(withTag: config.joystick.axisLockMode.tag)
            joystickAxisLockHoldDurationField.stringValue = String(format: "%.1f", config.joystick.axisLockHoldDuration)
            joystickAxisUnlockHoldDurationField.stringValue = String(format: "%.1f", config.joystick.axisUnlockHoldDuration)
        } else {
            config.action = .keyboard
            config.interactionMode = ButtonInteractionMode(tag: interactionModePopup.selectedTag()) ?? .momentary
            config.multiKeyActivationMode = MultiKeyActivationMode(tag: multiKeyActivationModePopup.selectedTag()) ?? .sequential
            config.rightClickFallsBackToPrimary = rightClickFallbackCheckbox.state == .on
            config.rightClickInteractionMode = ButtonInteractionMode(tag: rightClickModePopup.selectedTag())
        }

        let minimumSize = ButtonSizing.minimumSize(for: config.type)
        config.editorWidth = max(config.editorWidth, minimumSize.width)
        config.editorHeight = max(config.editorHeight, minimumSize.height)
        widthField.stringValue = geometryValueString(config.editorWidth)
        heightField.stringValue = geometryValueString(config.editorHeight)

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

        let previousBindings = config?.keyBindings ?? []
        config?.keyBindings = bindings
        config?.keyCode = bindings[0].keyCode
        config?.keyModifiers = bindings[0].keyModifiers
        let mode = preferredMultiKeyActivationMode(
            for: bindings,
            previousBindings: previousBindings,
            existingMode: config?.multiKeyActivationMode ?? .sequential
        )
        config?.multiKeyActivationMode = mode
        multiKeyActivationModePopup.selectItem(withTag: mode.tag)
        updateMultiKeyActivationModeVisibility(for: bindings)
    }

    private func applyRightClickKeyBindings(_ bindings: [ButtonKeyBinding]?) {
        guard config?.action.isProtectedSwitch != true else {
            return
        }
        guard config?.type != .systemEvent else {
            return
        }

        let normalizedBindings = bindings?.isEmpty == true ? nil : bindings
        let previousBindings = config?.rightClickKeyBindings ?? []
        config?.rightClickKeyBindings = normalizedBindings
        let mode = preferredMultiKeyActivationMode(
            for: normalizedBindings ?? [],
            previousBindings: previousBindings,
            existingMode: config?.multiKeyActivationMode ?? .sequential
        )
        config?.multiKeyActivationMode = mode
        multiKeyActivationModePopup.selectItem(withTag: mode.tag)
        rightClickRecorder.setOptionalKeyBindings(config?.rightClickKeyBindings)
        updateMultiKeyActivationModeVisibility()
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

        updateSelectedJoystickLayer { layer in
            switch direction {
            case .up:
                layer.up = binding
                joystickUpRecorder.setKeyBindings([binding])
            case .down:
                layer.down = binding
                joystickDownRecorder.setKeyBindings([binding])
            case .left:
                layer.left = binding
                joystickLeftRecorder.setKeyBindings([binding])
            case .right:
                layer.right = binding
                joystickRightRecorder.setKeyBindings([binding])
            }
        }
    }

    private func applyJoystickInputKeyBindings(_ bindings: [ButtonKeyBinding]?, target: JoystickInputTarget) {
        guard config?.action.isProtectedSwitch != true else {
            return
        }

        let normalizedBindings = bindings?.isEmpty == true ? nil : bindings
        switch target {
        case .leftClick:
            let previousBindings = selectedJoystickLayer(in: config?.joystick ?? .defaultBindings).leftClickAction.input.keyBindings
            let mode = preferredMultiKeyActivationMode(
                for: normalizedBindings ?? [],
                previousBindings: previousBindings,
                existingMode: selectedJoystickLayer(in: config?.joystick ?? .defaultBindings).leftClickAction.input.multiKeyActivationMode
            )
            updateSelectedJoystickLayer { layer in
                layer.leftClickAction.kind = normalizedBindings == nil ? .off : .keyCombo
                layer.leftClickAction.input.keyBindings = normalizedBindings ?? []
                layer.leftClickAction.input.multiKeyActivationMode = mode
            }
            joystickLeftClickActionPopup.selectItem(withTag: (normalizedBindings == nil ? JoystickTriggerActionKind.off : .keyCombo).tag)
            joystickLeftClickRecorder.setOptionalKeyBindings(normalizedBindings)
            joystickLeftClickMultiKeyPopup.selectItem(withTag: mode.tag)
        case .rightClick:
            let previousBindings = config?.joystick.rightClickAction.input.keyBindings ?? []
            let mode = preferredMultiKeyActivationMode(
                for: normalizedBindings ?? [],
                previousBindings: previousBindings,
                existingMode: config?.joystick.rightClickAction.input.multiKeyActivationMode ?? .sequential
            )
            if selectedJoystickLayerIndex == 0 {
                config?.joystick.rightClickAction.kind = normalizedBindings == nil ? .off : .keyCombo
                config?.joystick.rightClickAction.input.keyBindings = normalizedBindings ?? []
                config?.joystick.rightClickAction.input.multiKeyActivationMode = mode
            }
            joystickRightClickActionPopup.selectItem(withTag: (normalizedBindings == nil ? JoystickTriggerActionKind.off : .keyCombo).tag)
            joystickRightClickRecorder.setOptionalKeyBindings(normalizedBindings)
            joystickRightClickMultiKeyPopup.selectItem(withTag: mode.tag)
        case .scrollUp:
            let previousBindings = selectedJoystickLayer(in: config?.joystick ?? .defaultBindings).scrollUpAction.input.keyBindings
            let mode = preferredMultiKeyActivationMode(
                for: normalizedBindings ?? [],
                previousBindings: previousBindings,
                existingMode: selectedJoystickLayer(in: config?.joystick ?? .defaultBindings).scrollUpAction.input.multiKeyActivationMode
            )
            updateSelectedJoystickLayer { layer in
                layer.scrollUpAction.kind = normalizedBindings == nil ? .off : .keyCombo
                layer.scrollUpAction.input.keyBindings = normalizedBindings ?? []
                layer.scrollUpAction.input.multiKeyActivationMode = mode
            }
            joystickScrollUpActionPopup.selectItem(withTag: (normalizedBindings == nil ? JoystickScrollActionKind.off : .keyCombo).tag)
            joystickScrollUpRecorder.setOptionalKeyBindings(normalizedBindings)
            joystickScrollUpMultiKeyPopup.selectItem(withTag: mode.tag)
        case .scrollDown:
            let previousBindings = selectedJoystickLayer(in: config?.joystick ?? .defaultBindings).scrollDownAction.input.keyBindings
            let mode = preferredMultiKeyActivationMode(
                for: normalizedBindings ?? [],
                previousBindings: previousBindings,
                existingMode: selectedJoystickLayer(in: config?.joystick ?? .defaultBindings).scrollDownAction.input.multiKeyActivationMode
            )
            updateSelectedJoystickLayer { layer in
                layer.scrollDownAction.kind = normalizedBindings == nil ? .off : .keyCombo
                layer.scrollDownAction.input.keyBindings = normalizedBindings ?? []
                layer.scrollDownAction.input.multiKeyActivationMode = mode
            }
            joystickScrollDownActionPopup.selectItem(withTag: (normalizedBindings == nil ? JoystickScrollActionKind.off : .keyCombo).tag)
            joystickScrollDownRecorder.setOptionalKeyBindings(normalizedBindings)
            joystickScrollDownMultiKeyPopup.selectItem(withTag: mode.tag)
        }
    }

    private func preferredMultiKeyActivationMode(
        for bindings: [ButtonKeyBinding],
        previousBindings: [ButtonKeyBinding],
        existingMode: MultiKeyActivationMode
    ) -> MultiKeyActivationMode {
        guard bindings.count > 1 else {
            return .sequential
        }

        guard previousBindings.count <= 1 else {
            return existingMode
        }

        return bindings.contains { binding in
            Self.bindingContainsModifier(binding)
        } ? .simultaneous : existingMode
    }

    private static func bindingContainsModifier(_ binding: ButtonKeyBinding) -> Bool {
        if ButtonConfig.isModifierKey(code: binding.keyCode) {
            return true
        }

        let modifiers = NSEvent.ModifierFlags(rawValue: UInt(binding.keyModifiers))
        return modifiers.intersection([.command, .option, .control, .shift]).isEmpty == false
    }

    private func joystickInput(
        recorder: KeyRecorderButton,
        modePopup: NSPopUpButton,
        multiKeyPopup: NSPopUpButton
    ) -> JoystickInputConfig {
        let interactionMode = ButtonInteractionMode(tag: modePopup.selectedTag()) ?? .momentary
        let multiKeyActivationMode = MultiKeyActivationMode(tag: multiKeyPopup.selectedTag()) ?? .sequential

        return JoystickInputConfig(
            keyBindings: recorder.recordedBindings,
            interactionMode: interactionMode,
            multiKeyActivationMode: multiKeyActivationMode
        )
    }

    private func joystickTriggerAction(
        actionPopup: NSPopUpButton,
        recorder: KeyRecorderButton,
        modePopup: NSPopUpButton,
        multiKeyPopup: NSPopUpButton
    ) -> JoystickTriggerAction {
        let kind = JoystickTriggerActionKind(tag: actionPopup.selectedTag()) ?? .off
        switch kind {
        case .off:
            return .off
        case .keyCombo:
            return JoystickTriggerAction(
                kind: .keyCombo,
                input: joystickInput(recorder: recorder, modePopup: modePopup, multiKeyPopup: multiKeyPopup)
            )
        case .nestedJoystick:
            return .nestedJoystick
        }
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
        case .nestedJoystick:
            return .nestedJoystick
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

    private func syncJoystickTriggerControls(
        action: JoystickTriggerAction,
        actionPopup: NSPopUpButton,
        recorder: KeyRecorderButton,
        modePopup: NSPopUpButton,
        multiKeyPopup: NSPopUpButton
    ) {
        actionPopup.selectItem(withTag: action.kind.tag)
        syncJoystickInputControls(
            input: action.input,
            recorder: recorder,
            modePopup: modePopup,
            multiKeyPopup: multiKeyPopup
        )
    }

    private func syncJoystickLayerControls(from joystick: JoystickConfig) {
        let layer = selectedJoystickLayer(in: joystick)
        joystickUpRecorder.setKeyBindings([layer.up])
        joystickDownRecorder.setKeyBindings([layer.down])
        joystickLeftRecorder.setKeyBindings([layer.left])
        joystickRightRecorder.setKeyBindings([layer.right])
        syncJoystickTriggerControls(
            action: layer.leftClickAction,
            actionPopup: joystickLeftClickActionPopup,
            recorder: joystickLeftClickRecorder,
            modePopup: joystickLeftClickModePopup,
            multiKeyPopup: joystickLeftClickMultiKeyPopup
        )
        syncJoystickTriggerControls(
            action: selectedJoystickLayerIndex == 0 ? joystick.rightClickAction : .off,
            actionPopup: joystickRightClickActionPopup,
            recorder: joystickRightClickRecorder,
            modePopup: joystickRightClickModePopup,
            multiKeyPopup: joystickRightClickMultiKeyPopup
        )
        syncJoystickScrollControls(action: layer.scrollUpAction, direction: .up)
        syncJoystickScrollControls(action: layer.scrollDownAction, direction: .down)
        updateJoystickInputVisibility()
    }

    private func selectedJoystickLayer(in joystick: JoystickConfig) -> JoystickLayerConfig {
        guard selectedJoystickLayerIndex > 0,
              selectedJoystickLayerIndex - 1 < joystick.nestedLayers.count else {
            return JoystickLayerConfig(
                up: joystick.up,
                down: joystick.down,
                left: joystick.left,
                right: joystick.right,
                leftClickAction: joystick.leftClickAction,
                scrollUpAction: joystick.scrollUpAction,
                scrollDownAction: joystick.scrollDownAction
            )
        }

        return joystick.nestedLayers[selectedJoystickLayerIndex - 1]
    }

    private func ensureNestedJoystickLayers(in joystick: inout JoystickConfig, through layerIndex: Int) {
        guard layerIndex > 0 else {
            return
        }

        let requiredCount = min(layerIndex, JoystickConfig.maxLayerCount - 1)
        while joystick.nestedLayers.count < requiredCount {
            joystick.nestedLayers.append(.defaultBindings)
        }

        if joystick.nestedLayers.count > JoystickConfig.maxLayerCount - 1 {
            joystick.nestedLayers = Array(joystick.nestedLayers.prefix(JoystickConfig.maxLayerCount - 1))
        }
    }

    private func ensureNextNestedJoystickLayerIfNeeded(in joystick: inout JoystickConfig) {
        guard selectedJoystickLayerIndex + 1 < JoystickConfig.maxLayerCount else {
            return
        }

        let layer = selectedJoystickLayer(in: joystick)
        let usesNestedTrigger = layer.leftClickAction.kind == .nestedJoystick
            || layer.scrollUpAction.kind == .nestedJoystick
            || layer.scrollDownAction.kind == .nestedJoystick
        guard usesNestedTrigger else {
            return
        }

        ensureNestedJoystickLayers(in: &joystick, through: selectedJoystickLayerIndex + 1)
    }

    private func updateSelectedJoystickLayer(_ update: (inout JoystickLayerConfig) -> Void) {
        guard var config else {
            return
        }

        if selectedJoystickLayerIndex == 0 {
            var layer = selectedJoystickLayer(in: config.joystick)
            update(&layer)
            config.joystick.up = layer.up
            config.joystick.down = layer.down
            config.joystick.left = layer.left
            config.joystick.right = layer.right
            config.joystick.leftClickAction = layer.leftClickAction
            config.joystick.scrollUpAction = layer.scrollUpAction
            config.joystick.scrollDownAction = layer.scrollDownAction
        } else {
            ensureNestedJoystickLayers(in: &config.joystick, through: selectedJoystickLayerIndex)
            var layer = config.joystick.nestedLayers[selectedJoystickLayerIndex - 1]
            update(&layer)
            config.joystick.nestedLayers[selectedJoystickLayerIndex - 1] = layer
        }

        self.config = config
    }

    private func updateMultiKeyActivationModeVisibility(for bindings: [ButtonKeyBinding]? = nil) {
        let currentBindings = bindings ?? config?.keyBindings ?? []
        let rightClickBindings = config?.rightClickKeyBindings ?? []
        multiKeyActivationModeRow?.isHidden = currentBindings.count <= 1 && rightClickBindings.count <= 1
        updateJoystickInputVisibility()
    }

    private func updateJoystickInputVisibility() {
        let isJoystick = config?.type == .joystick && config?.action.isProtectedSwitch != true
        let isBaseLayer = selectedJoystickLayerIndex == 0
        let operationMode = JoystickOperationMode(tag: joystickOperationModePopup.selectedTag()) ?? .capture
        let leftClickKind = JoystickTriggerActionKind(tag: joystickLeftClickActionPopup.selectedTag()) ?? .off
        let rightClickKind = JoystickTriggerActionKind(tag: joystickRightClickActionPopup.selectedTag()) ?? .off
        let showsLeftClickKeyCombo = isJoystick && leftClickKind == .keyCombo
        let showsRightClickAction = isJoystick && isBaseLayer && operationMode == .clickDrag
        let showsRightClickKeyCombo = showsRightClickAction && rightClickKind == .keyCombo

        joystickLeftClickActionRow?.isHidden = !isJoystick
        joystickLeftClickKeyRow?.isHidden = !showsLeftClickKeyCombo
        joystickLeftClickModeRow?.isHidden = !showsLeftClickKeyCombo
        joystickLeftClickMultiKeyRow?.isHidden = !showsLeftClickKeyCombo
            || joystickLeftClickRecorder.recordedBindings.count <= 1
        joystickRightClickActionRow?.isHidden = !showsRightClickAction
        joystickRightClickKeyRow?.isHidden = !showsRightClickKeyCombo
        joystickRightClickModeRow?.isHidden = !showsRightClickKeyCombo
        joystickRightClickMultiKeyRow?.isHidden = !showsRightClickKeyCombo
            || joystickRightClickRecorder.recordedBindings.count <= 1

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
        let isJoystick = config?.type == .joystick && config?.action.isProtectedSwitch != true
        let isKeyCombo = JoystickScrollActionKind(tag: actionPopup.selectedTag()) == .keyCombo
        keyRow?.isHidden = !isJoystick || !isKeyCombo
        modeRow?.isHidden = !isJoystick || !isKeyCombo
        multiKeyRow?.isHidden = !isJoystick
            || !isKeyCombo
            || recorder.recordedBindings.count <= 1
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
        let isDwellAction = config?.type == .dwellAction
        let joystickAxisLockMode = JoystickAxisLockMode(tag: joystickAxisLockModePopup.selectedTag()) ?? .scrollWheel
        updateJoystickTriggerActionOptions()
        updateJoystickScrollActionOptions(axisLockMode: joystickAxisLockMode)
        let showsHoldDirectionAxisLock = isJoystick && joystickAxisLockMode == .holdDirection
        let isSystemEvent = config?.type == .systemEvent
        let hidesKeyboardControls = isProtectedSwitch || isJoystick || isSystemEvent || isDwellAction

        labelRow?.isHidden = isSystemEvent || isDwellAction
        labelStyleRow?.isHidden = isSystemEvent || isDwellAction
        buttonTypeRow?.isHidden = isProtectedSwitch
        systemEventRow?.isHidden = !isSystemEvent || isProtectedSwitch
        systemEventIconSizeRow?.isHidden = !(isSystemEvent || isDwellAction) || isProtectedSwitch
        dwellActionRow?.isHidden = !isDwellAction || isProtectedSwitch
        dwellTimerRow?.isHidden = !isDwellAction || isProtectedSwitch
        dwellToleranceRow?.isHidden = !isDwellAction || isProtectedSwitch
        keyRow?.isHidden = hidesKeyboardControls
        interactionModeRow?.isHidden = hidesKeyboardControls
        rightClickSectionLabel?.isHidden = hidesKeyboardControls
        rightClickKeyRow?.isHidden = hidesKeyboardControls
        rightClickFallbackRow?.isHidden = hidesKeyboardControls
        rightClickModeRow?.isHidden = hidesKeyboardControls
        joystickSectionLabel?.isHidden = !isJoystick || isProtectedSwitch
        joystickOperationModeRow?.isHidden = !isJoystick || isProtectedSwitch
        joystickLayerRow?.isHidden = !isJoystick || isProtectedSwitch
        joystickAxisLockModeRow?.isHidden = !isJoystick || isProtectedSwitch
        joystickAxisLockHoldDurationRow?.isHidden = !showsHoldDirectionAxisLock || isProtectedSwitch
        joystickUpRow?.isHidden = !isJoystick || isProtectedSwitch
        joystickDownRow?.isHidden = !isJoystick || isProtectedSwitch
        joystickLeftRow?.isHidden = !isJoystick || isProtectedSwitch
        joystickRightRow?.isHidden = !isJoystick || isProtectedSwitch
        joystickLeftClickActionRow?.isHidden = !isJoystick || isProtectedSwitch
        joystickLeftClickKeyRow?.isHidden = !isJoystick || isProtectedSwitch
        joystickLeftClickModeRow?.isHidden = !isJoystick || isProtectedSwitch
        joystickRightClickActionRow?.isHidden = !isJoystick || isProtectedSwitch
        joystickRightClickKeyRow?.isHidden = !isJoystick || isProtectedSwitch
        joystickRightClickModeRow?.isHidden = !isJoystick || isProtectedSwitch
        joystickScrollSectionLabel?.isHidden = !isJoystick || isProtectedSwitch
        joystickScrollUpActionRow?.isHidden = !isJoystick || isProtectedSwitch
        joystickScrollDownActionRow?.isHidden = !isJoystick || isProtectedSwitch

        if hidesKeyboardControls {
            multiKeyActivationModeRow?.isHidden = true
        } else {
            updateMultiKeyActivationModeVisibility()
        }
        updateJoystickInputVisibility()
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

        return parsedValue.rounded()
    }

    private func geometryValue(from stringValue: String, fallback: Double) -> Double {
        guard let parsedValue = Double(stringValue), parsedValue.isFinite else {
            return fallback
        }

        return parsedValue.rounded()
    }

    private func geometryValueString(_ value: Double) -> String {
        let roundedValue = value.rounded()
        if abs(value - roundedValue) < 0.0001 {
            return String(format: "%.0f", roundedValue)
        }

        return String(format: "%.1f", value)
    }

    private func durationValue(from stringValue: String, fallback: Double) -> Double {
        guard let parsedValue = Double(stringValue), parsedValue.isFinite else {
            return fallback
        }

        return max(0.1, parsedValue)
    }

    private func clampedWholeSeconds(from stringValue: String) -> Int {
        guard let parsedValue = Double(stringValue), parsedValue.isFinite else {
            return 1
        }

        return max(1, Int(parsedValue.rounded()))
    }

    private func toleranceValue(from stringValue: String, fallback: Double) -> Double {
        guard let parsedValue = Double(stringValue), parsedValue.isFinite else {
            return fallback
        }

        return max(0, parsedValue)
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
        [.keyboard, .joystick, .systemEvent, .dwellAction]
    }

    var displayName: String {
        switch self {
        case .keyboard:
            return "Keyboard"
        case .joystick:
            return "Joystick"
        case .systemEvent:
            return "System Event"
        case .dwellAction:
            return "Dwell Action"
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
        case .dwellAction:
            return 3
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
        case 3:
            self = .dwellAction
        default:
            return nil
        }
    }
}

private extension DwellActionKind {
    static var allCases: [DwellActionKind] {
        [
            .leftClick,
            .doubleClick,
            .rightClick,
            .middleClick,
            .holdLeftClick,
            .holdRightClick,
            .holdMiddleClick,
            .scrollUp,
            .scrollDown,
        ]
    }

    var tag: Int {
        switch self {
        case .leftClick:
            return 0
        case .doubleClick:
            return 1
        case .rightClick:
            return 2
        case .middleClick:
            return 3
        case .holdLeftClick:
            return 4
        case .holdRightClick:
            return 5
        case .holdMiddleClick:
            return 6
        case .scrollUp:
            return 7
        case .scrollDown:
            return 8
        }
    }

    init?(tag: Int) {
        switch tag {
        case 0:
            self = .leftClick
        case 1:
            self = .doubleClick
        case 2:
            self = .rightClick
        case 3:
            self = .middleClick
        case 4:
            self = .holdLeftClick
        case 5:
            self = .holdRightClick
        case 6:
            self = .holdMiddleClick
        case 7:
            self = .scrollUp
        case 8:
            self = .scrollDown
        default:
            return nil
        }
    }
}

private extension JoystickOperationMode {
    static var allCases: [JoystickOperationMode] {
        [.capture, .clickDrag]
    }

    var displayName: String {
        switch self {
        case .capture:
            return "Capture"
        case .clickDrag:
            return "Click Drag"
        }
    }

    var tag: Int {
        switch self {
        case .capture:
            return 0
        case .clickDrag:
            return 1
        }
    }

    init?(tag: Int) {
        switch tag {
        case 0:
            self = .capture
        case 1:
            self = .clickDrag
        default:
            return nil
        }
    }
}

private extension JoystickAxisLockMode {
    static var allCases: [JoystickAxisLockMode] {
        [.off, .scrollWheel, .holdDirection]
    }

    var displayName: String {
        switch self {
        case .off:
            return "Off"
        case .scrollWheel:
            return "Scroll Wheel"
        case .holdDirection:
            return "Hold Direction"
        }
    }

    var tag: Int {
        switch self {
        case .off:
            return 2
        case .scrollWheel:
            return 0
        case .holdDirection:
            return 1
        }
    }

    init?(tag: Int) {
        switch tag {
        case 0:
            self = .scrollWheel
        case 1:
            self = .holdDirection
        case 2:
            self = .off
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
    static func allCases(includeAxisLock: Bool = true, includeNested: Bool = true) -> [JoystickScrollActionKind] {
        var cases: [JoystickScrollActionKind] = includeAxisLock ? [.off, .axisLock, .keyCombo] : [.off, .keyCombo]
        if includeNested {
            cases.append(.nestedJoystick)
        }
        return cases
    }

    var displayName: String {
        switch self {
        case .off:
            return "Off"
        case .axisLock:
            return "Axis Lock"
        case .keyCombo:
            return "Key/Combo"
        case .nestedJoystick:
            return "Nested Joystick"
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
        case .nestedJoystick:
            return 3
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
        case 3:
            self = .nestedJoystick
        default:
            return nil
        }
    }
}

private extension JoystickTriggerActionKind {
    static func allCases(includeNested: Bool) -> [JoystickTriggerActionKind] {
        includeNested ? [.off, .keyCombo, .nestedJoystick] : [.off, .keyCombo]
    }

    var displayName: String {
        switch self {
        case .off:
            return "Off"
        case .keyCombo:
            return "Key/Combo"
        case .nestedJoystick:
            return "Nested Joystick"
        }
    }

    var tag: Int {
        switch self {
        case .off:
            return 0
        case .keyCombo:
            return 1
        case .nestedJoystick:
            return 2
        }
    }

    init?(tag: Int) {
        switch tag {
        case 0:
            self = .off
        case 1:
            self = .keyCombo
        case 2:
            self = .nestedJoystick
        default:
            return nil
        }
    }
}
