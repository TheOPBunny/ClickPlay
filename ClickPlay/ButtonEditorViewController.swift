import Cocoa

final class ButtonEditorViewController: NSViewController, NSMenuItemValidation, NSSplitViewDelegate {

    private struct ClipboardButton: Codable {
        var config: ButtonConfig
    }

    private enum AlignmentAction {
        case left
        case centerX
        case right
        case top
        case centerY
        case bottom
    }

    private enum EqualizeAction {
        case width
        case height
        case both
    }

    private enum SplitMetrics {
        static let minimumPreviewWidth: CGFloat = 420
        static let minimumInspectorWidth: CGFloat = 300
        static let defaultInspectorWidth: CGFloat = 320
    }

    private enum DefaultsKey {
        static let inspectorExpandedWidth = "Editor.inspectorExpandedWidth"
        static let inspectorCollapsed = "Editor.inspectorCollapsed"
    }

    private final class PreviewCanvasView: NSView {
        let previewView: GamepadPreviewView
        var showsGrid = true {
            didSet { needsDisplay = true }
        }
        private let workspaceSize = CGSize(width: 1000, height: 1000)
        private(set) var workspaceOrigin = CGPoint.zero

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

            let workspaceRect = CGRect(origin: workspaceOrigin, size: workspaceSize)
            drawGrid(in: workspaceRect, spacing: 10, color: NSColor.white.withAlphaComponent(0.05))
            drawGrid(in: workspaceRect, spacing: 50, color: NSColor.white.withAlphaComponent(0.10))

            let workspaceBorder = NSBezierPath(rect: workspaceRect.insetBy(dx: 0.5, dy: 0.5))
            NSColor.white.withAlphaComponent(0.18).setStroke()
            workspaceBorder.lineWidth = 1
            workspaceBorder.stroke()
        }

        override func layout() {
            super.layout()
            previewView.frame = bounds
        }

        func updateCanvasSize(visibleSize: CGSize) {
            let nextSize = CGSize(
                width: max(workspaceSize.width, visibleSize.width),
                height: workspaceSize.height
            )
            let nextWorkspaceOrigin = CGPoint(x: max(0, (nextSize.width - workspaceSize.width) / 2), y: 0)

            if frame.size != nextSize {
                frame = CGRect(origin: .zero, size: nextSize)
            }
            workspaceOrigin = nextWorkspaceOrigin
            previewView.workspaceOrigin = nextWorkspaceOrigin

            needsLayout = true
            needsDisplay = true
        }

        private func drawGrid(in rect: CGRect, spacing: CGFloat, color: NSColor) {
            let path = NSBezierPath()

            var x = rect.minX
            while x <= rect.maxX {
                path.move(to: CGPoint(x: x, y: rect.minY))
                path.line(to: CGPoint(x: x, y: rect.maxY))
                x += spacing
            }

            var y = rect.minY
            while y <= rect.maxY {
                path.move(to: CGPoint(x: rect.minX, y: y))
                path.line(to: CGPoint(x: rect.maxX, y: y))
                y += spacing
            }

            color.setStroke()
            path.lineWidth = 1
            path.stroke()
        }
    }

    var onProfileSaved: ((Profile) -> Void)?
    var onToggleSidebar: (() -> Void)?
    var onSavePanelLayout: (() -> Void)?

    private static let maximumWorkspaceSize = CGSize(width: 1000, height: 1000)
    private static let buttonCountWarningThreshold = 100
    private static let pasteOffset: Double = 18
    private static let snapThreshold: CGFloat = 5
    private static let pasteboardType = NSPasteboard.PasteboardType("com.clickplay.canvas-buttons")

    private var profile = ProfileStore.shared.activeResolvedProfile
    private var canvasObjects: [CanvasButtonObject] = []
    private var selectedIDs = Set<GamepadButton>()
    private var localClipboard: [ClipboardButton] = []
    private var pasteCount = 0
    private var profileIDsWarnedForHighButtonCount = Set<UUID>()
    private let editorUndoManager = UndoManager()
    private var isInspectorCollapsed = false
    private var lastExpandedInspectorWidth = SplitMetrics.defaultInspectorWidth
    private var hasRestoredInspectorLayout = false
    private var isApplyingInspectorLayout = false
    private var lastObservedEditorSplitWidth: CGFloat = 0

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
    private let editorSplitView = NSSplitView()
    private let leftColumn = NSStackView()
    private let hint = NSTextField(
        labelWithString: "Drag buttons freely inside a 1000 × 1000 workspace. Saving fits the gamepad to the outermost button bounds."
    )

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 980, height: 700))
    }

    override var undoManager: UndoManager? {
        editorUndoManager
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        loadInspectorDefaults()
        buildLayout()
        load(profile: ProfileStore.shared.activeResolvedProfile)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        restoreInspectorLayoutIfNeeded()
        updatePreviewCanvasLayout()
    }

    func load(profile: Profile) {
        editorUndoManager.removeAllActions()
        selectedIDs = []
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
        if let parentProfile = ProfileStore.shared.parentProfile(containingSubProfileID: profile.id),
           let updatedProfile = parentProfile.subProfiles.first(where: { $0.id == profile.id }) {
            load(profile: updatedProfile)
        } else if let updatedProfile = ProfileStore.shared.profiles.first(where: { $0.id == profile.id }) {
            load(profile: updatedProfile)
        } else {
            load(profile: ProfileStore.shared.activeResolvedProfile)
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

        let addJoystickButton = NSButton(title: "Add Joystick", target: self, action: #selector(addJoystickPressed))
        addJoystickButton.bezelStyle = .rounded

        let leftSidebarToggleButton = SidebarToggleButton()
        leftSidebarToggleButton.side = .left
        leftSidebarToggleButton.toolTip = "Toggle Profiles Sidebar"
        leftSidebarToggleButton.target = self
        leftSidebarToggleButton.action = #selector(toggleSidebarPressed)

        let rightInspectorToggleButton = SidebarToggleButton()
        rightInspectorToggleButton.side = .right
        rightInspectorToggleButton.toolTip = "Toggle Inspector"
        rightInspectorToggleButton.target = self
        rightInspectorToggleButton.action = #selector(toggleInspector)

        let topBar = NSStackView(views: [
            leftSidebarToggleButton,
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
            rightInspectorToggleButton,
            addButton,
            addJoystickButton,
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

            self.selectedIDs = selectedIDs
            guard selectedIDs.count == 1, let button = selectedIDs.first, let config = self.profile.buttons[button.rawValue] else {
                self.detailPanel.clear()
                return
            }

            self.detailPanel.load(button: button, config: config)
        }
        previewView.onGeometryChanged = { [weak self] proposedGeometries in
            guard let self else {
                return CanvasGeometryChangeResult(geometries: proposedGeometries, guides: [])
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

            let previousConfig = self.profile.buttons[button.rawValue]
            let nextConfig = self.configByApplyingGeometryClamp(config)
            self.profile.buttons[button.rawValue] = nextConfig
            self.registerButtonStateUndo(
                button: button,
                before: previousConfig,
                after: nextConfig,
                actionName: "Edit Button"
            )
            self.syncWorkspaceAfterGeometryChange(selectedButton: button)
            self.previewView.reload(objects: self.canvasObjects, keepSelection: true)
        }
        detailPanel.onDelete = { [weak self] button in
            self?.deleteButton(button)
        }

        hint.font = .systemFont(ofSize: 10)
        hint.textColor = .secondaryLabelColor
        hint.lineBreakMode = .byWordWrapping
        hint.translatesAutoresizingMaskIntoConstraints = false

        editorSplitView.isVertical = true
        editorSplitView.dividerStyle = .thin
        editorSplitView.delegate = self
        editorSplitView.translatesAutoresizingMaskIntoConstraints = false

        leftColumn.orientation = .vertical
        leftColumn.alignment = .width
        leftColumn.spacing = 6
        leftColumn.translatesAutoresizingMaskIntoConstraints = false
        leftColumn.addArrangedSubview(previewScrollView)
        leftColumn.addArrangedSubview(hint)

        editorSplitView.addArrangedSubview(leftColumn)
        editorSplitView.addArrangedSubview(detailPanel)
        editorSplitView.setHoldingPriority(.defaultLow, forSubviewAt: 0)
        editorSplitView.setHoldingPriority(.defaultHigh, forSubviewAt: 1)

        [topBar, editorSplitView].forEach(view.addSubview(_:))

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
            editorSplitView.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 14),
            editorSplitView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            editorSplitView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            editorSplitView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
            previewScrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 420),
        ])
    }

    @objc private func toggleSidebarPressed() {
        onToggleSidebar?()
    }

    @objc private func toggleInspector() {
        guard editorSplitView.arrangedSubviews.count > 1 else {
            return
        }

        let currentWidth = detailPanel.frame.width
        if isInspectorCollapsed {
            isInspectorCollapsed = false
            detailPanel.isHidden = false
            editorSplitView.adjustSubviews()
            setInspectorWidth(lastExpandedInspectorWidth)
        } else {
            if currentWidth >= SplitMetrics.minimumInspectorWidth {
                updateLastExpandedInspectorWidth(currentWidth)
            }

            isInspectorCollapsed = true
            detailPanel.isHidden = true
            editorSplitView.adjustSubviews()
        }

        saveInspectorDefaults()
    }

    func savePanelLayout() {
        if hasRestoredInspectorLayout {
            syncInspectorStateFromCurrentWidth()
        }
        saveInspectorDefaults()
    }

    private func setInspectorWidth(_ width: CGFloat) {
        let dividerPosition = editorSplitView.bounds.width - editorSplitView.dividerThickness - width
        isApplyingInspectorLayout = true
        editorSplitView.setPosition(max(SplitMetrics.minimumPreviewWidth, dividerPosition), ofDividerAt: 0)
        editorSplitView.layoutSubtreeIfNeeded()
        isApplyingInspectorLayout = false
    }

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        guard splitView == editorSplitView, dividerIndex == 0 else {
            return proposedMinimumPosition
        }

        return SplitMetrics.minimumPreviewWidth
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        guard splitView == editorSplitView, dividerIndex == 0 else {
            return proposedMaximumPosition
        }

        guard !isInspectorCollapsed, !detailPanel.isHidden else {
            return proposedMaximumPosition
        }

        return splitView.bounds.width - splitView.dividerThickness - SplitMetrics.minimumInspectorWidth
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        guard let splitView = notification.object as? NSSplitView, splitView == editorSplitView else {
            return
        }

        guard hasRestoredInspectorLayout else {
            return
        }

        let splitWidth = splitView.bounds.width
        let didResizeContainer = abs(splitWidth - lastObservedEditorSplitWidth) > 0.5
        lastObservedEditorSplitWidth = splitWidth

        if didResizeContainer {
            if !isInspectorCollapsed {
                setInspectorWidth(lastExpandedInspectorWidth)
            }
            return
        }

        guard !isApplyingInspectorLayout else {
            return
        }

        let inspectorWidth = detailPanel.frame.width
        syncInspectorStateFromCurrentWidth(inspectorWidth: inspectorWidth)
    }

    private func syncInspectorStateFromCurrentWidth(inspectorWidth: CGFloat? = nil) {
        guard !detailPanel.isHidden else {
            isInspectorCollapsed = true
            return
        }

        isInspectorCollapsed = false
        let inspectorWidth = inspectorWidth ?? detailPanel.frame.width
        if inspectorWidth >= SplitMetrics.minimumInspectorWidth {
            updateLastExpandedInspectorWidth(inspectorWidth)
            saveInspectorDefaults()
        }
    }

    private func restoreInspectorLayoutIfNeeded() {
        guard !hasRestoredInspectorLayout, editorSplitView.bounds.width > 0 else {
            return
        }

        hasRestoredInspectorLayout = true
        detailPanel.setCollapsed(false)
        detailPanel.isHidden = isInspectorCollapsed
        editorSplitView.adjustSubviews()
        lastObservedEditorSplitWidth = editorSplitView.bounds.width

        if !isInspectorCollapsed {
            setInspectorWidth(lastExpandedInspectorWidth)
        }
    }

    private func updateLastExpandedInspectorWidth(_ width: CGFloat) {
        lastExpandedInspectorWidth = max(width, SplitMetrics.minimumInspectorWidth)
    }

    private func loadInspectorDefaults() {
        let defaults = UserDefaults.standard
        isInspectorCollapsed = defaults.bool(forKey: DefaultsKey.inspectorCollapsed)

        let savedWidth = defaults.double(forKey: DefaultsKey.inspectorExpandedWidth)
        if savedWidth > 0 {
            updateLastExpandedInspectorWidth(savedWidth)
        }
    }

    private func saveInspectorDefaults() {
        let defaults = UserDefaults.standard
        defaults.set(isInspectorCollapsed, forKey: DefaultsKey.inspectorCollapsed)
        defaults.set(Double(lastExpandedInspectorWidth), forKey: DefaultsKey.inspectorExpandedWidth)
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

    private func makeNewJoystickConfig() -> ButtonConfig {
        ButtonConfig(
            type: .joystick,
            x: 0,
            y: 0,
            width: 96,
            height: 96,
            editorWidth: 96,
            editorHeight: 96,
            colorHex: "#35A889",
            keyCode: 13,
            keyModifiers: 0,
            label: "Joystick",
            shape: .oval,
            enabled: true,
            interactionMode: .momentary,
            rightClickKeyBindings: nil,
            rightClickFallsBackToPrimary: false,
            rightClickInteractionMode: nil,
            joystick: .defaultBindings
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

    @objc func undo(_ sender: Any?) {
        editorUndoManager.undo()
    }

    @objc func redo(_ sender: Any?) {
        editorUndoManager.redo()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(undo(_:)):
            menuItem.title = editorUndoManager.undoMenuItemTitle
            return editorUndoManager.canUndo
        case #selector(redo(_:)):
            menuItem.title = editorUndoManager.redoMenuItemTitle
            return editorUndoManager.canRedo
        case #selector(cut(_:)), #selector(copy(_:)), #selector(delete(_:)):
            if menuItem.action == #selector(copy(_:)) {
                return !selectedIDs.isEmpty && !isTextInputFirstResponder
            }

            return !deletableSelectedIDs.isEmpty && !isTextInputFirstResponder
        case #selector(paste(_:)):
            return canPasteButtons && !isTextInputFirstResponder
        case #selector(alignLeft(_:)), #selector(alignCenterX(_:)), #selector(alignRight(_:)),
             #selector(alignTop(_:)), #selector(alignCenterY(_:)), #selector(alignBottom(_:)),
             #selector(equalizeWidths(_:)), #selector(equalizeHeights(_:)), #selector(equalizeBoth(_:)):
            return selectedIDs.count >= 2 && !isTextInputFirstResponder
        case #selector(distributeHorizontally(_:)), #selector(distributeVertically(_:)):
            return selectedIDs.count >= 3 && !isTextInputFirstResponder
        default:
            return true
        }
    }

    @objc func cut(_ sender: Any?) {
        guard !isTextInputFirstResponder, copySelectedButtonsToPasteboard() else {
            return
        }

        deleteSelectedButtons(actionName: "Cut Buttons")
    }

    @objc func copy(_ sender: Any?) {
        guard !isTextInputFirstResponder else {
            return
        }

        _ = copySelectedButtonsToPasteboard()
    }

    @objc func paste(_ sender: Any?) {
        guard !isTextInputFirstResponder, let clipboardButtons = readClipboardButtons(), !clipboardButtons.isEmpty else {
            return
        }

        pasteCount += 1
        let offset = Double(pasteCount) * Self.pasteOffset
        var insertedStates: [GamepadButton: ButtonConfig?] = [:]
        var nextSelection = Set<GamepadButton>()

        for clipboardButton in clipboardButtons {
            let button = GamepadButton.generated()
            var config = clipboardButton.config
            config.x += offset
            config.y -= offset
            config.enabled = true
            config.action = .keyboard
            config = configByApplyingGeometryClamp(config)
            profile.buttons[button.rawValue] = config
            insertedStates[button] = config
            nextSelection.insert(button)
        }

        refreshEditorAfterButtonSetChange(selection: nextSelection)
        registerButtonSetUndo(before: Dictionary(uniqueKeysWithValues: insertedStates.keys.map { ($0, nil) }), after: insertedStates, actionName: "Paste Buttons")
    }

    @objc func delete(_ sender: Any?) {
        guard !isTextInputFirstResponder else {
            return
        }

        deleteSelectedButtons(actionName: "Delete Buttons")
    }

    @objc func alignLeft(_ sender: Any?) {
        alignSelectedButtons(.left)
    }

    @objc func alignCenterX(_ sender: Any?) {
        alignSelectedButtons(.centerX)
    }

    @objc func alignRight(_ sender: Any?) {
        alignSelectedButtons(.right)
    }

    @objc func alignTop(_ sender: Any?) {
        alignSelectedButtons(.top)
    }

    @objc func alignCenterY(_ sender: Any?) {
        alignSelectedButtons(.centerY)
    }

    @objc func alignBottom(_ sender: Any?) {
        alignSelectedButtons(.bottom)
    }

    @objc func distributeHorizontally(_ sender: Any?) {
        distributeSelectedButtons(horizontal: true)
    }

    @objc func distributeVertically(_ sender: Any?) {
        distributeSelectedButtons(horizontal: false)
    }

    @objc func equalizeWidths(_ sender: Any?) {
        equalizeSelectedButtons(.width)
    }

    @objc func equalizeHeights(_ sender: Any?) {
        equalizeSelectedButtons(.height)
    }

    @objc func equalizeBoth(_ sender: Any?) {
        equalizeSelectedButtons(.both)
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
        let config = makeNewButtonConfig()
        profile.buttons[button.rawValue] = config
        registerButtonStateUndo(button: button, before: nil, after: config, actionName: "Add Button")
        syncWorkspaceAfterGeometryChange(selectedButton: button)
        previewView.reload(objects: canvasObjects, keepSelection: false)
        previewView.select(button: button)
    }

    @objc private func addJoystickPressed() {
        guard confirmAddingButtonIfNeeded() else {
            return
        }

        let button = GamepadButton.generated()
        let config = makeNewJoystickConfig()
        profile.buttons[button.rawValue] = config
        registerButtonStateUndo(button: button, before: nil, after: config, actionName: "Add Joystick")
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
        guard !isProtectedSwitchButton(button) else {
            return
        }

        let previousConfig = profile.buttons[button.rawValue]
        profile.buttons.removeValue(forKey: button.rawValue)
        registerButtonStateUndo(button: button, before: previousConfig, after: nil, actionName: "Delete Button")
        refreshFittedPadSizeFields()
        updatePreviewCanvasLayout()
        canvasObjects = makeCanvasObjects(from: profile)
        previewView.reload(objects: canvasObjects, keepSelection: false)
        detailPanel.clear()
    }

    private var isTextInputFirstResponder: Bool {
        guard let firstResponder = view.window?.firstResponder else {
            return false
        }

        if firstResponder is NSTextView {
            return true
        }

        if let control = firstResponder as? NSControl {
            return control.currentEditor() != nil
        }

        return false
    }

    private var canPasteButtons: Bool {
        !localClipboard.isEmpty || NSPasteboard.general.availableType(from: [Self.pasteboardType]) != nil
    }

    private func copySelectedButtonsToPasteboard() -> Bool {
        let clipboardButtons = profile.orderedButtonIDs.compactMap { button -> ClipboardButton? in
            guard selectedIDs.contains(button), let config = profile.buttons[button.rawValue] else {
                return nil
            }

            return ClipboardButton(config: config)
        }

        guard !clipboardButtons.isEmpty else {
            return false
        }

        localClipboard = clipboardButtons
        if let data = try? JSONEncoder().encode(clipboardButtons) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setData(data, forType: Self.pasteboardType)
        }

        return true
    }

    private func readClipboardButtons() -> [ClipboardButton]? {
        if let data = NSPasteboard.general.data(forType: Self.pasteboardType),
           let decodedButtons = try? JSONDecoder().decode([ClipboardButton].self, from: data) {
            localClipboard = decodedButtons
            return decodedButtons
        }

        return localClipboard.isEmpty ? nil : localClipboard
    }

    private func deleteSelectedButtons(actionName: String) {
        let buttonsToDelete = deletableSelectedIDs
        guard !buttonsToDelete.isEmpty else {
            return
        }

        var beforeStates: [GamepadButton: ButtonConfig?] = [:]
        var afterStates: [GamepadButton: ButtonConfig?] = [:]

        for button in buttonsToDelete {
            beforeStates[button] = profile.buttons[button.rawValue]
            afterStates[button] = nil
            profile.buttons.removeValue(forKey: button.rawValue)
        }

        refreshEditorAfterButtonSetChange(selection: [])
        registerButtonSetUndo(before: beforeStates, after: afterStates, actionName: actionName)
    }

    private func refreshEditorAfterButtonSetChange(selection: Set<GamepadButton>) {
        clampEditableProfileToWorkspace()
        refreshFittedPadSizeFields()
        updatePreviewCanvasLayout()
        canvasObjects = makeCanvasObjects(from: profile)
        selectedIDs = selection
        previewView.reload(objects: canvasObjects, keepSelection: false)
        previewView.select(buttons: selection)

        if selection.count == 1, let button = selection.first, let config = profile.buttons[button.rawValue] {
            detailPanel.load(button: button, config: config)
        } else {
            detailPanel.clear()
        }
    }

    @objc private func saveProfile() {
        if !nameField.stringValue.isEmpty {
            profile.name = nameField.stringValue
        }

        profile.compatibilityMode = compatibilityModeCheckbox.state == .on
        clampEditableProfileToWorkspace()
        let savedProfile = makeSavedProfile(from: profile).normalizedForSaving()
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
        previewCanvasView.updateCanvasSize(visibleSize: previewScrollView.contentView.bounds.size)
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
                shape: config.shape,
                type: config.type,
                isEnabled: config.enabled,
                isSelected: false
            )
        }
    }

    private func applyCanvasGeometries(
        _ proposedGeometries: [GamepadButton: ButtonEditorGeometry]
    ) -> CanvasGeometryChangeResult {
        let snapResult = snappedGeometries(proposedGeometries)
        let geometriesToApply = snapResult.geometries
        var appliedGeometries: [GamepadButton: ButtonEditorGeometry] = [:]

        for (button, proposedGeometry) in geometriesToApply {
            guard var config = profile.buttons[button.rawValue] else {
                continue
            }

            let appliedGeometry = clampedGeometry(proposedGeometry, type: config.type)
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

        return CanvasGeometryChangeResult(geometries: appliedGeometries, guides: snapResult.guides)
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
            shape: config.shape,
            type: config.type,
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

        editorUndoManager.registerUndo(withTarget: self) { target in
            target.applyCanvasFrames(before, oppositeFrames: after)
        }
        editorUndoManager.setActionName("Move/Resize Button")
    }

    private func registerButtonStateUndo(
        button: GamepadButton,
        before: ButtonConfig?,
        after: ButtonConfig?,
        actionName: String
    ) {
        guard buttonStateChanged(before, after) else {
            return
        }

        editorUndoManager.registerUndo(withTarget: self) { target in
            target.applyButtonState(button: button, state: before, oppositeState: after, actionName: actionName)
        }
        editorUndoManager.setActionName(actionName)
    }

    private func registerButtonSetUndo(
        before: [GamepadButton: ButtonConfig?],
        after: [GamepadButton: ButtonConfig?],
        actionName: String
    ) {
        guard before.keys.contains(where: { button in buttonStateChanged(before[button] ?? nil, after[button] ?? nil) }) else {
            return
        }

        editorUndoManager.registerUndo(withTarget: self) { target in
            target.applyButtonSetState(states: before, oppositeStates: after, actionName: actionName)
        }
        editorUndoManager.setActionName(actionName)
    }

    private func applyButtonState(
        button: GamepadButton,
        state: ButtonConfig?,
        oppositeState: ButtonConfig?,
        actionName: String
    ) {
        if isProtectedSwitchButton(button), state == nil {
            return
        }

        if let state {
            profile.buttons[button.rawValue] = configByApplyingGeometryClamp(state)
        } else {
            profile.buttons.removeValue(forKey: button.rawValue)
        }

        clampEditableProfileToWorkspace()
        canvasObjects = makeCanvasObjects(from: profile)
        refreshFittedPadSizeFields()
        updatePreviewCanvasLayout()
        previewView.reload(objects: canvasObjects, keepSelection: true)

        if let config = profile.buttons[button.rawValue] {
            previewView.select(button: button)
            detailPanel.load(button: button, config: config)
        } else {
            detailPanel.clear()
        }

        editorUndoManager.registerUndo(withTarget: self) { target in
            target.applyButtonState(button: button, state: oppositeState, oppositeState: state, actionName: actionName)
        }
        editorUndoManager.setActionName(actionName)
    }

    private func applyButtonSetState(
        states: [GamepadButton: ButtonConfig?],
        oppositeStates: [GamepadButton: ButtonConfig?],
        actionName: String
    ) {
        for (button, state) in states {
            if isProtectedSwitchButton(button), state == nil {
                continue
            }

            if let state {
                profile.buttons[button.rawValue] = configByApplyingGeometryClamp(state)
            } else {
                profile.buttons.removeValue(forKey: button.rawValue)
            }
        }

        let nextSelection = Set(states.keys.filter { profile.buttons[$0.rawValue] != nil })
        refreshEditorAfterButtonSetChange(selection: nextSelection)

        editorUndoManager.registerUndo(withTarget: self) { target in
            target.applyButtonSetState(states: oppositeStates, oppositeStates: states, actionName: actionName)
        }
        editorUndoManager.setActionName(actionName)
    }

    private func buttonStateChanged(_ lhs: ButtonConfig?, _ rhs: ButtonConfig?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return false
        case (nil, _), (_, nil):
            return true
        case let (lhs?, rhs?):
            return lhs.x != rhs.x
                || lhs.y != rhs.y
                || lhs.width != rhs.width
                || lhs.height != rhs.height
                || lhs.editorWidth != rhs.editorWidth
                || lhs.editorHeight != rhs.editorHeight
                || lhs.colorHex != rhs.colorHex
                || lhs.type != rhs.type
                || lhs.keyCode != rhs.keyCode
                || lhs.keyModifiers != rhs.keyModifiers
                || lhs.keyBindings != rhs.keyBindings
                || lhs.multiKeyActivationMode != rhs.multiKeyActivationMode
                || lhs.label != rhs.label
                || lhs.labelFontSize != rhs.labelFontSize
                || lhs.labelBold != rhs.labelBold
                || lhs.labelItalic != rhs.labelItalic
                || lhs.shape != rhs.shape
                || lhs.enabled != rhs.enabled
                || lhs.interactionMode != rhs.interactionMode
                || lhs.joystick != rhs.joystick
                || lhs.action != rhs.action
        }
    }

    private var deletableSelectedIDs: Set<GamepadButton> {
        selectedIDs.filter { !isProtectedSwitchButton($0) }
    }

    private func isProtectedSwitchButton(_ button: GamepadButton) -> Bool {
        profile.buttons[button.rawValue]?.action.isProtectedSwitch == true
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

        editorUndoManager.registerUndo(withTarget: self) { target in
            target.applyCanvasFrames(oppositeFrames, oppositeFrames: frames)
        }
        editorUndoManager.setActionName("Move/Resize Button")
    }

    private func alignSelectedButtons(_ action: AlignmentAction) {
        let frames = selectedFrames()
        guard frames.count >= 2 else {
            return
        }

        let before = frames
        let targetFrame = frames.values.reduce(frames.values.first!) { $0.union($1) }
        var after: [GamepadButton: CGRect] = [:]

        for (button, frame) in frames {
            var nextFrame = frame
            switch action {
            case .left:
                nextFrame.origin.x = targetFrame.minX
            case .centerX:
                nextFrame.origin.x = targetFrame.midX - (frame.width / 2)
            case .right:
                nextFrame.origin.x = targetFrame.maxX - frame.width
            case .top:
                nextFrame.origin.y = targetFrame.maxY - frame.height
            case .centerY:
                nextFrame.origin.y = targetFrame.midY - (frame.height / 2)
            case .bottom:
                nextFrame.origin.y = targetFrame.minY
            }
            after[button] = nextFrame
        }

        applyCanvasFramesWithoutUndo(after)
        registerGeometryUndo(before: before, after: selectedFrames())
    }

    private func distributeSelectedButtons(horizontal: Bool) {
        let frames = selectedFrames()
        guard frames.count >= 3 else {
            return
        }

        let before = frames
        let sortedButtons = frames.keys.sorted { lhs, rhs in
            let lhsFrame = frames[lhs] ?? .zero
            let rhsFrame = frames[rhs] ?? .zero
            return horizontal ? lhsFrame.midX < rhsFrame.midX : lhsFrame.midY < rhsFrame.midY
        }
        guard let first = sortedButtons.first, let last = sortedButtons.last,
              let firstFrame = frames[first], let lastFrame = frames[last] else {
            return
        }

        let start = horizontal ? firstFrame.midX : firstFrame.midY
        let end = horizontal ? lastFrame.midX : lastFrame.midY
        let spacing = (end - start) / CGFloat(sortedButtons.count - 1)
        var after: [GamepadButton: CGRect] = [:]

        for (index, button) in sortedButtons.enumerated() {
            guard var frame = frames[button] else {
                continue
            }

            let center = start + (CGFloat(index) * spacing)
            if horizontal {
                frame.origin.x = center - (frame.width / 2)
            } else {
                frame.origin.y = center - (frame.height / 2)
            }
            after[button] = frame
        }

        applyCanvasFramesWithoutUndo(after)
        registerGeometryUndo(before: before, after: selectedFrames())
    }

    private func equalizeSelectedButtons(_ action: EqualizeAction) {
        let frames = selectedFrames()
        guard frames.count >= 2, let referenceButton = selectedIDs.sorted(by: { $0.rawValue < $1.rawValue }).first,
              let referenceFrame = frames[referenceButton] else {
            return
        }

        let before = frames
        var after: [GamepadButton: CGRect] = [:]

        for (button, frame) in frames {
            var nextFrame = frame
            switch action {
            case .width:
                nextFrame.size.width = referenceFrame.width
            case .height:
                nextFrame.size.height = referenceFrame.height
            case .both:
                nextFrame.size = referenceFrame.size
            }
            nextFrame.origin.x = frame.midX - (nextFrame.width / 2)
            nextFrame.origin.y = frame.midY - (nextFrame.height / 2)
            after[button] = nextFrame
        }

        applyCanvasFramesWithoutUndo(after)
        registerGeometryUndo(before: before, after: selectedFrames())
    }

    private func applyCanvasFramesWithoutUndo(_ frames: [GamepadButton: CGRect]) {
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

        if selectedIDs.count == 1, let button = selectedIDs.first, let config = profile.buttons[button.rawValue] {
            detailPanel.refreshPosition(x: config.x, y: config.y, config: config)
            detailPanel.refreshSize(
                width: config.editorWidth > 0 ? config.editorWidth : config.width,
                height: config.editorHeight > 0 ? config.editorHeight : config.height
            )
        } else {
            detailPanel.clear()
        }
    }

    private func selectedFrames() -> [GamepadButton: CGRect] {
        selectedIDs.reduce(into: [GamepadButton: CGRect]()) { result, button in
            guard let config = profile.buttons[button.rawValue] else {
                return
            }

            result[button] = editorFrame(for: config)
        }
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

            let minimumSize = ButtonSizing.minimumSize(for: config.type)
            config.editorWidth = max(config.editorWidth, minimumSize.width)
            config.editorHeight = max(config.editorHeight, minimumSize.height)
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
        guard let contentBounds = buttonContentBounds(for: editableProfile) else {
            return savedProfile
        }

        for button in savedProfile.orderedButtonIDs {
            guard var config = savedProfile.buttons[button.rawValue] else {
                continue
            }

            switch editableProfile.editorCoordinateMode {
            case .legacyTopLeft:
                config.x = (config.x - contentBounds.minX) / fittedWidth
                config.y = (config.y - contentBounds.minY) / fittedHeight
            case .centered:
                config.x = (config.x - contentBounds.minX) / fittedWidth
                config.y = (config.y - contentBounds.minY) / fittedHeight
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
        let clamped = clampedGeometry(geometry, type: config.type)
        config.x = clamped.centerX
        config.y = clamped.centerY
        config.editorWidth = clamped.width
        config.editorHeight = clamped.height
        return config
    }

    private func snappedGeometries(
        _ proposedGeometries: [GamepadButton: ButtonEditorGeometry]
    ) -> CanvasGeometryChangeResult {
        guard !proposedGeometries.isEmpty else {
            return CanvasGeometryChangeResult(geometries: proposedGeometries, guides: [])
        }

        if proposedGeometries.count > 1 {
            return snappedGroupMove(proposedGeometries)
        }

        guard let button = proposedGeometries.keys.first,
              let geometry = proposedGeometries[button] else {
            return CanvasGeometryChangeResult(geometries: proposedGeometries, guides: [])
        }

        if let anchoredResize = geometry.anchoredResize {
            return snappedAnchoredResize(button: button, geometry: geometry, anchoredResize: anchoredResize)
        }

        return snappedSingleMove(button: button, geometry: geometry)
    }

    private func snappedGroupMove(
        _ proposedGeometries: [GamepadButton: ButtonEditorGeometry]
    ) -> CanvasGeometryChangeResult {
        let proposedFrames = proposedGeometries.mapValues(frameForGeometry)
        guard let bounds = proposedFrames.values.reduce(nil, { partial, frame in
            partial?.union(frame) ?? frame
        } as (CGRect?, CGRect) -> CGRect?) else {
            return CanvasGeometryChangeResult(geometries: proposedGeometries, guides: [])
        }

        let snap = snapOffset(forMovingFrame: bounds, excluding: Set(proposedGeometries.keys))
        guard snap.offset != .zero else {
            return CanvasGeometryChangeResult(geometries: proposedGeometries, guides: snap.guides)
        }

        let snappedGeometries = proposedGeometries.mapValues { geometry in
            ButtonEditorGeometry(
                centerX: geometry.centerX + snap.offset.x,
                centerY: geometry.centerY + snap.offset.y,
                width: geometry.width,
                height: geometry.height,
                anchoredResize: geometry.anchoredResize
            )
        }
        return CanvasGeometryChangeResult(geometries: snappedGeometries, guides: snap.guides)
    }

    private func snappedSingleMove(button: GamepadButton, geometry: ButtonEditorGeometry) -> CanvasGeometryChangeResult {
        let frame = frameForGeometry(geometry)
        let snap = snapOffset(forMovingFrame: frame, excluding: [button])
        guard snap.offset != .zero else {
            return CanvasGeometryChangeResult(geometries: [button: geometry], guides: snap.guides)
        }

        let snappedGeometry = ButtonEditorGeometry(
            centerX: geometry.centerX + snap.offset.x,
            centerY: geometry.centerY + snap.offset.y,
            width: geometry.width,
            height: geometry.height,
            anchoredResize: geometry.anchoredResize
        )
        return CanvasGeometryChangeResult(geometries: [button: snappedGeometry], guides: snap.guides)
    }

    private func snappedAnchoredResize(
        button: GamepadButton,
        geometry: ButtonEditorGeometry,
        anchoredResize: AnchoredButtonResize
    ) -> CanvasGeometryChangeResult {
        let frame = frameForGeometry(geometry)
        let activeX = anchoredResize.resizesFromLeft ? frame.minX : frame.maxX
        let activeY = anchoredResize.resizesFromBottom ? frame.minY : frame.maxY
        let xSnap = nearestSnap(to: activeX, candidates: verticalSnapCandidates(excluding: [button]))
        let ySnap = nearestSnap(to: activeY, candidates: horizontalSnapCandidates(excluding: [button]))
        var snappedGeometry = geometry
        var guides: [CanvasAlignmentGuide] = []

        if let xSnap {
            let minimumSize = minimumEditorSize(for: button)
            let width = anchoredResize.resizesFromLeft
                ? anchoredResize.anchorX - xSnap
                : xSnap - anchoredResize.anchorX
            snappedGeometry.width = max(width, minimumSize.width)
            snappedGeometry.centerX = anchoredResize.resizesFromLeft
                ? anchoredResize.anchorX - (snappedGeometry.width / 2)
                : anchoredResize.anchorX + (snappedGeometry.width / 2)
            guides.append(CanvasAlignmentGuide(orientation: .vertical, position: xSnap))
        }

        if let ySnap {
            let minimumSize = minimumEditorSize(for: button)
            let height = anchoredResize.resizesFromBottom
                ? anchoredResize.anchorY - ySnap
                : ySnap - anchoredResize.anchorY
            snappedGeometry.height = max(height, minimumSize.height)
            snappedGeometry.centerY = anchoredResize.resizesFromBottom
                ? anchoredResize.anchorY - (snappedGeometry.height / 2)
                : anchoredResize.anchorY + (snappedGeometry.height / 2)
            guides.append(CanvasAlignmentGuide(orientation: .horizontal, position: ySnap))
        }

        return CanvasGeometryChangeResult(geometries: [button: snappedGeometry], guides: guides)
    }

    private func snapOffset(
        forMovingFrame frame: CGRect,
        excluding excludedButtons: Set<GamepadButton>
    ) -> (offset: CGPoint, guides: [CanvasAlignmentGuide]) {
        let xCandidates = verticalSnapCandidates(excluding: excludedButtons)
        let yCandidates = horizontalSnapCandidates(excluding: excludedButtons)
        let xValues = [frame.minX, frame.midX, frame.maxX]
        let yValues = [frame.minY, frame.midY, frame.maxY]
        let xSnap = bestSnapDelta(values: xValues, candidates: xCandidates)
        let ySnap = bestSnapDelta(values: yValues, candidates: yCandidates)
        var guides: [CanvasAlignmentGuide] = []

        if let xSnap {
            guides.append(CanvasAlignmentGuide(orientation: .vertical, position: xSnap.position))
        }
        if let ySnap {
            guides.append(CanvasAlignmentGuide(orientation: .horizontal, position: ySnap.position))
        }

        return (
            CGPoint(x: xSnap?.delta ?? 0, y: ySnap?.delta ?? 0),
            guides
        )
    }

    private func bestSnapDelta(
        values: [CGFloat],
        candidates: [CGFloat]
    ) -> (delta: CGFloat, position: CGFloat)? {
        var best: (delta: CGFloat, position: CGFloat, distance: CGFloat)?

        for value in values {
            for candidate in candidates {
                let delta = candidate - value
                let distance = abs(delta)
                guard distance <= Self.snapThreshold else {
                    continue
                }

                if best == nil || distance < best!.distance {
                    best = (delta, candidate, distance)
                }
            }
        }

        guard let best else {
            return nil
        }

        return (best.delta, best.position)
    }

    private func nearestSnap(to value: CGFloat, candidates: [CGFloat]) -> CGFloat? {
        bestSnapDelta(values: [value], candidates: candidates)?.position
    }

    private func verticalSnapCandidates(excluding excludedButtons: Set<GamepadButton>) -> [CGFloat] {
        workspaceVerticalSnapCandidates + canvasObjects.compactMap { object -> [CGFloat]? in
            guard !excludedButtons.contains(object.id), object.isEnabled else {
                return nil
            }
            return [object.frame.minX, object.frame.midX, object.frame.maxX]
        }.flatMap { $0 }
    }

    private func horizontalSnapCandidates(excluding excludedButtons: Set<GamepadButton>) -> [CGFloat] {
        workspaceHorizontalSnapCandidates + canvasObjects.compactMap { object -> [CGFloat]? in
            guard !excludedButtons.contains(object.id), object.isEnabled else {
                return nil
            }
            return [object.frame.minY, object.frame.midY, object.frame.maxY]
        }.flatMap { $0 }
    }

    private var workspaceVerticalSnapCandidates: [CGFloat] {
        switch profile.editorCoordinateMode {
        case .legacyTopLeft:
            return [0, Self.maximumWorkspaceSize.width / 2, Self.maximumWorkspaceSize.width]
        case .centered:
            return [-Self.maximumWorkspaceSize.width / 2, 0, Self.maximumWorkspaceSize.width / 2]
        }
    }

    private var workspaceHorizontalSnapCandidates: [CGFloat] {
        switch profile.editorCoordinateMode {
        case .legacyTopLeft:
            return [0, Self.maximumWorkspaceSize.height / 2, Self.maximumWorkspaceSize.height]
        case .centered:
            return [-Self.maximumWorkspaceSize.height / 2, 0, Self.maximumWorkspaceSize.height / 2]
        }
    }

    private func frameForGeometry(_ geometry: ButtonEditorGeometry) -> CGRect {
        CGRect(
            x: geometry.centerX - (geometry.width / 2),
            y: geometry.centerY - (geometry.height / 2),
            width: geometry.width,
            height: geometry.height
        )
    }

    private func minimumEditorSize(for button: GamepadButton) -> (width: Double, height: Double) {
        guard let config = profile.buttons[button.rawValue] else {
            return ButtonSizing.minimumSize(for: .keyboard)
        }

        return ButtonSizing.minimumSize(for: config.type)
    }

    private func clampedGeometry(_ geometry: ButtonEditorGeometry, type: ButtonType) -> ButtonEditorGeometry {
        if let anchoredResize = geometry.anchoredResize {
            return clampedAnchoredGeometry(geometry, type: type, anchoredResize: anchoredResize)
        }

        let maxWidth = Self.maximumWorkspaceSize.width
        let maxHeight = Self.maximumWorkspaceSize.height
        let minimumSize = ButtonSizing.minimumSize(for: type)
        let width = min(max(geometry.width, minimumSize.width), maxWidth)
        let height = min(max(geometry.height, minimumSize.height), maxHeight)
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
        type: ButtonType,
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
        let minimumSize = ButtonSizing.minimumSize(for: type)
        let width = min(max(geometry.width, minimumSize.width), max(minimumSize.width, maxWidth))
        let height = min(max(geometry.height, minimumSize.height), max(minimumSize.height, maxHeight))
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
            return contentBounds.size
        }
    }

    private func scrollPreviewToProfileContent() {
        guard let contentBounds = canvasContentBounds(for: profile) else {
            let origin = CGPoint(
                x: max(0, previewCanvasView.workspaceOrigin.x - ((previewScrollView.contentView.bounds.width - Self.maximumWorkspaceSize.width) / 2)),
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
            return contentBounds.offsetBy(
                dx: previewCanvasView.workspaceOrigin.x,
                dy: previewCanvasView.workspaceOrigin.y
            )
        }

        return contentBounds.offsetBy(
            dx: (Self.maximumWorkspaceSize.width / 2) + previewCanvasView.workspaceOrigin.x,
            dy: (Self.maximumWorkspaceSize.height / 2) + previewCanvasView.workspaceOrigin.y
        )
    }

    private func clamp(_ value: CGFloat, min minimum: CGFloat, max maximum: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, minimum), maximum)
    }
}
