import Cocoa

final class ButtonEditorViewController: NSViewController {

    private final class PreviewCanvasView: NSView {
        let previewView: GamepadPreviewView
        var showsGrid = true {
            didSet { needsDisplay = true }
        }
        private let workspaceSize = CGSize(width: 1000, height: 1000)

        init(previewView: GamepadPreviewView) {
            self.previewView = previewView
            super.init(frame: .zero)
            wantsLayer = true
            addSubview(previewView)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)

            NSColor(white: 0.13, alpha: 1).setFill()
            dirtyRect.fill()

            guard showsGrid else { return }

            drawGrid(spacing: 10, color: NSColor.white.withAlphaComponent(0.05))
            drawGrid(spacing: 50, color: NSColor.white.withAlphaComponent(0.10))

            let workspaceBorder = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5))
            NSColor.white.withAlphaComponent(0.18).setStroke()
            workspaceBorder.lineWidth = 1
            workspaceBorder.stroke()
        }

        override func layout() {
            super.layout()
            previewView.frame = bounds
        }

        func updateCanvasSize() {
            if frame.size != workspaceSize {
                frame = CGRect(origin: .zero, size: workspaceSize)
            }

            needsLayout = true
            needsDisplay = true
        }

        private func drawGrid(spacing: CGFloat, color: NSColor) {
            let path = NSBezierPath()

            var x: CGFloat = 0
            while x <= bounds.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.line(to: CGPoint(x: x, y: bounds.height))
                x += spacing
            }

            var y: CGFloat = 0
            while y <= bounds.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.line(to: CGPoint(x: bounds.width, y: y))
                y += spacing
            }

            color.setStroke()
            path.lineWidth = 1
            path.stroke()
        }
    }

    var onProfileSaved: ((Profile) -> Void)?

    private static let maximumWorkspaceSize = CGSize(width: 1000, height: 1000)
    private static let buttonCountWarningThreshold = 100

    private var profile = ProfileStore.shared.activeProfile
    private var canvasObjects: [CanvasButtonObject] = []
    private var profileIDsWarnedForHighButtonCount = Set<UUID>()

    private let nameField = NSTextField()
    private let opacitySlider = NSSlider()
    private let opacityLabel = NSTextField(labelWithString: "90%")
    private let padWidthField = NSTextField()
    private let padHeightField = NSTextField()
    private let compatibilityModeCheckbox = NSButton(checkboxWithTitle: "Compatibility Mode", target: nil, action: nil)
    private let showGridCheckbox = NSButton(checkboxWithTitle: "Show Grid", target: nil, action: nil)
    private let previewView = GamepadPreviewView()
    private lazy var previewCanvasView = PreviewCanvasView(previewView: previewView)
    private let previewScrollView = NSScrollView()
    private let detailPanel = ButtonDetailPanel()
    private let leftColumn = NSStackView()
    private let hint = NSTextField(
        labelWithString: "Drag buttons freely inside a 1000 × 1000 workspace. Saving fits the gamepad to the outermost button bounds."
    )

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 980, height: 700))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildLayout()
        load(profile: ProfileStore.shared.activeProfile)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        updatePreviewCanvasLayout()
    }

    func load(profile: Profile) {
        self.profile = makeEditableProfile(from: profile)
        previewView.usesCenteredOrigin = profile.editorCoordinateMode == .centered
        clampEditableProfileToWorkspace()
        canvasObjects = makeCanvasObjects(from: self.profile)
        nameField.stringValue = self.profile.name
        opacitySlider.doubleValue = self.profile.opacity
        opacityLabel.stringValue = "\(Int(self.profile.opacity * 100))%"
        compatibilityModeCheckbox.state = self.profile.compatibilityMode ? .on : .off
        refreshFittedPadSizeFields()
        updatePreviewCanvasLayout()
        previewView.reload(objects: canvasObjects, keepSelection: false)
        detailPanel.clear()
        scrollPreviewToProfileContent()
    }

    func refreshFromStoreIfNeeded() {
        if let updatedProfile = ProfileStore.shared.profiles.first(where: { $0.id == profile.id }) {
            load(profile: updatedProfile)
        } else {
            load(profile: ProfileStore.shared.activeProfile)
        }
    }

    private func buildLayout() {
        previewView.maximumWorkspaceSize = Self.maximumWorkspaceSize
        nameField.placeholderString = "Profile name"
        nameField.bezelStyle = .roundedBezel
        nameField.font = .systemFont(ofSize: 12)

        opacitySlider.minValue = 0.25
        opacitySlider.maxValue = 1.0
        opacitySlider.isContinuous = true
        opacitySlider.target = self
        opacitySlider.action = #selector(opacityMoved)

        padWidthField.bezelStyle = .roundedBezel
        padWidthField.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        padWidthField.isEditable = false
        padWidthField.isSelectable = false
        padHeightField.bezelStyle = .roundedBezel
        padHeightField.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        padHeightField.isEditable = false
        padHeightField.isSelectable = false
        compatibilityModeCheckbox.target = self
        compatibilityModeCheckbox.action = #selector(compatibilityModeChanged)
        showGridCheckbox.state = .on
        showGridCheckbox.target = self
        showGridCheckbox.action = #selector(showGridChanged)

        let saveButton = NSButton(title: "Save & Apply", target: self, action: #selector(saveProfile))
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"

        let addButton = NSButton(title: "Add Button", target: self, action: #selector(addButtonPressed))
        addButton.bezelStyle = .rounded

        let topBar = NSStackView(views: [
            makeLabel("Name:"),
            nameField,
            makeLabel("  Opacity:"),
            opacitySlider,
            opacityLabel,
            makeLabel("  Fit:"),
            padWidthField,
            makeLabel("×"),
            padHeightField,
            compatibilityModeCheckbox,
            showGridCheckbox,
            NSView(),
            addButton,
            saveButton,
        ])
        topBar.orientation = .horizontal
        topBar.alignment = .centerY
        topBar.spacing = 6
        topBar.translatesAutoresizingMaskIntoConstraints = false

        previewScrollView.translatesAutoresizingMaskIntoConstraints = false
        previewScrollView.hasVerticalScroller = true
        previewScrollView.hasHorizontalScroller = true
        previewScrollView.borderType = .bezelBorder
        previewScrollView.drawsBackground = false
        previewScrollView.documentView = previewCanvasView

        previewView.onSelectionChanged = { [weak self] selectedIDs in
            guard let self else {
                return
            }

            guard selectedIDs.count == 1, let button = selectedIDs.first, let config = self.profile.buttons[button.rawValue] else {
                self.detailPanel.clear()
                return
            }

            self.detailPanel.load(button: button, config: config)
        }
        previewView.onGeometryChanged = { [weak self] proposedGeometries in
            guard let self else {
                return proposedGeometries
            }

            return self.applyCanvasGeometries(proposedGeometries)
        }
        previewView.onGeometryChangeCompleted = { [weak self] beforeFrames, afterFrames in
            self?.registerGeometryUndo(before: beforeFrames, after: afterFrames)
        }

        detailPanel.translatesAutoresizingMaskIntoConstraints = false
        detailPanel.onChanged = { [weak self] button, config in
            guard let self else {
                return
            }

            self.profile.buttons[button.rawValue] = self.configByApplyingGeometryClamp(config)
            self.syncWorkspaceAfterGeometryChange(selectedButton: button)
            self.previewView.reload(objects: self.canvasObjects, keepSelection: true)
        }
        detailPanel.onDelete = { [weak self] button in
            self?.deleteButton(button)
        }

        hint.font = .systemFont(ofSize: 10)
        hint.textColor = .secondaryLabelColor
        hint.translatesAutoresizingMaskIntoConstraints = false

        leftColumn.orientation = .vertical
        leftColumn.alignment = .leading
        leftColumn.spacing = 6
        leftColumn.translatesAutoresizingMaskIntoConstraints = false
        leftColumn.addArrangedSubview(previewScrollView)
        leftColumn.addArrangedSubview(hint)

        let preferredPreviewWidthConstraint = leftColumn.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.60)
        preferredPreviewWidthConstraint.priority = .defaultHigh

        [topBar, leftColumn, detailPanel].forEach(view.addSubview(_:))

        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            topBar.heightAnchor.constraint(equalToConstant: 28),
            nameField.widthAnchor.constraint(equalToConstant: 130),
            opacitySlider.widthAnchor.constraint(equalToConstant: 90),
            opacityLabel.widthAnchor.constraint(equalToConstant: 36),
            padWidthField.widthAnchor.constraint(equalToConstant: 52),
            padHeightField.widthAnchor.constraint(equalToConstant: 52),
            leftColumn.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 14),
            leftColumn.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            leftColumn.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
            leftColumn.widthAnchor.constraint(greaterThanOrEqualToConstant: 520),
            leftColumn.widthAnchor.constraint(lessThanOrEqualToConstant: 900),
            preferredPreviewWidthConstraint,
            previewScrollView.widthAnchor.constraint(equalTo: leftColumn.widthAnchor),
            previewScrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 420),
            hint.widthAnchor.constraint(equalTo: leftColumn.widthAnchor),
            detailPanel.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 14),
            detailPanel.leadingAnchor.constraint(equalTo: leftColumn.trailingAnchor, constant: 20),
            detailPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            detailPanel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
            detailPanel.widthAnchor.constraint(greaterThanOrEqualToConstant: 300),
        ])
    }

    private func makeLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12)
        return label
    }

    private func makeNewButtonConfig() -> ButtonConfig {
        let width = 80.0
        let height = 44.0

        return ButtonConfig(
            x: 0,
            y: 0,
            width: width,
            height: height,
            editorWidth: width,
            editorHeight: height,
            colorHex: "#4C8DFF",
            keyCode: 49,
            keyModifiers: 0,
            label: nextCustomButtonLabel(),
            enabled: true
        )
    }

    private func nextCustomButtonLabel() -> String {
        let nextNumber = profile.buttons.values.reduce(0) { currentMax, config in
            let label = config.label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard label.hasPrefix("Custom ") else {
                return currentMax
            }

            let suffix = label.dropFirst("Custom ".count)
            return max(currentMax, Int(suffix) ?? 0)
        } + 1

        return "Custom \(nextNumber)"
    }

    private var enabledButtonCount: Int {
        profile.buttons.values.filter(\.enabled).count
    }

    @objc private func opacityMoved() {
        profile.opacity = opacitySlider.doubleValue
        opacityLabel.stringValue = "\(Int(profile.opacity * 100))%"
    }

    @objc private func compatibilityModeChanged() {
        profile.compatibilityMode = compatibilityModeCheckbox.state == .on
        previewView.reload(objects: canvasObjects, keepSelection: true)
    }

    @objc private func showGridChanged() {
        previewCanvasView.showsGrid = showGridCheckbox.state == .on
    }

    @objc private func addButtonPressed() {
        guard confirmAddingButtonIfNeeded() else {
            return
        }

        let button = GamepadButton.generated()
        profile.buttons[button.rawValue] = makeNewButtonConfig()
        syncWorkspaceAfterGeometryChange(selectedButton: button)
        previewView.reload(objects: canvasObjects, keepSelection: false)
        previewView.select(button: button)
    }

    private func confirmAddingButtonIfNeeded() -> Bool {
        guard enabledButtonCount >= Self.buttonCountWarningThreshold else {
            return true
        }

        guard !profileIDsWarnedForHighButtonCount.contains(profile.id) else {
            return true
        }

        let alert = NSAlert()
        alert.messageText = "Add more than \(Self.buttonCountWarningThreshold) buttons?"
        alert.informativeText = "Large layouts can become harder to manage. You can keep adding buttons if this profile needs them."
        alert.addButton(withTitle: "Add Anyway")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else {
            return false
        }

        profileIDsWarnedForHighButtonCount.insert(profile.id)
        return true
    }

    private func deleteButton(_ button: GamepadButton) {
        profile.buttons.removeValue(forKey: button.rawValue)
        refreshFittedPadSizeFields()
        updatePreviewCanvasLayout()
        canvasObjects = makeCanvasObjects(from: profile)
        previewView.reload(objects: canvasObjects, keepSelection: false)
        detailPanel.clear()
    }

    @objc private func saveProfile() {
        if !nameField.stringValue.isEmpty {
            profile.name = nameField.stringValue
        }

        profile.compatibilityMode = compatibilityModeCheckbox.state == .on
        clampEditableProfileToWorkspace()
        let savedProfile = makeSavedProfile(from: profile).normalizedForSaving()
        profile = makeEditableProfile(from: savedProfile)
        previewView.usesCenteredOrigin = savedProfile.editorCoordinateMode == .centered
        clampEditableProfileToWorkspace()
        canvasObjects = makeCanvasObjects(from: profile)
        refreshFittedPadSizeFields()
        updatePreviewCanvasLayout()
        previewView.reload(objects: canvasObjects, keepSelection: true)

        onProfileSaved?(savedProfile)
        showSavedIndicator()
    }

    private func showSavedIndicator() {
        let savedLabel = NSTextField(labelWithString: "Saved")
        savedLabel.font = .boldSystemFont(ofSize: 12)
        savedLabel.textColor = .systemGreen
        savedLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(savedLabel)

        NSLayoutConstraint.activate([
            savedLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            savedLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
        ])

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            savedLabel.removeFromSuperview()
        }
    }

    private func updatePreviewCanvasLayout() {
        previewCanvasView.showsGrid = showGridCheckbox.state == .on
        previewCanvasView.updateCanvasSize()
        previewCanvasView.layoutSubtreeIfNeeded()
    }

    private func syncWorkspaceAfterGeometryChange(selectedButton: GamepadButton) {
        clampEditableProfileToWorkspace()
        refreshFittedPadSizeFields()
        updatePreviewCanvasLayout()
        canvasObjects = makeCanvasObjects(from: profile)

        guard let config = profile.buttons[selectedButton.rawValue] else {
            return
        }

        if let object = canvasObjects.first(where: { $0.id == selectedButton }) {
            previewView.syncObject(object)
        }
        detailPanel.refreshPosition(x: config.x, y: config.y, config: config)
        detailPanel.refreshSize(
            width: config.editorWidth > 0 ? config.editorWidth : config.width,
            height: config.editorHeight > 0 ? config.editorHeight : config.height
        )
    }

    private func makeCanvasObjects(from profile: Profile) -> [CanvasButtonObject] {
        profile.orderedButtonIDs.compactMap { button in
            guard let config = profile.buttons[button.rawValue], config.enabled else {
                return nil
            }

            return CanvasButtonObject(
                id: button,
                frame: editorFrame(for: config),
                label: config.resolvedDisplayLabel,
                colorHex: config.colorHex,
                labelFontSize: config.labelFontSize,
                labelBold: config.labelBold,
                labelItalic: config.labelItalic,
                isEnabled: config.enabled,
                isSelected: false
            )
        }
    }

    private func applyCanvasGeometries(
        _ proposedGeometries: [GamepadButton: ButtonEditorGeometry]
    ) -> [GamepadButton: ButtonEditorGeometry] {
        var appliedGeometries: [GamepadButton: ButtonEditorGeometry] = [:]

        for (button, proposedGeometry) in proposedGeometries {
            guard var config = profile.buttons[button.rawValue] else {
                continue
            }

            let appliedGeometry = clampedGeometry(proposedGeometry)
            config.x = appliedGeometry.centerX
            config.y = appliedGeometry.centerY
            config.editorWidth = appliedGeometry.width
            config.editorHeight = appliedGeometry.height
            profile.buttons[button.rawValue] = config
            appliedGeometries[button] = appliedGeometry
            syncCanvasObject(for: button, config: config)
        }

        refreshFittedPadSizeFields()
        updatePreviewCanvasLayout()

        if proposedGeometries.count == 1, let button = proposedGeometries.keys.first, let config = profile.buttons[button.rawValue] {
            detailPanel.refreshPosition(x: config.x, y: config.y, config: config)
            detailPanel.refreshSize(
                width: config.editorWidth > 0 ? config.editorWidth : config.width,
                height: config.editorHeight > 0 ? config.editorHeight : config.height
            )
        }

        return appliedGeometries
    }

    private func syncCanvasObject(for button: GamepadButton, config: ButtonConfig) {
        let object = CanvasButtonObject(
            id: button,
            frame: editorFrame(for: config),
            label: config.resolvedDisplayLabel,
            colorHex: config.colorHex,
            labelFontSize: config.labelFontSize,
            labelBold: config.labelBold,
            labelItalic: config.labelItalic,
            isEnabled: config.enabled,
            isSelected: false
        )

        if let index = canvasObjects.firstIndex(where: { $0.id == button }) {
            canvasObjects[index] = object
        } else if config.enabled {
            canvasObjects.append(object)
        }
    }

    private func registerGeometryUndo(before: [GamepadButton: CGRect], after: [GamepadButton: CGRect]) {
        guard !before.isEmpty, before != after else {
            return
        }

        view.window?.undoManager?.registerUndo(withTarget: self) { target in
            target.applyCanvasFrames(before, oppositeFrames: after)
        }
        view.window?.undoManager?.setActionName("Move/Resize Button")
    }

    private func applyCanvasFrames(_ frames: [GamepadButton: CGRect], oppositeFrames: [GamepadButton: CGRect]) {
        for (button, frame) in frames {
            guard var config = profile.buttons[button.rawValue] else {
                continue
            }

            config.x = frame.midX
            config.y = frame.midY
            config.editorWidth = frame.width
            config.editorHeight = frame.height
            profile.buttons[button.rawValue] = configByApplyingGeometryClamp(config)
        }

        clampEditableProfileToWorkspace()
        canvasObjects = makeCanvasObjects(from: profile)
        refreshFittedPadSizeFields()
        updatePreviewCanvasLayout()
        previewView.reload(objects: canvasObjects, keepSelection: true)

        if frames.count == 1, let button = frames.keys.first, let config = profile.buttons[button.rawValue] {
            detailPanel.refreshPosition(x: config.x, y: config.y, config: config)
            detailPanel.refreshSize(
                width: config.editorWidth > 0 ? config.editorWidth : config.width,
                height: config.editorHeight > 0 ? config.editorHeight : config.height
            )
        }

        view.window?.undoManager?.registerUndo(withTarget: self) { target in
            target.applyCanvasFrames(oppositeFrames, oppositeFrames: frames)
        }
        view.window?.undoManager?.setActionName("Move/Resize Button")
    }

    private func editorFrame(for config: ButtonConfig) -> CGRect {
        let width = config.editorWidth > 0 ? config.editorWidth : config.width
        let height = config.editorHeight > 0 ? config.editorHeight : config.height

        return CGRect(
            x: config.x - (width / 2),
            y: config.y - (height / 2),
            width: width,
            height: height
        )
    }

    private func makeEditableProfile(from savedProfile: Profile) -> Profile {
        var editableProfile = savedProfile

        for button in editableProfile.orderedButtonIDs {
            guard var config = editableProfile.buttons[button.rawValue] else {
                continue
            }

            let fallbackWidth = config.width * savedProfile.padWidth
            let fallbackHeight = config.height * savedProfile.padHeight

            switch savedProfile.editorCoordinateMode {
            case .legacyTopLeft:
                config.x *= savedProfile.padWidth
                config.y *= savedProfile.padHeight
            case .centered:
                config.x = (config.x * savedProfile.padWidth) - (savedProfile.padWidth / 2)
                config.y = (config.y * savedProfile.padHeight) - (savedProfile.padHeight / 2)
            }
            if config.editorWidth <= 0 {
                config.editorWidth = fallbackWidth
            }
            if config.editorHeight <= 0 {
                config.editorHeight = fallbackHeight
            }

            config.editorWidth = max(config.editorWidth, 20)
            config.editorHeight = max(config.editorHeight, 14)
            editableProfile.buttons[button.rawValue] = config
        }

        return editableProfile
    }

    private func makeSavedProfile(from editableProfile: Profile) -> Profile {
        var savedProfile = editableProfile
        guard let fittedSize = fittedPadSize(for: editableProfile) else {
            return savedProfile
        }

        let fittedWidth = max(1, fittedSize.width)
        let fittedHeight = max(1, fittedSize.height)
        savedProfile.padWidth = fittedWidth
        savedProfile.padHeight = fittedHeight
        let contentBounds = buttonContentBounds(for: editableProfile)

        for button in savedProfile.orderedButtonIDs {
            guard var config = savedProfile.buttons[button.rawValue] else {
                continue
            }

            switch editableProfile.editorCoordinateMode {
            case .legacyTopLeft:
                guard let contentBounds else {
                    continue
                }
                config.x = (config.x - contentBounds.minX) / fittedWidth
                config.y = (config.y - contentBounds.minY) / fittedHeight
            case .centered:
                config.x = (config.x + fittedWidth / 2) / fittedWidth
                config.y = (config.y + fittedHeight / 2) / fittedHeight
            }
            let editorWidth = config.editorWidth > 0 ? config.editorWidth : config.width
            let editorHeight = config.editorHeight > 0 ? config.editorHeight : config.height
            config.editorWidth = editorWidth
            config.editorHeight = editorHeight
            config.width = editorWidth / fittedWidth
            config.height = editorHeight / fittedHeight
            savedProfile.buttons[button.rawValue] = config
        }

        return savedProfile
    }

    private func refreshFittedPadSizeFields() {
        guard let fittedSize = fittedPadSize(for: profile) else {
            padWidthField.stringValue = "0"
            padHeightField.stringValue = "0"
            return
        }

        padWidthField.stringValue = "\(Int(ceil(fittedSize.width)))"
        padHeightField.stringValue = "\(Int(ceil(fittedSize.height)))"
    }

    private func buttonContentBounds(for profile: Profile) -> CGRect? {
        var contentBounds: CGRect?

        for button in profile.orderedButtonIDs {
            guard let config = profile.buttons[button.rawValue] else {
                continue
            }

            let buttonFrame = CGRect(
                x: config.x - ((config.editorWidth > 0 ? config.editorWidth : config.width) / 2),
                y: config.y - ((config.editorHeight > 0 ? config.editorHeight : config.height) / 2),
                width: config.editorWidth > 0 ? config.editorWidth : config.width,
                height: config.editorHeight > 0 ? config.editorHeight : config.height
            )

            contentBounds = contentBounds?.union(buttonFrame) ?? buttonFrame
        }

        return contentBounds
    }

    private func clampEditableProfileToWorkspace() {
        for button in profile.orderedButtonIDs {
            guard var config = profile.buttons[button.rawValue] else {
                continue
            }

            config = configByApplyingGeometryClamp(config)
            profile.buttons[button.rawValue] = config
        }
    }

    private func configByApplyingGeometryClamp(_ config: ButtonConfig) -> ButtonConfig {
        var config = config
        let geometry = ButtonEditorGeometry(
            centerX: config.x,
            centerY: config.y,
            width: config.editorWidth > 0 ? config.editorWidth : config.width,
            height: config.editorHeight > 0 ? config.editorHeight : config.height,
            anchoredResize: nil
        )
        let clamped = clampedGeometry(geometry)
        config.x = clamped.centerX
        config.y = clamped.centerY
        config.editorWidth = clamped.width
        config.editorHeight = clamped.height
        return config
    }

    private func clampedGeometry(_ geometry: ButtonEditorGeometry) -> ButtonEditorGeometry {
        if let anchoredResize = geometry.anchoredResize {
            return clampedAnchoredGeometry(geometry, anchoredResize: anchoredResize)
        }

        let maxWidth = Self.maximumWorkspaceSize.width
        let maxHeight = Self.maximumWorkspaceSize.height
        let width = min(max(geometry.width, 20), maxWidth)
        let height = min(max(geometry.height, 14), maxHeight)
        let halfWidth = width / 2
        let halfHeight = height / 2

        switch profile.editorCoordinateMode {
        case .legacyTopLeft:
            return ButtonEditorGeometry(
                centerX: min(max(geometry.centerX, halfWidth), maxWidth - halfWidth),
                centerY: min(max(geometry.centerY, halfHeight), maxHeight - halfHeight),
                width: width,
                height: height,
                anchoredResize: geometry.anchoredResize
            )
        case .centered:
            return ButtonEditorGeometry(
                centerX: min(max(geometry.centerX, -maxWidth / 2 + halfWidth), maxWidth / 2 - halfWidth),
                centerY: min(max(geometry.centerY, -maxHeight / 2 + halfHeight), maxHeight / 2 - halfHeight),
                width: width,
                height: height,
                anchoredResize: geometry.anchoredResize
            )
        }
    }

    private func clampedAnchoredGeometry(
        _ geometry: ButtonEditorGeometry,
        anchoredResize: AnchoredButtonResize
    ) -> ButtonEditorGeometry {
        let workspaceMinX: Double
        let workspaceMaxX: Double
        let workspaceMinY: Double
        let workspaceMaxY: Double

        switch profile.editorCoordinateMode {
        case .legacyTopLeft:
            workspaceMinX = 0
            workspaceMaxX = Self.maximumWorkspaceSize.width
            workspaceMinY = 0
            workspaceMaxY = Self.maximumWorkspaceSize.height
        case .centered:
            workspaceMinX = -Self.maximumWorkspaceSize.width / 2
            workspaceMaxX = Self.maximumWorkspaceSize.width / 2
            workspaceMinY = -Self.maximumWorkspaceSize.height / 2
            workspaceMaxY = Self.maximumWorkspaceSize.height / 2
        }

        let maxWidth = anchoredResize.resizesFromLeft
            ? anchoredResize.anchorX - workspaceMinX
            : workspaceMaxX - anchoredResize.anchorX
        let maxHeight = anchoredResize.resizesFromBottom
            ? anchoredResize.anchorY - workspaceMinY
            : workspaceMaxY - anchoredResize.anchorY
        let width = min(max(geometry.width, 20), max(20, maxWidth))
        let height = min(max(geometry.height, 14), max(14, maxHeight))
        let centerX = anchoredResize.resizesFromLeft
            ? anchoredResize.anchorX - (width / 2)
            : anchoredResize.anchorX + (width / 2)
        let centerY = anchoredResize.resizesFromBottom
            ? anchoredResize.anchorY - (height / 2)
            : anchoredResize.anchorY + (height / 2)

        return ButtonEditorGeometry(
            centerX: centerX,
            centerY: centerY,
            width: width,
            height: height,
            anchoredResize: anchoredResize
        )
    }

    private func fittedPadSize(for profile: Profile) -> CGSize? {
        guard let contentBounds = buttonContentBounds(for: profile) else {
            return nil
        }

        switch profile.editorCoordinateMode {
        case .legacyTopLeft:
            return contentBounds.size
        case .centered:
            return CGSize(
                width: max(abs(contentBounds.minX), abs(contentBounds.maxX)) * 2,
                height: max(abs(contentBounds.minY), abs(contentBounds.maxY)) * 2
            )
        }
    }

    private func scrollPreviewToProfileContent() {
        guard let contentBounds = canvasContentBounds(for: profile) else {
            let origin = CGPoint(
                x: max(0, (Self.maximumWorkspaceSize.width - previewScrollView.contentView.bounds.width) / 2),
                y: max(0, (Self.maximumWorkspaceSize.height - previewScrollView.contentView.bounds.height) / 2)
            )
            previewScrollView.contentView.scroll(to: origin)
            previewScrollView.reflectScrolledClipView(previewScrollView.contentView)
            return
        }

        let visibleSize = previewScrollView.contentView.bounds.size
        let documentSize = previewCanvasView.frame.size
        let targetOrigin = CGPoint(
            x: clamp(
                contentBounds.midX - visibleSize.width / 2,
                min: 0,
                max: max(0, documentSize.width - visibleSize.width)
            ),
            y: clamp(
                contentBounds.midY - visibleSize.height / 2,
                min: 0,
                max: max(0, documentSize.height - visibleSize.height)
            )
        )

        previewScrollView.contentView.scroll(to: targetOrigin)
        previewScrollView.reflectScrolledClipView(previewScrollView.contentView)
    }

    private func canvasContentBounds(for profile: Profile) -> CGRect? {
        guard let contentBounds = buttonContentBounds(for: profile) else {
            return nil
        }

        guard profile.editorCoordinateMode == .centered else {
            return contentBounds
        }

        return contentBounds.offsetBy(
            dx: Self.maximumWorkspaceSize.width / 2,
            dy: Self.maximumWorkspaceSize.height / 2
        )
    }

    private func clamp(_ value: CGFloat, min minimum: CGFloat, max maximum: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, minimum), maximum)
    }
}
