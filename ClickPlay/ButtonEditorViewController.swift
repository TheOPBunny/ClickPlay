import Cocoa

// Small NSView traversal helper used when deciding whether clicks belong to editor controls or the canvas.
private extension NSView {
    func closestAncestor<T: NSView>(ofType type: T.Type) -> T? {
        var current: NSView? = self

        while let view = current {
            if let matchingView = view as? T {
                return matchingView
            }

            current = view.superview
        }

        return nil
    }
}

/// Full profile layout editor: preview canvas, inspector, selection, clipboard, grouping, snapping, and undo.
final class ButtonEditorViewController: NSViewController, NSMenuItemValidation, NSSplitViewDelegate, NSTextFieldDelegate {

    // Editor-only helper types keep command logic readable without becoming persisted profile state.
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
        static let minimumPreviewHeight: CGFloat = 420
        static let minimumInspectorWidth: CGFloat = 300
        static let defaultInspectorWidth: CGFloat = 320
    }

    private enum DefaultsKey {
        static let inspectorExpandedWidth = "Editor.inspectorExpandedWidth"
        static let inspectorCollapsed = "Editor.inspectorCollapsed"
        static let snappingEnabled = "Editor.snappingEnabled"
        static let canvasZoomScale = "Editor.canvasZoomScale"
    }

    /// Scroll document that draws the fixed editor workspace and positions the live preview inside it.
    private final class PreviewCanvasView: NSView {
        let previewView: GamepadPreviewView
        var showsGrid = true {
            didSet { needsDisplay = true }
        }
        var workspaceSize = CGSize(width: 1000, height: 1000) {
            didSet {
                guard oldValue != workspaceSize else { return }
                needsDisplay = true
            }
        }
        var zoomScale: CGFloat = 1 {
            didSet {
                zoomScale = max(zoomScale, 0.01)
                previewView.zoomScale = zoomScale
                needsDisplay = true
            }
        }
        private(set) var workspaceOrigin = CGPoint.zero

        init(previewView: GamepadPreviewView, workspaceSize: CGSize, zoomScale: CGFloat) {
            self.previewView = previewView
            self.workspaceSize = workspaceSize
            self.zoomScale = zoomScale
            super.init(frame: .zero)
            wantsLayer = true
            previewView.zoomScale = zoomScale
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

            let scaledWorkspaceSize = scaledWorkspaceSize(for: workspaceSize)
            let workspaceRect = CGRect(origin: workspaceOrigin, size: scaledWorkspaceSize)
            drawGrid(in: workspaceRect, spacing: 10 * zoomScale, color: NSColor.white.withAlphaComponent(0.05))
            drawGrid(in: workspaceRect, spacing: 50 * zoomScale, color: NSColor.white.withAlphaComponent(0.10))

            let workspaceBorder = NSBezierPath(rect: workspaceRect.insetBy(dx: 0.5, dy: 0.5))
            NSColor.white.withAlphaComponent(0.18).setStroke()
            workspaceBorder.lineWidth = 1
            workspaceBorder.stroke()
        }

        override func layout() {
            super.layout()
            previewView.frame = bounds
        }

        func updateCanvasSize(visibleSize: CGSize, workspaceSize: CGSize) {
            self.workspaceSize = workspaceSize
            previewView.zoomScale = zoomScale
            let scaledWorkspaceSize = scaledWorkspaceSize(for: workspaceSize)
            let nextSize = CGSize(
                width: max(scaledWorkspaceSize.width, visibleSize.width),
                height: max(scaledWorkspaceSize.height, visibleSize.height)
            )
            let nextWorkspaceOrigin = CGPoint(
                x: max(0, (nextSize.width - scaledWorkspaceSize.width) / 2),
                y: max(0, (nextSize.height - scaledWorkspaceSize.height) / 2)
            )

            if frame.size != nextSize {
                frame = CGRect(origin: .zero, size: nextSize)
            }
            workspaceOrigin = nextWorkspaceOrigin
            previewView.workspaceOrigin = nextWorkspaceOrigin

            needsLayout = true
            needsDisplay = true
        }

        private func scaledWorkspaceSize(for workspaceSize: CGSize) -> CGSize {
            CGSize(width: workspaceSize.width * zoomScale, height: workspaceSize.height * zoomScale)
        }

        private func drawGrid(in rect: CGRect, spacing: CGFloat, color: NSColor) {
            guard spacing > 0 else {
                return
            }

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
    var onProfileVirtualCursorModeSettingsSaved: ((UUID, Bool, Int, Int) -> Void)?
    var onToggleSidebar: (() -> Void)?
    var onSavePanelLayout: (() -> Void)?

    private static let fallbackWorkspaceSize = CGSize(width: 1000, height: 1000)
    private static let buttonCountWarningThreshold = 100
    private static let pasteOffset: Double = 18
    private static let snapThreshold: CGFloat = 5
    private static let pasteboardType = NSPasteboard.PasteboardType("com.clickplay.canvas-buttons")
    private static let canvasZoomLevels: [CGFloat] = [0.25, 0.5, 0.75, 1, 1.25, 1.5, 2, 3]

    private var maximumWorkspaceSize = ButtonEditorViewController.workspaceSize(for: NSScreen.main)
    private var profile = ProfileStore.shared.activeResolvedProfile
    private var profileVirtualCursorModeTimingProfileID = ProfileStore.shared.activeProfileID
    private var topProfileVirtualCursorModeEnabled = false
    private var topProfileVirtualCursorModeArmDelaySeconds = Profile.defaultVirtualCursorModeArmDelaySeconds
    private var topProfileVirtualCursorModeTemporaryReleaseSeconds = Profile.defaultVirtualCursorModeTemporaryReleaseSeconds
    private var canvasObjects: [CanvasButtonObject] = []
    private var selectedIDs = Set<GamepadButton>()
    private var selectedGroupID: UUID?
    private var localClipboard: [ClipboardButton] = []
    private var pasteCount = 0
    private var profileIDsWarnedForHighButtonCount = Set<UUID>()
    private let editorUndoManager = UndoManager()
    private var isInspectorCollapsed = false
    private var lastExpandedInspectorWidth = SplitMetrics.defaultInspectorWidth
    private var hasRestoredInspectorLayout = false
    private var isInspectorLayoutRestoreScheduled = false
    private var isApplyingInspectorLayout = false
    private var lastObservedEditorSplitWidth: CGFloat = 0
    private var savedProfileFingerprint: Data?
    private var shouldScrollToProfileContent = false
    private var pendingProfileContentScrollRetries = 0
    private var hasLoadedEditableProfile = false
    private var canvasZoomScale: CGFloat = 1
    private var templatesDidChangeObserver: NSObjectProtocol?
    private var screenParametersObserver: NSObjectProtocol?
    private var editorMouseDownMonitor: Any?

    private let profileSettingsButton = NSButton(title: "Profile Settings", target: nil, action: nil)
    private let profileSettingsPopover = NSPopover()
    private let profileCompatibilityModeCheckbox = NSButton(checkboxWithTitle: "Compatibility Mode", target: nil, action: nil)
    private let profileBackgroundColorWell = NSColorWell()
    private let profileBackgroundResetButton = NSButton(title: "Reset", target: nil, action: nil)
    private let profileBackgroundFrostedGlassPopup = NSPopUpButton()
    private let profileVirtualCursorModeEnabledCheckbox = NSButton(checkboxWithTitle: "Enable Virtual Cursor Mode", target: nil, action: nil)
    private let profileVirtualCursorModeArmDelayField = NSTextField()
    private let profileVirtualCursorModeTemporaryReleaseField = NSTextField()
    private var profileVirtualCursorModeTimingRows: [NSStackView] = []
    private let showGridCheckbox = NSButton(checkboxWithTitle: "Show Grid", target: nil, action: nil)
    private let snappingCheckbox = NSButton(checkboxWithTitle: "Snapping", target: nil, action: nil)
    private let groupButton = NSButton(title: "Group", target: nil, action: nil)
    private let ungroupButton = NSButton(title: "Ungroup", target: nil, action: nil)
    private let saveGroupButton = NSButton(title: "Save Group", target: nil, action: nil)
    private let zoomOutButton = NSButton(title: "-", target: nil, action: nil)
    private let zoomResetButton = NSButton(title: "100%", target: nil, action: nil)
    private let zoomInButton = NSButton(title: "+", target: nil, action: nil)
    private let addPopupButton = NSPopUpButton(frame: .zero, pullsDown: true)
    private let previewView = GamepadPreviewView()
    private lazy var previewCanvasView = PreviewCanvasView(
        previewView: previewView,
        workspaceSize: maximumWorkspaceSize,
        zoomScale: canvasZoomScale
    )
    private let previewScrollView = NSScrollView()
    private lazy var detailPanel = ButtonDetailPanel(
        frame: NSRect(
            x: 0,
            y: 0,
            width: SplitMetrics.defaultInspectorWidth,
            height: SplitMetrics.minimumPreviewHeight
        )
    )
    private let editorSplitView = NSSplitView()
    private lazy var leftColumn = NSView(
        frame: NSRect(
            x: 0,
            y: 0,
            width: SplitMetrics.minimumPreviewWidth,
            height: SplitMetrics.minimumPreviewHeight
        )
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
        updateWorkspaceSizeForCurrentDisplay(remapExistingButtons: false)
        buildLayout()
        installEditorFocusMonitor()
        installScreenParametersObserver()
        load(
            profile: ProfileStore.shared.activeResolvedProfile,
            isTopProfileSelection: true,
            topProfileID: ProfileStore.shared.activeProfileID
        )
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        updateWorkspaceSizeForCurrentDisplay(scrollToContent: true)
    }

    deinit {
        if let templatesDidChangeObserver {
            NotificationCenter.default.removeObserver(templatesDidChangeObserver)
        }
        if let screenParametersObserver {
            NotificationCenter.default.removeObserver(screenParametersObserver)
        }
        if let editorMouseDownMonitor {
            NSEvent.removeMonitor(editorMouseDownMonitor)
        }
    }

    private func installEditorFocusMonitor() {
        editorMouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.clearEditorFocusIfNeeded(for: event)
            return event
        }
    }

    private func installScreenParametersObserver() {
        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateWorkspaceSizeForCurrentDisplay(scrollToContent: true)
        }
    }

    private static func workspaceSize(for screen: NSScreen?) -> CGSize {
        let screenSize = screen?.frame.size
            ?? NSScreen.main?.frame.size
            ?? fallbackWorkspaceSize

        return CGSize(
            width: max(1, round(screenSize.width)),
            height: max(1, round(screenSize.height))
        )
    }

    private func updateWorkspaceSizeForCurrentDisplay(
        scrollToContent: Bool = false,
        remapExistingButtons: Bool = true
    ) {
        let nextWorkspaceSize = Self.workspaceSize(for: view.window?.screen)
        guard nextWorkspaceSize != maximumWorkspaceSize else {
            return
        }

        let previousWorkspaceSize = maximumWorkspaceSize
        maximumWorkspaceSize = nextWorkspaceSize
        previewCanvasView.workspaceSize = nextWorkspaceSize
        previewView.maximumWorkspaceSize = nextWorkspaceSize

        if remapExistingButtons, hasLoadedEditableProfile {
            remapEditableProfile(from: previousWorkspaceSize, to: nextWorkspaceSize)
            canvasObjects = makeCanvasObjects(from: profile)
            reloadPreview(keepSelection: true)
            refreshDetailPanelForCurrentSelection()
        }

        updatePreviewCanvasLayout()

        if scrollToContent {
            prepareProfileContentScroll()
            scrollToProfileContentIfNeeded()
        }
    }

    private func remapEditableProfile(from oldSize: CGSize, to newSize: CGSize) {
        let widthScale = max(Double(newSize.width), 1) / max(Double(oldSize.width), 1)
        let heightScale = max(Double(newSize.height), 1) / max(Double(oldSize.height), 1)

        for button in profile.orderedButtonIDs {
            guard var config = profile.buttons[button.rawValue] else {
                continue
            }

            config.x = remappedWorkspaceCoordinate(
                config.x,
                oldLength: oldSize.width,
                newLength: newSize.width
            )
            config.y = remappedWorkspaceCoordinate(
                config.y,
                oldLength: oldSize.height,
                newLength: newSize.height
            )
            config.editorWidth = max(1, config.editorWidth) * widthScale
            config.editorHeight = max(1, config.editorHeight) * heightScale
            profile.buttons[button.rawValue] = configByApplyingGeometryClamp(config)
        }

        refreshFittedPadSizeFields()
    }

    private func remappedWorkspaceCoordinate(_ value: Double, oldLength: CGFloat, newLength: CGFloat) -> Double {
        let oldLength = max(Double(oldLength), 1)
        let newLength = max(Double(newLength), 1)

        switch profile.editorCoordinateMode {
        case .legacyTopLeft:
            return (value / oldLength) * newLength
        case .centered:
            let normalized = (value + oldLength / 2) / oldLength
            return (normalized * newLength) - (newLength / 2)
        }
    }

    private func clearEditorFocusIfNeeded(for event: NSEvent) {
        guard let window = view.window, event.window === window else {
            return
        }

        let point = view.convert(event.locationInWindow, from: nil)
        guard view.bounds.contains(point), let hitView = view.hitTest(point) else {
            return
        }

        let hitColorWell = hitView.closestAncestor(ofType: NSColorWell.self)
        deactivateColorWells(except: hitColorWell)

        guard hitView.closestAncestor(ofType: NSTextView.self) == nil else {
            return
        }

        if let textField = hitView.closestAncestor(ofType: NSTextField.self),
           textField.isEditable || textField.currentEditor() != nil {
            return
        }

        window.makeFirstResponder(nil)
    }

    private func deactivateColorWells(except activeColorWell: NSColorWell?) {
        allColorWells(in: view).forEach { colorWell in
            guard colorWell !== activeColorWell else {
                return
            }

            colorWell.deactivate()
        }
    }

    private func allColorWells(in rootView: NSView) -> [NSColorWell] {
        var colorWells: [NSColorWell] = []

        func collect(from view: NSView) {
            if let colorWell = view as? NSColorWell {
                colorWells.append(colorWell)
            }

            view.subviews.forEach(collect)
        }

        collect(from: rootView)
        return colorWells
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        restoreInspectorLayoutIfNeeded()
        updatePreviewCanvasLayout()
        scrollToProfileContentIfNeeded()
    }

    func load(profile: Profile, isTopProfileSelection: Bool = false, topProfileID: UUID? = nil) {
        hasLoadedEditableProfile = false
        editorUndoManager.removeAllActions()
        selectedIDs = []
        selectedGroupID = nil
        let timingProfile = virtualCursorModeTimingProfile(
            for: profile,
            topProfileID: topProfileID,
            isTopProfileSelection: isTopProfileSelection
        )
        profileVirtualCursorModeTimingProfileID = timingProfile.id
        topProfileVirtualCursorModeEnabled = timingProfile.virtualCursorModeEnabled
        topProfileVirtualCursorModeArmDelaySeconds = timingProfile.virtualCursorModeArmDelaySeconds
        topProfileVirtualCursorModeTemporaryReleaseSeconds = timingProfile.virtualCursorModeTemporaryReleaseSeconds
        self.profile = makeEditableProfile(from: profile)
        hasLoadedEditableProfile = true
        previewView.usesCenteredOrigin = profile.editorCoordinateMode == .centered
        clampEditableProfileToWorkspace()
        self.profile.buttonGroups = sanitizedEditorGroups(self.profile.buttonGroups)
        canvasObjects = makeCanvasObjects(from: self.profile)
        syncProfileSettingsControls()
        refreshFittedPadSizeFields()
        updatePreviewCanvasLayout()
        previewView.reload(objects: canvasObjects, groups: makeCanvasGroups(from: self.profile), keepSelection: false)
        clearInspector()
        updateGroupToolbarState()
        savedProfileFingerprint = currentSavedProfileFingerprint()
        prepareProfileContentScroll()
        scrollToProfileContentIfNeeded()
    }

    private func virtualCursorModeTimingProfile(
        for profile: Profile,
        topProfileID: UUID?,
        isTopProfileSelection: Bool
    ) -> Profile {
        let store = ProfileStore.shared
        if let topProfileID,
           let selectedTopProfile = store.profiles.first(where: { $0.id == topProfileID }) {
            return selectedTopProfile
        }

        if let parentProfile = store.parentProfile(containingSubProfileID: profile.id) {
            return parentProfile
        }

        if isTopProfileSelection {
            return store.activeProfile
        }

        return store.profiles.first(where: { $0.id == profile.id }) ?? store.activeProfile
    }

    func centerCanvasOnProfileContentWhenReady() {
        prepareProfileContentScroll()
        scrollToProfileContentIfNeeded()
    }

    func refreshFromStoreIfNeeded() {
        if let parentProfile = ProfileStore.shared.parentProfile(containingSubProfileID: profile.id),
           let updatedProfile = parentProfile.subProfiles.first(where: { $0.id == profile.id }) {
            load(profile: updatedProfile, topProfileID: parentProfile.id)
        } else if let updatedProfile = ProfileStore.shared.profiles.first(where: { $0.id == profile.id }) {
            load(profile: updatedProfile, isTopProfileSelection: true, topProfileID: updatedProfile.id)
        } else {
            load(
                profile: ProfileStore.shared.activeResolvedProfile,
                isTopProfileSelection: true,
                topProfileID: ProfileStore.shared.activeProfileID
            )
        }
    }

    var hasUnsavedChanges: Bool {
        savedProfileFingerprint != currentSavedProfileFingerprint()
    }

    func confirmSaveIfNeeded() -> Bool {
        guard hasUnsavedChanges else {
            return true
        }

        let alert = NSAlert()
        alert.messageText = "Save changes before leaving?"
        alert.informativeText = "Your editor changes have not been saved yet."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return saveChanges()
        case .alertSecondButtonReturn:
            savedProfileFingerprint = currentSavedProfileFingerprint()
            return true
        default:
            return false
        }
    }

    @discardableResult
    func saveChanges() -> Bool {
        topProfileVirtualCursorModeEnabled = profileVirtualCursorModeEnabledCheckbox.state == .on
        applyProfileVirtualCursorModeTimingFields()
        profile.compatibilityMode = profileCompatibilityModeCheckbox.state == .on
        clampEditableProfileToWorkspace()
        profile.buttonGroups = sanitizedEditorGroups(profile.buttonGroups)
        let savedProfile = currentSavedProfile()
        canvasObjects = makeCanvasObjects(from: profile)
        refreshFittedPadSizeFields()
        updatePreviewCanvasLayout()
        reloadPreview(keepSelection: true)

        onProfileSaved?(savedProfile)
        onProfileVirtualCursorModeSettingsSaved?(
            profileVirtualCursorModeTimingProfileID,
            topProfileVirtualCursorModeEnabled,
            topProfileVirtualCursorModeArmDelaySeconds,
            topProfileVirtualCursorModeTemporaryReleaseSeconds
        )
        savedProfileFingerprint = currentSavedProfileFingerprint()
        showSavedIndicator()
        return true
    }

    private func buildLayout() {
        previewView.maximumWorkspaceSize = maximumWorkspaceSize
        previewView.zoomScale = canvasZoomScale
        previewCanvasView.zoomScale = canvasZoomScale
        configureProfileSettingsPopover()
        profileSettingsButton.bezelStyle = .rounded
        profileSettingsButton.target = self
        profileSettingsButton.action = #selector(toggleProfileSettingsPopover)
        showGridCheckbox.state = .on
        showGridCheckbox.target = self
        showGridCheckbox.action = #selector(showGridChanged)
        snappingCheckbox.target = self
        snappingCheckbox.action = #selector(snappingChanged)

        [groupButton, ungroupButton, saveGroupButton, zoomOutButton, zoomResetButton, zoomInButton].forEach { button in
            button.bezelStyle = .rounded
            button.target = self
        }
        groupButton.action = #selector(groupSelectedButtons)
        ungroupButton.action = #selector(ungroupSelectedGroup)
        saveGroupButton.action = #selector(saveSelectedGroupAsTemplate)
        zoomOutButton.action = #selector(zoomOut(_:))
        zoomOutButton.toolTip = "Zoom Out"
        zoomResetButton.action = #selector(actualSize(_:))
        zoomResetButton.toolTip = "Actual Size"
        zoomInButton.action = #selector(zoomIn(_:))
        zoomInButton.toolTip = "Zoom In"
        updateZoomControls()
        rebuildAddMenu()
        addPopupButton.target = self
        addPopupButton.action = #selector(addPopupChanged)

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
            profileSettingsButton,
            showGridCheckbox,
            snappingCheckbox,
            groupButton,
            ungroupButton,
            saveGroupButton,
            zoomOutButton,
            zoomResetButton,
            zoomInButton,
            NSView(),
            rightInspectorToggleButton,
            addPopupButton,
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

        previewView.onSelectionChanged = { [weak self] selectedIDs, selectedGroupID in
            guard let self else {
                return
            }

            self.selectedIDs = selectedIDs
            self.selectedGroupID = selectedGroupID
            self.updateGroupToolbarState()
            if let selectedGroupID, let group = self.buttonGroup(for: selectedGroupID) {
                self.detailPanel.loadGroup(group, colorHex: self.commonColorHex(for: group))
                return
            }

            guard selectedIDs.count == 1, let button = selectedIDs.first, let config = self.profile.buttons[button.rawValue] else {
                self.clearInspector()
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
            self.reloadPreview(keepSelection: true)
        }
        detailPanel.onDelete = { [weak self] button in
            self?.deleteButton(button)
        }
        detailPanel.onDeleteGroup = { [weak self] groupID in
            self?.deleteGroup(groupID)
        }
        detailPanel.onGroupColorChanged = { [weak self] groupID, colorHex in
            self?.applyColor(colorHex, toGroup: groupID)
        }

        templatesDidChangeObserver = NotificationCenter.default.addObserver(
            forName: ProfileTemplateStore.templatesDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.rebuildAddMenu()
        }

        editorSplitView.isVertical = true
        editorSplitView.dividerStyle = .thin
        editorSplitView.delegate = self
        editorSplitView.translatesAutoresizingMaskIntoConstraints = false

        leftColumn.translatesAutoresizingMaskIntoConstraints = false
        leftColumn.addSubview(previewScrollView)

        editorSplitView.addArrangedSubview(leftColumn)
        editorSplitView.addArrangedSubview(detailPanel)
        editorSplitView.setHoldingPriority(.defaultLow, forSubviewAt: 0)
        editorSplitView.setHoldingPriority(.defaultHigh, forSubviewAt: 1)

        [topBar, editorSplitView].forEach(view.addSubview(_:))

        let previewMinimumHeightConstraint = previewScrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: SplitMetrics.minimumPreviewHeight)
        previewMinimumHeightConstraint.priority = .defaultHigh
        let previewBottomConstraint = previewScrollView.bottomAnchor.constraint(equalTo: leftColumn.bottomAnchor)
        previewBottomConstraint.priority = .defaultHigh

        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            topBar.heightAnchor.constraint(equalToConstant: 28),
            editorSplitView.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 14),
            editorSplitView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            editorSplitView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            editorSplitView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
            previewScrollView.topAnchor.constraint(equalTo: leftColumn.topAnchor),
            previewScrollView.leadingAnchor.constraint(equalTo: leftColumn.leadingAnchor),
            previewScrollView.trailingAnchor.constraint(equalTo: leftColumn.trailingAnchor),
            previewBottomConstraint,
            previewMinimumHeightConstraint,
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
        defer { isApplyingInspectorLayout = false }
        editorSplitView.setPosition(max(SplitMetrics.minimumPreviewWidth, dividerPosition), ofDividerAt: 0)
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
        guard !hasRestoredInspectorLayout,
              !isInspectorLayoutRestoreScheduled,
              editorSplitView.bounds.width > 0 else {
            return
        }

        isInspectorLayoutRestoreScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.hasRestoredInspectorLayout else {
                return
            }

            self.isInspectorLayoutRestoreScheduled = false
            guard self.editorSplitView.bounds.width > 0 else {
                return
            }

            self.hasRestoredInspectorLayout = true
            self.detailPanel.isHidden = self.isInspectorCollapsed
            self.editorSplitView.adjustSubviews()
            self.lastObservedEditorSplitWidth = self.editorSplitView.bounds.width

            if !self.isInspectorCollapsed {
                self.setInspectorWidth(self.lastExpandedInspectorWidth)
            }
        }
    }

    private func updateLastExpandedInspectorWidth(_ width: CGFloat) {
        lastExpandedInspectorWidth = max(width, SplitMetrics.minimumInspectorWidth)
    }

    private func loadInspectorDefaults() {
        let defaults = UserDefaults.standard
        isInspectorCollapsed = defaults.bool(forKey: DefaultsKey.inspectorCollapsed)
        snappingCheckbox.state = defaults.object(forKey: DefaultsKey.snappingEnabled) as? Bool == false ? .off : .on
        canvasZoomScale = nearestSupportedZoomScale(to: defaults.double(forKey: DefaultsKey.canvasZoomScale))

        let savedWidth = defaults.double(forKey: DefaultsKey.inspectorExpandedWidth)
        if savedWidth > 0 {
            updateLastExpandedInspectorWidth(savedWidth)
        }
    }

    private func saveInspectorDefaults() {
        let defaults = UserDefaults.standard
        defaults.set(isInspectorCollapsed, forKey: DefaultsKey.inspectorCollapsed)
        defaults.set(Double(lastExpandedInspectorWidth), forKey: DefaultsKey.inspectorExpandedWidth)
        defaults.set(snappingCheckbox.state == .on, forKey: DefaultsKey.snappingEnabled)
    }

    private func makeNewButtonConfig() -> ButtonConfig {
        let width = 40.0
        let height = 40.0
        let origin = nearestEmptySpawnOrigin(for: CGSize(width: width, height: height))

        return ButtonConfig(
            x: Double(origin.x) + (width / 2),
            y: Double(origin.y) + (height / 2),
            width: width,
            height: height,
            editorWidth: width,
            editorHeight: height,
            colorHex: "#3D3D3D",
            keyCode: 49,
            keyModifiers: 0,
            label: nextCustomButtonLabel(),
            shape: .square,
            enabled: true
        )
    }

    private func makeNewJoystickConfig() -> ButtonConfig {
        let width = 50.0
        let height = 50.0
        let origin = nearestEmptySpawnOrigin(for: CGSize(width: width, height: height))
        var joystick = JoystickConfig.defaultBindings
        joystick.operationMode = .clickDrag
        joystick.axisLockMode = .holdDirection
        joystick.axisLockHoldDuration = JoystickConfig.defaultAxisLockHoldDuration
        joystick.axisUnlockHoldDuration = JoystickConfig.defaultAxisUnlockHoldDuration

        return ButtonConfig(
            type: .joystick,
            x: Double(origin.x) + (width / 2),
            y: Double(origin.y) + (height / 2),
            width: width,
            height: height,
            editorWidth: width,
            editorHeight: height,
            colorHex: "#000000",
            keyCode: 13,
            keyModifiers: 0,
            label: "Joystick",
            shape: .oval,
            enabled: true,
            interactionMode: .momentary,
            rightClickKeyBindings: nil,
            rightClickFallsBackToPrimary: false,
            rightClickInteractionMode: nil,
            joystick: joystick
        )
    }

    private func makeNewSystemEventConfig() -> ButtonConfig {
        let width = 40.0
        let height = 40.0
        let origin = nearestEmptySpawnOrigin(for: CGSize(width: width, height: height))

        return ButtonConfig(
            type: .systemEvent,
            x: Double(origin.x) + (width / 2),
            y: Double(origin.y) + (height / 2),
            width: width,
            height: height,
            editorWidth: width,
            editorHeight: height,
            colorHex: "#000000",
            keyCode: 49,
            keyModifiers: 0,
            label: "",
            shape: .square,
            enabled: true,
            interactionMode: .momentary,
            rightClickKeyBindings: nil,
            rightClickFallsBackToPrimary: false,
            rightClickInteractionMode: nil,
            action: .systemEvent(.brightnessDown)
        )
    }

    private func makeNewDwellActionConfig() -> ButtonConfig {
        let width = 20.0
        let height = 20.0
        let origin = nearestEmptySpawnOrigin(for: CGSize(width: width, height: height))

        return ButtonConfig(
            type: .dwellAction,
            x: Double(origin.x) + (width / 2),
            y: Double(origin.y) + (height / 2),
            width: width,
            height: height,
            editorWidth: width,
            editorHeight: height,
            colorHex: "#000000",
            keyCode: 49,
            keyModifiers: 0,
            label: "",
            shape: .square,
            enabled: true,
            interactionMode: .momentary,
            rightClickKeyBindings: nil,
            rightClickFallsBackToPrimary: false,
            rightClickInteractionMode: nil,
            dwellAction: .default
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

    @objc func zoomIn(_ sender: Any?) {
        guard let nextScale = nextZoomScale(after: canvasZoomScale) else {
            return
        }

        setCanvasZoomScale(nextScale, persist: true)
    }

    @objc func zoomOut(_ sender: Any?) {
        guard let nextScale = nextZoomScale(before: canvasZoomScale) else {
            return
        }

        setCanvasZoomScale(nextScale, persist: true)
    }

    @objc func actualSize(_ sender: Any?) {
        setCanvasZoomScale(1, persist: true)
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

            return (selectedGroupID != nil || !deletableSelectedIDs.isEmpty) && !isTextInputFirstResponder
        case #selector(paste(_:)):
            return canPasteButtons && !isTextInputFirstResponder
        case #selector(alignLeft(_:)), #selector(alignCenterX(_:)), #selector(alignRight(_:)),
             #selector(alignTop(_:)), #selector(alignCenterY(_:)), #selector(alignBottom(_:)),
             #selector(equalizeWidths(_:)), #selector(equalizeHeights(_:)), #selector(equalizeBoth(_:)):
            return selectedIDs.count >= 2 && !isTextInputFirstResponder
        case #selector(distributeHorizontally(_:)), #selector(distributeVertically(_:)):
            return selectedIDs.count >= 3 && !isTextInputFirstResponder
        case #selector(zoomIn(_:)):
            return nextZoomScale(after: canvasZoomScale) != nil
        case #selector(zoomOut(_:)):
            return nextZoomScale(before: canvasZoomScale) != nil
        case #selector(actualSize(_:)):
            return canvasZoomScale != 1
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
            if config.action.isProtectedSwitch {
                config.action = .keyboard
            }
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

        if let selectedGroupID {
            deleteGroup(selectedGroupID)
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

    private func configureProfileSettingsPopover() {
        profileCompatibilityModeCheckbox.target = self
        profileCompatibilityModeCheckbox.action = #selector(profileCompatibilityModeChanged)

        profileVirtualCursorModeEnabledCheckbox.target = self
        profileVirtualCursorModeEnabledCheckbox.action = #selector(profileVirtualCursorModeEnabledChanged)

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

        [profileVirtualCursorModeArmDelayField, profileVirtualCursorModeTemporaryReleaseField].forEach { field in
            field.bezelStyle = .roundedBezel
            field.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            field.widthAnchor.constraint(equalToConstant: 58).isActive = true
            field.target = self
            field.action = #selector(profileVirtualCursorModeTimingChanged(_:))
            field.delegate = self
        }

        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 224))
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: "Profile Settings")
        titleLabel.font = .boldSystemFont(ofSize: 14)

        let colorControls = NSStackView(views: [profileBackgroundColorWell, profileBackgroundResetButton])
        colorControls.orientation = .horizontal
        colorControls.alignment = .centerY
        colorControls.spacing = 8

        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(profileCompatibilityModeCheckbox)
        stack.addArrangedSubview(makeProfileSettingsRow(label: "Gamepad Color", control: colorControls))
        stack.addArrangedSubview(makeProfileSettingsRow(label: "Frosted Glass", control: profileBackgroundFrostedGlassPopup))
        stack.addArrangedSubview(profileVirtualCursorModeEnabledCheckbox)

        let armDelayRow = makeProfileSettingsRow(label: "Activation Delay", control: makeProfileSettingsUnitField(field: profileVirtualCursorModeArmDelayField, unit: "seconds"))
        let temporaryReleaseRow = makeProfileSettingsRow(label: "Temporary Release", control: makeProfileSettingsUnitField(field: profileVirtualCursorModeTemporaryReleaseField, unit: "seconds"))
        profileVirtualCursorModeTimingRows = [armDelayRow, temporaryReleaseRow]
        stack.addArrangedSubview(armDelayRow)
        stack.addArrangedSubview(temporaryReleaseRow)

        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        let contentController = NSViewController()
        contentController.view = contentView
        profileSettingsPopover.contentViewController = contentController
        profileSettingsPopover.behavior = .transient
        profileSettingsPopover.animates = true
    }

    private func makeProfileSettingsRow(label: String, control: NSView) -> NSStackView {
        let labelView = NSTextField(labelWithString: label)
        labelView.font = .systemFont(ofSize: 12)
        labelView.widthAnchor.constraint(equalToConstant: 132).isActive = true

        let row = NSStackView(views: [labelView, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
    }

    private func makeProfileSettingsUnitField(field: NSTextField, unit: String) -> NSStackView {
        let unitLabel = NSTextField(labelWithString: unit)
        unitLabel.font = .systemFont(ofSize: 12)
        unitLabel.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [field, unitLabel])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        return stack
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

    private func syncProfileSettingsControls() {
        profileCompatibilityModeCheckbox.state = profile.compatibilityMode ? .on : .off
        profileBackgroundColorWell.color = NSColor(hex: profile.backgroundColorHex)
        profileBackgroundFrostedGlassPopup.selectItem(withTag: profile.backgroundFrostedGlassIntensity)
        if profileBackgroundFrostedGlassPopup.selectedItem == nil {
            profileBackgroundFrostedGlassPopup.selectItem(withTag: Profile.defaultBackgroundFrostedGlassIntensity)
        }
        profileVirtualCursorModeEnabledCheckbox.state = topProfileVirtualCursorModeEnabled ? .on : .off
        profileVirtualCursorModeArmDelayField.stringValue = "\(max(1, topProfileVirtualCursorModeArmDelaySeconds))"
        profileVirtualCursorModeTemporaryReleaseField.stringValue = "\(max(1, topProfileVirtualCursorModeTemporaryReleaseSeconds))"
        updateProfileVirtualCursorModeTimingAvailability()
    }

    @objc private func toggleProfileSettingsPopover() {
        if profileSettingsPopover.isShown {
            profileSettingsPopover.performClose(nil)
            return
        }

        syncProfileSettingsControls()
        profileSettingsPopover.show(
            relativeTo: profileSettingsButton.bounds,
            of: profileSettingsButton,
            preferredEdge: .maxY
        )
    }

    @objc private func profileCompatibilityModeChanged() {
        profile.compatibilityMode = profileCompatibilityModeCheckbox.state == .on
        reloadPreview(keepSelection: true)
    }

    @objc private func profileBackgroundColorChanged() {
        profile.backgroundColorHex = profileBackgroundColorWell.color.hexString
    }

    @objc private func resetProfileBackgroundColor() {
        profileBackgroundColorWell.color = NSColor(hex: Profile.defaultBackgroundColorHex)
        profile.backgroundColorHex = Profile.defaultBackgroundColorHex
    }

    @objc private func profileBackgroundFrostedGlassChanged() {
        profile.backgroundFrostedGlassIntensity = profileBackgroundFrostedGlassPopup.selectedTag()
    }

    @objc private func profileVirtualCursorModeEnabledChanged() {
        topProfileVirtualCursorModeEnabled = profileVirtualCursorModeEnabledCheckbox.state == .on
        updateProfileVirtualCursorModeTimingAvailability()
    }

    private func updateProfileVirtualCursorModeTimingAvailability() {
        let isEnabled = profileVirtualCursorModeEnabledCheckbox.state == .on
        profileVirtualCursorModeArmDelayField.isEnabled = isEnabled
        profileVirtualCursorModeTemporaryReleaseField.isEnabled = isEnabled
        profileVirtualCursorModeTimingRows.forEach { $0.alphaValue = isEnabled ? 1 : 0.45 }
    }

    @objc private func profileVirtualCursorModeTimingChanged(_ sender: NSTextField) {
        applyProfileVirtualCursorModeTimingField(sender)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField,
              field === profileVirtualCursorModeArmDelayField || field === profileVirtualCursorModeTemporaryReleaseField else {
            return
        }

        applyProfileVirtualCursorModeTimingField(field)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard commandSelector == #selector(NSResponder.insertNewline(_:)),
              let textField = control as? NSTextField,
              textField === profileVirtualCursorModeArmDelayField || textField === profileVirtualCursorModeTemporaryReleaseField else {
            return false
        }

        textField.stringValue = textView.string
        applyProfileVirtualCursorModeTimingField(textField)
        textField.window?.endEditing(for: textField)
        textField.window?.makeFirstResponder(nil)
        return true
    }

    private func applyProfileVirtualCursorModeTimingFields() {
        applyProfileVirtualCursorModeTimingField(profileVirtualCursorModeArmDelayField)
        applyProfileVirtualCursorModeTimingField(profileVirtualCursorModeTemporaryReleaseField)
    }

    private func applyProfileVirtualCursorModeTimingField(_ field: NSTextField) {
        let value = clampedWholeSeconds(from: field.stringValue)
        field.stringValue = "\(value)"

        if field === profileVirtualCursorModeArmDelayField {
            topProfileVirtualCursorModeArmDelaySeconds = value
        } else if field === profileVirtualCursorModeTemporaryReleaseField {
            topProfileVirtualCursorModeTemporaryReleaseSeconds = value
        }
    }

    private func clampedWholeSeconds(from stringValue: String) -> Int {
        guard let parsedValue = Double(stringValue), parsedValue.isFinite else {
            return 1
        }

        return max(1, Int(parsedValue.rounded()))
    }

    @objc private func showGridChanged() {
        previewCanvasView.showsGrid = showGridCheckbox.state == .on
    }

    @objc private func snappingChanged() {
        UserDefaults.standard.set(snappingCheckbox.state == .on, forKey: DefaultsKey.snappingEnabled)
    }

    private func setCanvasZoomScale(_ scale: CGFloat, persist: Bool) {
        let nextScale = nearestSupportedZoomScale(to: scale)
        guard nextScale != canvasZoomScale else {
            updateZoomControls()
            return
        }

        let anchorPoint = visibleCanvasAnchorPoint()
        canvasZoomScale = nextScale
        previewCanvasView.zoomScale = nextScale
        previewView.zoomScale = nextScale
        updatePreviewCanvasLayout()
        updateZoomControls()

        if persist {
            UserDefaults.standard.set(Double(nextScale), forKey: DefaultsKey.canvasZoomScale)
        }

        if let anchorPoint {
            scrollPreviewToCanvasRect(CGRect(origin: canvasPoint(forModelPoint: anchorPoint), size: .zero))
        }
    }

    private func updateZoomControls() {
        zoomOutButton.isEnabled = nextZoomScale(before: canvasZoomScale) != nil
        zoomInButton.isEnabled = nextZoomScale(after: canvasZoomScale) != nil
        zoomResetButton.title = "\(Int(round(canvasZoomScale * 100)))%"
    }

    private func nextZoomScale(after scale: CGFloat) -> CGFloat? {
        Self.canvasZoomLevels.first { $0 > scale + 0.001 }
    }

    private func nextZoomScale(before scale: CGFloat) -> CGFloat? {
        Self.canvasZoomLevels.reversed().first { $0 < scale - 0.001 }
    }

    private func nearestSupportedZoomScale(to scale: CGFloat) -> CGFloat {
        guard scale > 0 else {
            return 1
        }

        return Self.canvasZoomLevels.min { lhs, rhs in
            abs(lhs - scale) < abs(rhs - scale)
        } ?? 1
    }

    private func nearestSupportedZoomScale(to scale: Double) -> CGFloat {
        nearestSupportedZoomScale(to: CGFloat(scale))
    }

    private func rebuildAddMenu() {
        addPopupButton.removeAllItems()
        addPopupButton.addItem(withTitle: "Add...")
        addPopupButton.addItem(withTitle: "Button")
        addPopupButton.lastItem?.tag = 1
        addPopupButton.addItem(withTitle: "Joystick")
        addPopupButton.lastItem?.tag = 2
        addPopupButton.addItem(withTitle: "System Event")
        addPopupButton.lastItem?.tag = 3
        addPopupButton.addItem(withTitle: "Dwell Action")
        addPopupButton.lastItem?.tag = 4

        let groupItem = NSMenuItem(title: "Group", action: nil, keyEquivalent: "")
        let groupMenu = NSMenu(title: "Group")
        let templates = ProfileTemplateStore.shared.templates(kind: .group)
        if templates.isEmpty {
            let emptyItem = NSMenuItem(title: "No Saved Groups", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            groupMenu.addItem(emptyItem)
        } else {
            for template in templates {
                let item = NSMenuItem(title: template.name, action: #selector(addGroupFromTemplate(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = template.id.uuidString
                groupMenu.addItem(item)
            }
        }
        groupItem.submenu = groupMenu
        addPopupButton.menu?.addItem(NSMenuItem.separator())
        addPopupButton.menu?.addItem(groupItem)
    }

    @objc private func addPopupChanged() {
        defer { addPopupButton.selectItem(at: 0) }

        switch addPopupButton.selectedTag() {
        case 1:
            addButtonPressed()
        case 2:
            addJoystickPressed()
        case 3:
            addSystemEventPressed()
        case 4:
            addDwellActionPressed()
        default:
            break
        }
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
        reloadPreview(keepSelection: false)
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
        reloadPreview(keepSelection: false)
        previewView.select(button: button)
    }

    @objc private func addSystemEventPressed() {
        guard confirmAddingButtonIfNeeded() else {
            return
        }

        let button = GamepadButton.generated()
        let config = makeNewSystemEventConfig()
        profile.buttons[button.rawValue] = config
        registerButtonStateUndo(button: button, before: nil, after: config, actionName: "Add System Event")
        syncWorkspaceAfterGeometryChange(selectedButton: button)
        reloadPreview(keepSelection: false)
        previewView.select(button: button)
    }

    @objc private func addDwellActionPressed() {
        guard confirmAddingButtonIfNeeded() else {
            return
        }

        let button = GamepadButton.generated()
        let config = makeNewDwellActionConfig()
        profile.buttons[button.rawValue] = config
        registerButtonStateUndo(button: button, before: nil, after: config, actionName: "Add Dwell Action")
        syncWorkspaceAfterGeometryChange(selectedButton: button)
        reloadPreview(keepSelection: false)
        previewView.select(button: button)
    }

    @objc private func groupSelectedButtons() {
        let selectedButtonIDs = profile.orderedButtonIDs
            .filter { selectedIDs.contains($0) }
            .map(\.rawValue)
        guard selectedButtonIDs.count >= 2, selectedButtonIDs.allSatisfy({ groupID(containingButtonID: $0) == nil }) else {
            return
        }

        let beforeGroups = profile.buttonGroups
        let group = ButtonGroup(
            name: nextGroupName(),
            memberButtonIDs: selectedButtonIDs
        )
        profile.buttonGroups.append(group)
        profile.buttonGroups = sanitizedEditorGroups(profile.buttonGroups)
        selectedIDs = []
        selectedGroupID = group.id
        reloadPreview(keepSelection: false)
        previewView.select(group: group.id)
        detailPanel.loadGroup(group, colorHex: commonColorHex(for: group))
        updateGroupToolbarState()
        registerGroupStateUndo(before: beforeGroups, after: profile.buttonGroups, actionName: "Group Buttons")
    }

    @objc private func ungroupSelectedGroup() {
        guard let selectedGroupID else {
            return
        }

        let beforeGroups = profile.buttonGroups
        profile.buttonGroups.removeAll { $0.id == selectedGroupID }
        self.selectedGroupID = nil
        reloadPreview(keepSelection: false)
        previewView.select(buttons: [])
        clearInspector()
        updateGroupToolbarState()
        registerGroupStateUndo(before: beforeGroups, after: profile.buttonGroups, actionName: "Ungroup Buttons")
    }

    @objc private func saveSelectedGroupAsTemplate() {
        guard let selectedGroupID, let group = buttonGroup(for: selectedGroupID) else {
            return
        }

        let alert = NSAlert()
        alert.messageText = "Save Group Template"
        alert.informativeText = "Choose a name for this group."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        textField.stringValue = group.name
        textField.selectText(nil)
        alert.accessoryView = textField

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        var templateProfile = profile
        let memberIDs = Set(group.memberButtonIDs)
        templateProfile.buttons = profile.buttons.filter { memberIDs.contains($0.key) }
        templateProfile.buttonGroups = [group]
        templateProfile.subProfiles = []
        templateProfile.activeSubProfileID = nil

        ProfileTemplateStore.shared.saveTemplate(
            named: textField.stringValue,
            kind: .group,
            profile: makeSavedProfile(from: templateProfile)
        )
    }

    @objc private func addGroupFromTemplate(_ sender: NSMenuItem) {
        defer { addPopupButton.selectItem(at: 0) }

        guard let idString = sender.representedObject as? String,
              let templateID = UUID(uuidString: idString),
              var groupProfile = ProfileTemplateStore.shared.makeGroup(fromTemplateID: templateID) else {
            return
        }

        groupProfile = makeEditableProfile(from: groupProfile)
        guard confirmAddingButtonIfNeeded(),
              let sourceGroup = groupProfile.buttonGroups.first else {
            return
        }

        let sourceBounds = buttonContentBounds(for: groupProfile) ?? .zero
        let targetOrigin = nearestEmptySpawnOrigin(for: sourceBounds.size)
        let offset = CGPoint(
            x: targetOrigin.x - sourceBounds.minX,
            y: targetOrigin.y - sourceBounds.minY
        )
        var insertedButtons: [GamepadButton: ButtonConfig] = [:]

        for button in groupProfile.orderedButtonIDs {
            guard var config = groupProfile.buttons[button.rawValue] else {
                continue
            }

            config.x += offset.x
            config.y += offset.y
            config.enabled = true
            config = configByApplyingGeometryClamp(config)
            profile.buttons[button.rawValue] = config
            insertedButtons[button] = config
        }

        let beforeGroups = profile.buttonGroups
        let newGroup = ButtonGroup(
            name: sourceGroup.name,
            memberButtonIDs: sourceGroup.memberButtonIDs.filter { profile.buttons[$0] != nil }
        )
        profile.buttonGroups.append(newGroup)
        profile.buttonGroups = sanitizedEditorGroups(profile.buttonGroups)
        selectedIDs = []
        selectedGroupID = newGroup.id

        refreshEditorAfterButtonSetChange(selection: [])
        previewView.select(group: newGroup.id)
        focusPreviewForEditorCommands()
        if let group = buttonGroup(for: newGroup.id) {
            detailPanel.loadGroup(group, colorHex: commonColorHex(for: group))
        }
        updateGroupToolbarState()
        registerAddedGroupUndo(
            insertedButtons: insertedButtons,
            beforeGroups: beforeGroups,
            afterGroups: profile.buttonGroups
        )
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
        let beforeGroups = profile.buttonGroups
        profile.buttons.removeValue(forKey: button.rawValue)
        profile.buttonGroups = sanitizedEditorGroups(profile.buttonGroups)
        registerEditorStateUndo(
            beforeButtons: [button: previousConfig],
            afterButtons: [button: nil],
            beforeGroups: beforeGroups,
            afterGroups: profile.buttonGroups,
            actionName: "Delete Button"
        )
        refreshFittedPadSizeFields()
        updatePreviewCanvasLayout()
        canvasObjects = makeCanvasObjects(from: profile)
        reloadPreview(keepSelection: false)
        clearInspector()
    }

    private func deleteGroup(_ groupID: UUID) {
        guard let group = buttonGroup(for: groupID) else {
            return
        }

        var deletedButtonStates: [GamepadButton: ButtonConfig] = [:]
        let beforeGroups = profile.buttonGroups

        for buttonID in group.memberButtonIDs {
            let button = GamepadButton(buttonID)
            guard !isProtectedSwitchButton(button) else {
                continue
            }

            if let config = profile.buttons[buttonID] {
                deletedButtonStates[button] = config
            }
            profile.buttons.removeValue(forKey: buttonID)
        }

        profile.buttonGroups.removeAll { $0.id == groupID }
        profile.buttonGroups = sanitizedEditorGroups(profile.buttonGroups)
        selectedGroupID = nil
        refreshEditorAfterButtonSetChange(selection: [])
        registerGroupDeleteUndo(
            deletedButtons: deletedButtonStates,
            beforeGroups: beforeGroups,
            afterGroups: profile.buttonGroups
        )
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
        let beforeGroups = profile.buttonGroups

        for button in buttonsToDelete {
            beforeStates[button] = profile.buttons[button.rawValue]
            afterStates[button] = Optional<ButtonConfig?>.some(nil)
            profile.buttons.removeValue(forKey: button.rawValue)
        }

        profile.buttonGroups = sanitizedEditorGroups(profile.buttonGroups)
        refreshEditorAfterButtonSetChange(selection: [])
        registerEditorStateUndo(
            beforeButtons: beforeStates,
            afterButtons: afterStates,
            beforeGroups: beforeGroups,
            afterGroups: profile.buttonGroups,
            actionName: actionName
        )
    }

    private func refreshEditorAfterButtonSetChange(selection: Set<GamepadButton>) {
        clampEditableProfileToWorkspace()
        refreshFittedPadSizeFields()
        updatePreviewCanvasLayout()
        canvasObjects = makeCanvasObjects(from: profile)
        selectedIDs = selection
        selectedGroupID = nil
        reloadPreview(keepSelection: false)
        previewView.select(buttons: selection)
        updateGroupToolbarState()

        if selection.count == 1, let button = selection.first, let config = profile.buttons[button.rawValue] {
            detailPanel.load(button: button, config: config)
        } else {
            clearInspector()
        }
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
        previewCanvasView.zoomScale = canvasZoomScale
        previewCanvasView.updateCanvasSize(
            visibleSize: previewScrollView.contentView.bounds.size,
            workspaceSize: maximumWorkspaceSize
        )
        previewCanvasView.needsLayout = true
    }

    private func reloadPreview(keepSelection: Bool) {
        previewView.reload(
            objects: canvasObjects,
            groups: makeCanvasGroups(from: profile),
            keepSelection: keepSelection
        )
    }

    private func refreshDetailPanelForCurrentSelection() {
        if let selectedGroupID, let group = buttonGroup(for: selectedGroupID) {
            detailPanel.loadGroup(group, colorHex: commonColorHex(for: group))
            return
        }

        if selectedIDs.count == 1,
           let button = selectedIDs.first,
           let config = profile.buttons[button.rawValue] {
            detailPanel.load(button: button, config: config)
            return
        }

        clearInspector()
    }

    private func clearInspector() {
        detailPanel.clear()
    }

    private func focusPreviewForEditorCommands() {
        view.window?.makeFirstResponder(previewView)
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }

            self.view.window?.makeFirstResponder(self.previewView)
        }
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

    private func applyColor(_ colorHex: String, toGroup groupID: UUID) {
        guard let group = buttonGroup(for: groupID) else {
            return
        }

        var beforeStates: [GamepadButton: ButtonConfig?] = [:]
        var afterStates: [GamepadButton: ButtonConfig?] = [:]

        for buttonID in group.memberButtonIDs {
            let button = GamepadButton(buttonID)
            guard var config = profile.buttons[buttonID] else {
                continue
            }

            beforeStates[button] = config
            config.colorHex = colorHex
            profile.buttons[buttonID] = config
            afterStates[button] = config
            syncCanvasObject(for: button, config: config)
        }

        canvasObjects = makeCanvasObjects(from: profile)
        reloadPreview(keepSelection: true)
        if let group = buttonGroup(for: groupID) {
            detailPanel.loadGroup(group, colorHex: commonColorHex(for: group))
        }
        registerButtonSetUndo(before: beforeStates, after: afterStates, actionName: "Edit Group Color")
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
                labelColorHex: config.labelColorHex,
                shape: config.shape,
                type: config.type,
                systemEvent: config.action.systemEvent,
                systemEventIconSize: config.systemEventIconSize,
                isEnabled: config.enabled,
                isSelected: false
            )
        }
    }

    private func makeCanvasGroups(from profile: Profile) -> [CanvasButtonGroupObject] {
        var enabledButtonIDs = Set<GamepadButton>()
        for (key, config) in profile.buttons where config.enabled {
            enabledButtonIDs.insert(GamepadButton(key))
        }

        var canvasGroups: [CanvasButtonGroupObject] = []
        for group in profile.buttonGroups {
            let memberIDs = group.memberButtonIDs
                .map { GamepadButton($0) }
                .filter { enabledButtonIDs.contains($0) }
            guard memberIDs.count >= 2 else {
                continue
            }

            canvasGroups.append(CanvasButtonGroupObject(id: group.id, name: group.name, memberIDs: memberIDs))
        }

        return canvasGroups
    }

    private func buttonGroup(for id: UUID) -> ButtonGroup? {
        profile.buttonGroups.first { $0.id == id }
    }

    private func groupID(containingButtonID buttonID: String) -> UUID? {
        profile.buttonGroups.first { $0.memberButtonIDs.contains(buttonID) }?.id
    }

    private func nextGroupName() -> String {
        let prefix = "Group "
        let nextNumber = profile.buttonGroups.reduce(0) { currentMax, group in
            guard group.name.hasPrefix(prefix) else {
                return currentMax
            }

            return max(currentMax, Int(group.name.dropFirst(prefix.count)) ?? 0)
        } + 1

        return "\(prefix)\(nextNumber)"
    }

    private func commonColorHex(for group: ButtonGroup) -> String? {
        let colors = Set(group.memberButtonIDs.compactMap { profile.buttons[$0]?.colorHex })
        return colors.count == 1 ? colors.first : nil
    }

    private func updateGroupToolbarState() {
        let selectedButtonIDs = selectedIDs.map(\.rawValue)
        groupButton.isEnabled = selectedButtonIDs.count >= 2
            && selectedButtonIDs.allSatisfy { groupID(containingButtonID: $0) == nil }
        ungroupButton.isEnabled = selectedGroupID != nil
        saveGroupButton.isEnabled = selectedGroupID != nil
    }

    private func sanitizedEditorGroups(_ groups: [ButtonGroup]) -> [ButtonGroup] {
        let validIDs = Set(profile.buttons.keys)
        var claimedButtonIDs = Set<String>()

        return groups.compactMap { group in
            var seen = Set<String>()
            let members = group.memberButtonIDs.filter { buttonID in
                guard validIDs.contains(buttonID),
                      !seen.contains(buttonID),
                      !claimedButtonIDs.contains(buttonID) else {
                    return false
                }

                seen.insert(buttonID)
                claimedButtonIDs.insert(buttonID)
                return true
            }

            guard members.count >= 2 else {
                return nil
            }

            let trimmedName = group.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return ButtonGroup(
                id: group.id,
                name: trimmedName.isEmpty ? "Group" : trimmedName,
                memberButtonIDs: members
            )
        }
    }

    private func nearestEmptySpawnOrigin(for size: CGSize) -> CGPoint {
        let workspaceBounds = editorWorkspaceBounds()
        let width = min(max(size.width, 1), workspaceBounds.width)
        let height = min(max(size.height, 1), workspaceBounds.height)
        let occupiedFrames = enabledEditorFrames()
        let searchBounds = CGRect(
            x: workspaceBounds.minX,
            y: workspaceBounds.minY,
            width: max(0, workspaceBounds.width - width),
            height: max(0, workspaceBounds.height - height)
        )
        var candidateXs = Set<CGFloat>([searchBounds.minX, 0])
        var candidateYs = Set<CGFloat>([searchBounds.minY, 0])

        for frame in occupiedFrames {
            candidateXs.insert(frame.maxX)
            candidateXs.insert(frame.minX - width)
            candidateYs.insert(frame.maxY)
            candidateYs.insert(frame.minY - height)
        }

        let clampedXs = candidateXs.map { clamp($0, min: searchBounds.minX, max: searchBounds.maxX) }
        let clampedYs = candidateYs.map { clamp($0, min: searchBounds.minY, max: searchBounds.maxY) }
        let sortedXs = Array(Set(clampedXs)).sorted()
        let sortedYs = Array(Set(clampedYs)).sorted()
        var bestOrigin: CGPoint?
        var bestRank: (distance: CGFloat, y: CGFloat, x: CGFloat)?

        for y in sortedYs {
            for x in sortedXs {
                let candidate = CGRect(x: x, y: y, width: width, height: height)
                guard !occupiedFrames.contains(where: { $0.intersects(candidate) }) else {
                    continue
                }

                let distance = (x * x) + (y * y)
                let rank = (distance: distance, y: y, x: x)
                if let currentBest = bestRank {
                    guard rank.distance < currentBest.distance
                        || (rank.distance == currentBest.distance && rank.y < currentBest.y)
                        || (rank.distance == currentBest.distance && rank.y == currentBest.y && rank.x < currentBest.x) else {
                        continue
                    }
                }

                bestRank = rank
                bestOrigin = candidate.origin
            }
        }

        return bestOrigin ?? CGPoint(x: searchBounds.minX, y: searchBounds.minY)
    }

    private func editorWorkspaceBounds() -> CGRect {
        switch profile.editorCoordinateMode {
        case .legacyTopLeft:
            return CGRect(origin: .zero, size: maximumWorkspaceSize)
        case .centered:
            return CGRect(
                x: -maximumWorkspaceSize.width / 2,
                y: -maximumWorkspaceSize.height / 2,
                width: maximumWorkspaceSize.width,
                height: maximumWorkspaceSize.height
            )
        }
    }

    private func enabledEditorFrames() -> [CGRect] {
        profile.orderedButtonIDs.compactMap { button in
            guard let config = profile.buttons[button.rawValue], config.enabled else {
                return nil
            }

            return editorFrame(for: config)
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

            let appliedGeometry = pixelAlignedGeometry(proposedGeometry, type: config.type)
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
            labelColorHex: config.labelColorHex,
            shape: config.shape,
            type: config.type,
            systemEvent: config.action.systemEvent,
            systemEventIconSize: config.systemEventIconSize,
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

    private func registerGroupStateUndo(before: [ButtonGroup], after: [ButtonGroup], actionName: String) {
        guard before != after else {
            return
        }

        editorUndoManager.registerUndo(withTarget: self) { target in
            target.applyGroupState(before, oppositeGroups: after, actionName: actionName)
        }
        editorUndoManager.setActionName(actionName)
    }

    private func registerEditorStateUndo(
        beforeButtons: [GamepadButton: ButtonConfig?],
        afterButtons: [GamepadButton: ButtonConfig?],
        beforeGroups: [ButtonGroup],
        afterGroups: [ButtonGroup],
        actionName: String
    ) {
        let buttonChanged = beforeButtons.keys.contains { button in
            buttonStateChanged(beforeButtons[button] ?? nil, afterButtons[button] ?? nil)
        }
        guard buttonChanged || beforeGroups != afterGroups else {
            return
        }

        editorUndoManager.registerUndo(withTarget: self) { target in
            target.applyEditorState(
                buttonStates: beforeButtons,
                oppositeButtonStates: afterButtons,
                groups: beforeGroups,
                oppositeGroups: afterGroups,
                actionName: actionName
            )
        }
        editorUndoManager.setActionName(actionName)
    }

    private func registerGroupDeleteUndo(
        deletedButtons: [GamepadButton: ButtonConfig],
        beforeGroups: [ButtonGroup],
        afterGroups: [ButtonGroup]
    ) {
        guard !deletedButtons.isEmpty || beforeGroups != afterGroups else {
            return
        }

        editorUndoManager.registerUndo(withTarget: self) { target in
            target.applyGroupDeleteState(
                deletedButtons: deletedButtons,
                groups: beforeGroups,
                oppositeGroups: afterGroups,
                restoresButtons: true
            )
        }
        editorUndoManager.setActionName("Delete Group")
    }

    private func registerAddedGroupUndo(
        insertedButtons: [GamepadButton: ButtonConfig],
        beforeGroups: [ButtonGroup],
        afterGroups: [ButtonGroup]
    ) {
        guard !insertedButtons.isEmpty || beforeGroups != afterGroups else {
            return
        }

        editorUndoManager.registerUndo(withTarget: self) { target in
            target.applyAddedGroupState(
                insertedButtons: insertedButtons,
                groups: beforeGroups,
                oppositeGroups: afterGroups,
                restoresButtons: false
            )
        }
        editorUndoManager.setActionName("Add Group")
    }

    private func applyGroupState(_ groups: [ButtonGroup], oppositeGroups: [ButtonGroup], actionName: String) {
        profile.buttonGroups = sanitizedEditorGroups(groups)
        let restoredGroupID = profile.buttonGroups.first { group in
            !oppositeGroups.contains(group)
        }?.id
        refreshEditorAfterButtonSetChange(selection: [])
        if let restoredGroupID {
            selectedGroupID = restoredGroupID
            previewView.select(group: restoredGroupID)
            if let group = buttonGroup(for: restoredGroupID) {
                detailPanel.loadGroup(group, colorHex: commonColorHex(for: group))
            }
        }
        updateGroupToolbarState()

        editorUndoManager.registerUndo(withTarget: self) { target in
            target.applyGroupState(oppositeGroups, oppositeGroups: groups, actionName: actionName)
        }
        editorUndoManager.setActionName(actionName)
    }

    private func applyEditorState(
        buttonStates: [GamepadButton: ButtonConfig?],
        oppositeButtonStates: [GamepadButton: ButtonConfig?],
        groups: [ButtonGroup],
        oppositeGroups: [ButtonGroup],
        actionName: String
    ) {
        for (button, state) in buttonStates {
            if isProtectedSwitchButton(button), state == nil {
                continue
            }

            if let state {
                profile.buttons[button.rawValue] = configByApplyingGeometryClamp(state)
            } else {
                profile.buttons.removeValue(forKey: button.rawValue)
            }
        }

        profile.buttonGroups = sanitizedEditorGroups(groups)
        let restoredGroupID = profile.buttonGroups.first { group in
            !oppositeGroups.contains(group)
        }?.id
        refreshEditorAfterButtonSetChange(selection: [])
        if let restoredGroupID {
            selectedGroupID = restoredGroupID
            previewView.select(group: restoredGroupID)
            if let group = buttonGroup(for: restoredGroupID) {
                detailPanel.loadGroup(group, colorHex: commonColorHex(for: group))
            }
        }
        updateGroupToolbarState()

        editorUndoManager.registerUndo(withTarget: self) { target in
            target.applyEditorState(
                buttonStates: oppositeButtonStates,
                oppositeButtonStates: buttonStates,
                groups: oppositeGroups,
                oppositeGroups: groups,
                actionName: actionName
            )
        }
        editorUndoManager.setActionName(actionName)
    }

    private func applyGroupDeleteState(
        deletedButtons: [GamepadButton: ButtonConfig],
        groups: [ButtonGroup],
        oppositeGroups: [ButtonGroup],
        restoresButtons: Bool
    ) {
        if restoresButtons {
            for (button, config) in deletedButtons {
                profile.buttons[button.rawValue] = configByApplyingGeometryClamp(config)
            }
        } else {
            for button in deletedButtons.keys {
                guard !isProtectedSwitchButton(button) else {
                    continue
                }

                profile.buttons.removeValue(forKey: button.rawValue)
            }
        }

        profile.buttonGroups = sanitizedEditorGroups(groups)
        let restoredGroupID = restoresButtons ? profile.buttonGroups.first { group in
            !oppositeGroups.contains(group)
        }?.id : nil
        refreshEditorAfterButtonSetChange(selection: [])
        if let restoredGroupID {
            selectedGroupID = restoredGroupID
            previewView.select(group: restoredGroupID)
            if let group = buttonGroup(for: restoredGroupID) {
                detailPanel.loadGroup(group, colorHex: commonColorHex(for: group))
            }
        }
        updateGroupToolbarState()

        editorUndoManager.registerUndo(withTarget: self) { target in
            target.applyGroupDeleteState(
                deletedButtons: deletedButtons,
                groups: oppositeGroups,
                oppositeGroups: groups,
                restoresButtons: !restoresButtons
            )
        }
        editorUndoManager.setActionName("Delete Group")
    }

    private func applyAddedGroupState(
        insertedButtons: [GamepadButton: ButtonConfig],
        groups: [ButtonGroup],
        oppositeGroups: [ButtonGroup],
        restoresButtons: Bool
    ) {
        if restoresButtons {
            for (button, config) in insertedButtons {
                profile.buttons[button.rawValue] = configByApplyingGeometryClamp(config)
            }
        } else {
            for button in insertedButtons.keys {
                guard !isProtectedSwitchButton(button) else {
                    continue
                }

                profile.buttons.removeValue(forKey: button.rawValue)
            }
        }

        profile.buttonGroups = sanitizedEditorGroups(groups)
        let restoredGroupID = restoresButtons ? profile.buttonGroups.first { group in
            !oppositeGroups.contains(group)
        }?.id : nil
        refreshEditorAfterButtonSetChange(selection: [])
        if let restoredGroupID {
            selectedGroupID = restoredGroupID
            previewView.select(group: restoredGroupID)
            focusPreviewForEditorCommands()
            if let group = buttonGroup(for: restoredGroupID) {
                detailPanel.loadGroup(group, colorHex: commonColorHex(for: group))
            }
        }
        updateGroupToolbarState()

        editorUndoManager.registerUndo(withTarget: self) { target in
            target.applyAddedGroupState(
                insertedButtons: insertedButtons,
                groups: oppositeGroups,
                oppositeGroups: groups,
                restoresButtons: !restoresButtons
            )
        }
        editorUndoManager.setActionName("Add Group")
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

        profile.buttonGroups = sanitizedEditorGroups(profile.buttonGroups)
        clampEditableProfileToWorkspace()
        canvasObjects = makeCanvasObjects(from: profile)
        refreshFittedPadSizeFields()
        updatePreviewCanvasLayout()
        reloadPreview(keepSelection: true)

        if let config = profile.buttons[button.rawValue] {
            previewView.select(button: button)
            detailPanel.load(button: button, config: config)
        } else {
            clearInspector()
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

        profile.buttonGroups = sanitizedEditorGroups(profile.buttonGroups)
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
                || lhs.labelColorHex != rhs.labelColorHex
                || lhs.systemEventIconSize != rhs.systemEventIconSize
                || lhs.shape != rhs.shape
                || lhs.enabled != rhs.enabled
                || lhs.interactionMode != rhs.interactionMode
                || lhs.rightClickKeyBindings != rhs.rightClickKeyBindings
                || lhs.rightClickFallsBackToPrimary != rhs.rightClickFallsBackToPrimary
                || lhs.rightClickInteractionMode != rhs.rightClickInteractionMode
                || lhs.joystick != rhs.joystick
                || lhs.dwellAction != rhs.dwellAction
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

            let geometry = geometryForFrame(frame)
            config.x = geometry.centerX
            config.y = geometry.centerY
            config.editorWidth = geometry.width
            config.editorHeight = geometry.height
            profile.buttons[button.rawValue] = configByApplyingGeometryClamp(config)
        }

        clampEditableProfileToWorkspace()
        canvasObjects = makeCanvasObjects(from: profile)
        refreshFittedPadSizeFields()
        updatePreviewCanvasLayout()
        reloadPreview(keepSelection: true)

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

            let geometry = geometryForFrame(frame)
            config.x = geometry.centerX
            config.y = geometry.centerY
            config.editorWidth = geometry.width
            config.editorHeight = geometry.height
            profile.buttons[button.rawValue] = configByApplyingGeometryClamp(config)
        }

        clampEditableProfileToWorkspace()
        canvasObjects = makeCanvasObjects(from: profile)
        refreshFittedPadSizeFields()
        updatePreviewCanvasLayout()
        reloadPreview(keepSelection: true)

        if selectedIDs.count == 1, let button = selectedIDs.first, let config = profile.buttons[button.rawValue] {
            detailPanel.refreshPosition(x: config.x, y: config.y, config: config)
            detailPanel.refreshSize(
                width: config.editorWidth > 0 ? config.editorWidth : config.width,
                height: config.editorHeight > 0 ? config.editorHeight : config.height
            )
        } else {
            clearInspector()
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

    private func currentSavedProfile() -> Profile {
        makeSavedProfile(from: profile).normalizedForSaving()
    }

    private func currentSavedProfileFingerprint() -> Data? {
        let profileForFingerprint = makeSavedProfile(from: profile).normalizedForEditorFingerprint()
        guard var data = fingerprint(for: profileForFingerprint) else {
            return nil
        }

        if let timingData = "|virtualCursorMode:\(profileVirtualCursorModeTimingProfileID.uuidString):\(topProfileVirtualCursorModeEnabled):\(topProfileVirtualCursorModeArmDelaySeconds):\(topProfileVirtualCursorModeTemporaryReleaseSeconds)"
            .data(using: .utf8) {
            data.append(timingData)
        }

        return data
    }

    private func fingerprint(for profile: Profile) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(profile)
    }

    private func refreshFittedPadSizeFields() {
        _ = fittedPadSize(for: profile)
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
        let clamped = pixelAlignedGeometry(geometry, type: config.type)
        config.x = clamped.centerX
        config.y = clamped.centerY
        config.editorWidth = clamped.width
        config.editorHeight = clamped.height
        return config
    }

    private func snappedGeometries(
        _ proposedGeometries: [GamepadButton: ButtonEditorGeometry]
    ) -> CanvasGeometryChangeResult {
        guard snappingCheckbox.state == .on else {
            return CanvasGeometryChangeResult(geometries: proposedGeometries, guides: [])
        }

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
            return [0, maximumWorkspaceSize.width / 2, maximumWorkspaceSize.width]
        case .centered:
            return [-maximumWorkspaceSize.width / 2, 0, maximumWorkspaceSize.width / 2]
        }
    }

    private var workspaceHorizontalSnapCandidates: [CGFloat] {
        switch profile.editorCoordinateMode {
        case .legacyTopLeft:
            return [0, maximumWorkspaceSize.height / 2, maximumWorkspaceSize.height]
        case .centered:
            return [-maximumWorkspaceSize.height / 2, 0, maximumWorkspaceSize.height / 2]
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

    private func geometryForFrame(_ frame: CGRect, anchoredResize: AnchoredButtonResize? = nil) -> ButtonEditorGeometry {
        ButtonEditorGeometry(
            centerX: frame.midX,
            centerY: frame.midY,
            width: frame.width,
            height: frame.height,
            anchoredResize: anchoredResize
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

        let maxWidth = maximumWorkspaceSize.width
        let maxHeight = maximumWorkspaceSize.height
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

    private func pixelAlignedGeometry(_ geometry: ButtonEditorGeometry, type: ButtonType) -> ButtonEditorGeometry {
        let clamped = clampedGeometry(geometry, type: type)
        let alignedFrame = pixelAlignedFrame(
            frameForGeometry(clamped),
            type: type,
            anchoredResize: clamped.anchoredResize
        )
        let alignedGeometry = geometryForFrame(alignedFrame, anchoredResize: clamped.anchoredResize)
        return clampedGeometry(alignedGeometry, type: type)
    }

    private func pixelAlignedFrame(
        _ frame: CGRect,
        type: ButtonType,
        anchoredResize: AnchoredButtonResize?
    ) -> CGRect {
        let minimumSize = ButtonSizing.minimumSize(for: type)
        let workspaceBounds = editorWorkspaceBounds()
        let width = min(max(round(frame.width), CGFloat(minimumSize.width)), workspaceBounds.width)
        let height = min(max(round(frame.height), CGFloat(minimumSize.height)), workspaceBounds.height)
        let originX: CGFloat
        let originY: CGFloat

        if let anchoredResize {
            let anchorX = round(CGFloat(anchoredResize.anchorX))
            let anchorY = round(CGFloat(anchoredResize.anchorY))
            originX = anchoredResize.resizesFromLeft
                ? anchorX - width
                : anchorX
            originY = anchoredResize.resizesFromBottom
                ? anchorY - height
                : anchorY
        } else {
            originX = round(frame.minX)
            originY = round(frame.minY)
        }

        return CGRect(
            x: pixelAlignedOrigin(originX, min: workspaceBounds.minX, max: workspaceBounds.maxX - width),
            y: pixelAlignedOrigin(originY, min: workspaceBounds.minY, max: workspaceBounds.maxY - height),
            width: width,
            height: height
        )
    }

    private func pixelAlignedOrigin(_ value: CGFloat, min minimum: CGFloat, max maximum: CGFloat) -> CGFloat {
        let alignedMinimum = ceil(minimum)
        let alignedMaximum = floor(maximum)
        guard alignedMinimum <= alignedMaximum else {
            return clamp(value, min: minimum, max: maximum)
        }

        return clamp(value, min: alignedMinimum, max: alignedMaximum)
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
            workspaceMaxX = maximumWorkspaceSize.width
            workspaceMinY = 0
            workspaceMaxY = maximumWorkspaceSize.height
        case .centered:
            workspaceMinX = -maximumWorkspaceSize.width / 2
            workspaceMaxX = maximumWorkspaceSize.width / 2
            workspaceMinY = -maximumWorkspaceSize.height / 2
            workspaceMaxY = maximumWorkspaceSize.height / 2
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
            scrollPreviewToCanvasRect(
                canvasRect(forModelRect: editorWorkspaceBounds())
            )
            return
        }

        scrollPreviewToCanvasRect(contentBounds)
    }

    private func scrollToProfileContentIfNeeded() {
        guard shouldScrollToProfileContent else {
            return
        }

        updatePreviewCanvasLayout()

        guard previewScrollView.contentView.bounds.size != .zero,
              previewCanvasView.frame.size != .zero else {
            scheduleProfileContentScrollRetry()
            return
        }

        shouldScrollToProfileContent = false
        pendingProfileContentScrollRetries = 0
        scrollPreviewToProfileContent()
    }

    private func prepareProfileContentScroll() {
        shouldScrollToProfileContent = true
        pendingProfileContentScrollRetries = 3
    }

    private func scheduleProfileContentScrollRetry() {
        guard pendingProfileContentScrollRetries > 0 else {
            return
        }

        pendingProfileContentScrollRetries -= 1
        DispatchQueue.main.async { [weak self] in
            self?.scrollToProfileContentIfNeeded()
        }
    }

    private func scrollPreviewToCanvasRect(_ rect: CGRect) {
        let visibleSize = previewScrollView.contentView.bounds.size
        let documentSize = previewCanvasView.frame.size
        let targetOrigin = CGPoint(
            x: clamp(
                rect.midX - visibleSize.width / 2,
                min: 0,
                max: max(0, documentSize.width - visibleSize.width)
            ),
            y: clamp(
                rect.midY - visibleSize.height / 2,
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

        return canvasRect(forModelRect: contentBounds)
    }

    private func visibleCanvasAnchorPoint() -> CGPoint? {
        guard previewScrollView.contentView.bounds.size != .zero else {
            return nil
        }

        let visibleBounds = previewScrollView.contentView.bounds
        return modelPoint(forCanvasPoint: CGPoint(x: visibleBounds.midX, y: visibleBounds.midY))
    }

    private func canvasPoint(forModelPoint point: CGPoint) -> CGPoint {
        switch profile.editorCoordinateMode {
        case .legacyTopLeft:
            return CGPoint(
                x: point.x * canvasZoomScale + previewCanvasView.workspaceOrigin.x,
                y: point.y * canvasZoomScale + previewCanvasView.workspaceOrigin.y
            )
        case .centered:
            return CGPoint(
                x: (point.x + maximumWorkspaceSize.width / 2) * canvasZoomScale + previewCanvasView.workspaceOrigin.x,
                y: (point.y + maximumWorkspaceSize.height / 2) * canvasZoomScale + previewCanvasView.workspaceOrigin.y
            )
        }
    }

    private func modelPoint(forCanvasPoint point: CGPoint) -> CGPoint {
        let workspacePoint = CGPoint(
            x: (point.x - previewCanvasView.workspaceOrigin.x) / canvasZoomScale,
            y: (point.y - previewCanvasView.workspaceOrigin.y) / canvasZoomScale
        )

        guard profile.editorCoordinateMode == .centered else {
            return workspacePoint
        }

        return CGPoint(
            x: workspacePoint.x - maximumWorkspaceSize.width / 2,
            y: workspacePoint.y - maximumWorkspaceSize.height / 2
        )
    }

    private func canvasRect(forModelRect rect: CGRect) -> CGRect {
        let origin = canvasPoint(forModelPoint: rect.origin)
        return CGRect(
            x: origin.x,
            y: origin.y,
            width: rect.width * canvasZoomScale,
            height: rect.height * canvasZoomScale
        )
    }

    private func clamp(_ value: CGFloat, min minimum: CGFloat, max maximum: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, minimum), maximum)
    }
}

private extension Profile {
    func normalizedForEditorFingerprint() -> Profile {
        var normalizedProfile = self
        var normalizedButtons: [String: ButtonConfig] = [:]
        var remappedButtonIDs: [String: String] = [:]

        for button in orderedButtonIDs {
            guard let config = buttons[button.rawValue] else {
                continue
            }

            let key = stableFingerprintKey(for: button)
            normalizedButtons[key] = config
            remappedButtonIDs[button.rawValue] = key
        }

        normalizedProfile.buttons = normalizedButtons
        normalizedProfile.buttonGroups = Self.sanitizedFingerprintGroups(
            buttonGroups.map { group in
                ButtonGroup(
                    id: group.id,
                    name: group.name,
                    memberButtonIDs: group.memberButtonIDs.compactMap { remappedButtonIDs[$0] }
                )
            },
            validButtonIDs: Set(normalizedButtons.keys)
        )
        normalizedProfile.subProfiles = subProfiles.map { $0.normalizedForEditorFingerprint() }
        return normalizedProfile
    }

    private func stableFingerprintKey(for button: GamepadButton) -> String {
        if button.isGenerated || button.isSubProfileSwitch {
            return button.rawValue
        }

        return "legacy:\(button.rawValue)"
    }

    private static func sanitizedFingerprintGroups(_ groups: [ButtonGroup], validButtonIDs: Set<String>) -> [ButtonGroup] {
        var claimedButtonIDs = Set<String>()

        return groups.compactMap { group in
            var seen = Set<String>()
            let members = group.memberButtonIDs.filter { buttonID in
                guard validButtonIDs.contains(buttonID),
                      !seen.contains(buttonID),
                      !claimedButtonIDs.contains(buttonID) else {
                    return false
                }

                seen.insert(buttonID)
                claimedButtonIDs.insert(buttonID)
                return true
            }

            guard members.count >= 2 else {
                return nil
            }

            let trimmedName = group.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return ButtonGroup(
                id: group.id,
                name: trimmedName.isEmpty ? "Group" : trimmedName,
                memberButtonIDs: members
            )
        }
    }
}
