import Cocoa

final class ConfiguratorViewController: NSSplitViewController {

    private let profileListViewController = ProfileListViewController()
    private let editorViewController = ButtonEditorViewController()
    private var profilesDidChangeObserver: NSObjectProtocol?

    override func viewDidLoad() {
        super.viewDidLoad()

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: profileListViewController)
        sidebarItem.minimumThickness = 180
        sidebarItem.maximumThickness = 220

        addSplitViewItem(sidebarItem)
        addSplitViewItem(NSSplitViewItem(viewController: editorViewController))

        profileListViewController.onProfileSelected = { [weak self] profile in
            self?.editorViewController.load(profile: profile)
        }

        editorViewController.onProfileSaved = { profile in
            ProfileStore.shared.upsert(profile)
        }

        profilesDidChangeObserver = NotificationCenter.default.addObserver(
            forName: ProfileStore.profilesDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.profileListViewController.reload()
            self?.editorViewController.refreshFromStoreIfNeeded()
        }

        editorViewController.load(profile: ProfileStore.shared.activeProfile)
    }

    deinit {
        if let profilesDidChangeObserver {
            NotificationCenter.default.removeObserver(profilesDidChangeObserver)
        }
    }
}

final class ProfileListViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {

    var onProfileSelected: ((Profile) -> Void)?

    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private var isReloadingSelection = false

    private var profiles: [Profile] {
        ProfileStore.shared.profiles
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 400))
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let nameColumn = NSTableColumn(identifier: .init("name"))
        nameColumn.title = "Profiles"

        tableView.addTableColumn(nameColumn)
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 28
        tableView.usesAlternatingRowBackgroundColors = true

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let bar = NSStackView(views: [
            makeButton(title: "+", action: #selector(addProfile)),
            makeButton(title: "⎘", action: #selector(duplicateProfile)),
            makeButton(title: "−", action: #selector(deleteProfile)),
            NSView(),
        ])
        bar.orientation = .horizontal
        bar.spacing = 4
        bar.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(scrollView)
        view.addSubview(bar)

        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
            bar.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -4),
            bar.heightAnchor.constraint(equalToConstant: 26),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bar.topAnchor, constant: -4),
        ])

        reload()
    }

    func reload() {
        isReloadingSelection = true
        defer { isReloadingSelection = false }

        tableView.reloadData()

        guard let index = profiles.firstIndex(where: { $0.id == ProfileStore.shared.activeProfileID }) else {
            tableView.deselectAll(nil)
            return
        }

        if tableView.selectedRow == index {
            return
        }

        tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        profiles.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let label = NSTextField(labelWithString: profiles[row].name)
        label.font = .systemFont(ofSize: 13)
        return label
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        if isReloadingSelection {
            return
        }

        let row = tableView.selectedRow
        guard row >= 0 else {
            return
        }

        let profile = profiles[row]

        if profile.id == ProfileStore.shared.activeProfileID {
            onProfileSelected?(profile)
            return
        }

        ProfileStore.shared.setActive(profile.id)
        onProfileSelected?(profile)
    }

    private func makeButton(title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .smallSquare
        return button
    }

    @objc private func addProfile() {
        let profile = Profile.makeDefault(name: "Profile \(profiles.count + 1)")
        ProfileStore.shared.upsert(profile)
        ProfileStore.shared.setActive(profile.id)
        onProfileSelected?(profile)
    }

    @objc private func duplicateProfile() {
        let row = tableView.selectedRow
        guard row >= 0 else {
            return
        }

        guard let duplicatedProfile = ProfileStore.shared.duplicate(profiles[row].id) else {
            return
        }

        ProfileStore.shared.setActive(duplicatedProfile.id)
        onProfileSelected?(duplicatedProfile)
    }

    @objc private func deleteProfile() {
        let row = tableView.selectedRow
        guard row >= 0 else {
            return
        }

        ProfileStore.shared.delete(profiles[row].id)
        onProfileSelected?(ProfileStore.shared.activeProfile)
    }
}

final class ButtonEditorViewController: NSViewController {

    var onProfileSaved: ((Profile) -> Void)?

    private var profile = ProfileStore.shared.activeProfile

    private let nameField = NSTextField()
    private let opacitySlider = NSSlider()
    private let opacityLabel = NSTextField(labelWithString: "90%")
    private let padWidthField = NSTextField()
    private let padHeightField = NSTextField()
    private let previewView = GamepadPreviewView()
    private let detailPanel = ButtonDetailPanel()

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 780, height: 580))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildLayout()
        load(profile: ProfileStore.shared.activeProfile)
    }

    func load(profile: Profile) {
        self.profile = profile
        nameField.stringValue = profile.name
        opacitySlider.doubleValue = profile.opacity
        opacityLabel.stringValue = "\(Int(profile.opacity * 100))%"
        padWidthField.stringValue = "\(Int(profile.padWidth))"
        padHeightField.stringValue = "\(Int(profile.padHeight))"
        previewView.reload(profile: profile, keepSelection: false)
        detailPanel.clear()
    }

    func refreshFromStoreIfNeeded() {
        if let updatedProfile = ProfileStore.shared.profiles.first(where: { $0.id == profile.id }) {
            load(profile: updatedProfile)
        } else {
            load(profile: ProfileStore.shared.activeProfile)
        }
    }

    private func buildLayout() {
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
        padHeightField.bezelStyle = .roundedBezel
        padHeightField.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)

        let saveButton = NSButton(title: "Save & Apply", target: self, action: #selector(saveProfile))
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"

        let topBar = NSStackView(views: [
            makeLabel("Name:"),
            nameField,
            makeLabel("  Opacity:"),
            opacitySlider,
            opacityLabel,
            makeLabel("  Size:"),
            padWidthField,
            makeLabel("×"),
            padHeightField,
            NSView(),
            saveButton,
        ])
        topBar.orientation = .horizontal
        topBar.alignment = .centerY
        topBar.spacing = 6
        topBar.translatesAutoresizingMaskIntoConstraints = false

        previewView.translatesAutoresizingMaskIntoConstraints = false
        previewView.onButtonSelected = { [weak self] button in
            guard
                let self,
                let config = self.profile.buttons[button.rawValue]
            else {
                return
            }

            self.detailPanel.load(button: button, config: config)
        }
        previewView.onButtonMoved = { [weak self] button, x, y in
            guard let self else {
                return
            }

            self.profile.buttons[button.rawValue]?.x = x
            self.profile.buttons[button.rawValue]?.y = y

            if let config = self.profile.buttons[button.rawValue] {
                self.detailPanel.refreshPosition(x: x, y: y, config: config)
            }
        }
        previewView.onButtonResized = { [weak self] button, width, height in
            guard let self else {
                return
            }

            self.profile.buttons[button.rawValue]?.width = width
            self.profile.buttons[button.rawValue]?.height = height
            self.detailPanel.refreshSize(width: width, height: height)
        }

        detailPanel.translatesAutoresizingMaskIntoConstraints = false
        detailPanel.onChanged = { [weak self] button, config in
            guard let self else {
                return
            }

            self.profile.buttons[button.rawValue] = config
            self.previewView.reload(profile: self.profile, keepSelection: true)
        }

        let hint = NSTextField(
            labelWithString: "Click a button to select it. Drag the button to move it or the corner handle to resize it."
        )
        hint.font = .systemFont(ofSize: 10)
        hint.textColor = .secondaryLabelColor
        hint.translatesAutoresizingMaskIntoConstraints = false

        [topBar, previewView, detailPanel, hint].forEach(view.addSubview(_:))

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
            previewView.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 14),
            previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            previewView.widthAnchor.constraint(equalToConstant: 420),
            previewView.heightAnchor.constraint(equalToConstant: 300),
            hint.topAnchor.constraint(equalTo: previewView.bottomAnchor, constant: 6),
            hint.leadingAnchor.constraint(equalTo: previewView.leadingAnchor),
            detailPanel.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 14),
            detailPanel.leadingAnchor.constraint(equalTo: previewView.trailingAnchor, constant: 20),
            detailPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            detailPanel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
        ])
    }

    private func makeLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12)
        return label
    }

    @objc private func opacityMoved() {
        profile.opacity = opacitySlider.doubleValue
        opacityLabel.stringValue = "\(Int(profile.opacity * 100))%"
    }

    @objc private func saveProfile() {
        if !nameField.stringValue.isEmpty {
            profile.name = nameField.stringValue
        }

        profile.padWidth = Double(padWidthField.stringValue) ?? profile.padWidth
        profile.padHeight = Double(padHeightField.stringValue) ?? profile.padHeight

        onProfileSaved?(profile)
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
}

final class GamepadPreviewView: NSView {

    var onButtonSelected: ((GamepadButton) -> Void)?
    var onButtonMoved: ((GamepadButton, Double, Double) -> Void)?
    var onButtonResized: ((GamepadButton, Double, Double) -> Void)?

    private var buttonLayers: [GamepadButton: CALayer] = [:]
    private var handleLayers: [GamepadButton: CALayer] = [:]
    private var selectedButton: GamepadButton?
    private var profile = ProfileStore.shared.activeProfile
    private var lastRenderedSize: CGSize = .zero

    private enum DragMode {
        case move
        case resizeBottomRight
    }

    private var dragMode: DragMode = .move
    private var dragButton: GamepadButton?
    private var dragStartMouse: CGPoint = .zero
    private var dragStartButtonCenter: CGPoint = .zero
    private var dragStartButtonSize: CGSize = .zero

    private let handleSize: CGFloat = 8

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.10, alpha: 1).cgColor
        layer?.cornerRadius = 14
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func reload(profile: Profile, keepSelection: Bool) {
        let previousSelection = keepSelection ? selectedButton : nil
        let shouldRebuild = bounds.size != lastRenderedSize
        self.profile = profile
        lastRenderedSize = bounds.size

        if shouldRebuild {
            rebuildLayers()
        } else {
            updateExistingLayers()
        }

        highlight(previousSelection)
    }

    private func rebuildLayers() {
        buttonLayers.values.forEach { $0.removeFromSuperlayer() }
        handleLayers.values.forEach { $0.removeFromSuperlayer() }
        buttonLayers.removeAll()
        handleLayers.removeAll()

        let width = bounds.width
        let height = bounds.height

        for button in GamepadButton.allCases {
            guard let config = profile.buttons[button.rawValue], config.enabled else {
                continue
            }

            let centerX = CGFloat(config.x) * width
            let centerY = CGFloat(config.y) * height
            let buttonWidth = CGFloat(config.width) * width
            let buttonHeight = CGFloat(config.height) * height

            let buttonLayer = CALayer()
            buttonLayer.frame = CGRect(
                x: centerX - (buttonWidth / 2),
                y: centerY - (buttonHeight / 2),
                width: buttonWidth,
                height: buttonHeight
            )
            buttonLayer.backgroundColor = NSColor(hex: config.colorHex).withAlphaComponent(0.85).cgColor
            buttonLayer.cornerRadius = 6

            let textLayer = CATextLayer()
            textLayer.string = config.label
            textLayer.fontSize = 10
            textLayer.alignmentMode = .center
            textLayer.foregroundColor = NSColor.white.cgColor
            textLayer.contentsScale = window?.backingScaleFactor ?? 2
            textLayer.frame = buttonLayer.bounds
            buttonLayer.addSublayer(textLayer)

            layer?.addSublayer(buttonLayer)
            buttonLayers[button] = buttonLayer

            let handleLayer = CALayer()
            handleLayer.frame = CGRect(
                x: buttonLayer.frame.maxX - handleSize,
                y: buttonLayer.frame.minY,
                width: handleSize,
                height: handleSize
            )
            handleLayer.backgroundColor = NSColor.white.withAlphaComponent(0.7).cgColor
            handleLayer.cornerRadius = 2
            handleLayer.isHidden = true
            layer?.addSublayer(handleLayer)
            handleLayers[button] = handleLayer
        }
    }

    private func updateExistingLayers() {
        let activeButtons = Set(GamepadButton.allCases.filter {
            guard let config = profile.buttons[$0.rawValue] else {
                return false
            }

            return config.enabled
        })

        for button in Array(buttonLayers.keys) where !activeButtons.contains(button) {
            buttonLayers[button]?.removeFromSuperlayer()
            buttonLayers.removeValue(forKey: button)

            handleLayers[button]?.removeFromSuperlayer()
            handleLayers.removeValue(forKey: button)
        }

        for button in GamepadButton.allCases {
            guard let config = profile.buttons[button.rawValue], config.enabled else {
                continue
            }

            let buttonLayer = buttonLayers[button] ?? makeButtonLayer(for: button)
            let handleLayer = handleLayers[button] ?? makeHandleLayer(for: button)
            update(buttonLayer: buttonLayer, handleLayer: handleLayer, with: config)
        }
    }

    private func makeButtonLayer(for button: GamepadButton) -> CALayer {
        let buttonLayer = CALayer()
        buttonLayer.cornerRadius = 6

        let textLayer = CATextLayer()
        textLayer.fontSize = 10
        textLayer.alignmentMode = .center
        textLayer.foregroundColor = NSColor.white.cgColor
        textLayer.contentsScale = window?.backingScaleFactor ?? 2
        buttonLayer.addSublayer(textLayer)

        layer?.addSublayer(buttonLayer)
        buttonLayers[button] = buttonLayer
        return buttonLayer
    }

    private func makeHandleLayer(for button: GamepadButton) -> CALayer {
        let handleLayer = CALayer()
        handleLayer.backgroundColor = NSColor.white.withAlphaComponent(0.7).cgColor
        handleLayer.cornerRadius = 2
        handleLayer.isHidden = true
        layer?.addSublayer(handleLayer)
        handleLayers[button] = handleLayer
        return handleLayer
    }

    private func update(buttonLayer: CALayer, handleLayer: CALayer, with config: ButtonConfig) {
        let width = bounds.width
        let height = bounds.height
        let centerX = CGFloat(config.x) * width
        let centerY = CGFloat(config.y) * height
        let buttonWidth = CGFloat(config.width) * width
        let buttonHeight = CGFloat(config.height) * height

        buttonLayer.frame = CGRect(
            x: centerX - (buttonWidth / 2),
            y: centerY - (buttonHeight / 2),
            width: buttonWidth,
            height: buttonHeight
        )
        buttonLayer.backgroundColor = NSColor(hex: config.colorHex).withAlphaComponent(0.85).cgColor

        if let textLayer = buttonLayer.sublayers?.first as? CATextLayer {
            textLayer.string = config.label
            textLayer.contentsScale = window?.backingScaleFactor ?? 2
            textLayer.frame = buttonLayer.bounds
        }

        handleLayer.frame = CGRect(
            x: buttonLayer.frame.maxX - handleSize,
            y: buttonLayer.frame.minY,
            width: handleSize,
            height: handleSize
        )
    }

    override func layout() {
        super.layout()
        guard bounds.size != .zero, bounds.size != lastRenderedSize else {
            return
        }

        reload(profile: profile, keepSelection: true)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let button = button(at: point), let config = profile.buttons[button.rawValue] else {
            highlight(nil)
            return
        }

        highlight(button)
        onButtonSelected?(button)
        dragButton = button
        dragStartMouse = point

        let width = bounds.width
        let height = bounds.height
        dragStartButtonCenter = CGPoint(x: CGFloat(config.x) * width, y: CGFloat(config.y) * height)
        dragStartButtonSize = CGSize(width: CGFloat(config.width) * width, height: CGFloat(config.height) * height)
        dragMode = isOnHandle(point, for: button) ? .resizeBottomRight : .move
    }

    override func mouseDragged(with event: NSEvent) {
        guard let button = dragButton else {
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        let deltaX = point.x - dragStartMouse.x
        let deltaY = point.y - dragStartMouse.y
        let width = bounds.width
        let height = bounds.height

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        switch dragMode {
        case .move:
            let nextX = (dragStartButtonCenter.x + deltaX).clamped(to: 0 ... width)
            let nextY = (dragStartButtonCenter.y + deltaY).clamped(to: 0 ... height)

            if let buttonLayer = buttonLayers[button] {
                buttonLayer.position = CGPoint(x: nextX, y: nextY)
                updateHandleFrame(for: button, buttonLayer: buttonLayer)
            }

            onButtonMoved?(button, nextX / width, nextY / height)

        case .resizeBottomRight:
            let newWidth = max(20, dragStartButtonSize.width + deltaX)
            let newHeight = max(14, dragStartButtonSize.height - deltaY)

            if let buttonLayer = buttonLayers[button] {
                let center = buttonLayer.position
                buttonLayer.bounds = CGRect(origin: .zero, size: CGSize(width: newWidth, height: newHeight))
                buttonLayer.position = center

                if let textLayer = buttonLayer.sublayers?.first {
                    textLayer.frame = buttonLayer.bounds
                }

                updateHandleFrame(for: button, buttonLayer: buttonLayer)
            }

            onButtonResized?(button, newWidth / width, newHeight / height)
        }

        CATransaction.commit()
    }

    override func mouseUp(with event: NSEvent) {
        dragButton = nil
    }

    private func button(at point: CGPoint) -> GamepadButton? {
        let width = bounds.width
        let height = bounds.height

        for button in GamepadButton.allCases {
            guard let config = profile.buttons[button.rawValue], config.enabled else {
                continue
            }

            let centerX = CGFloat(config.x) * width
            let centerY = CGFloat(config.y) * height
            let buttonWidth = CGFloat(config.width) * width
            let buttonHeight = CGFloat(config.height) * height
            let frame = CGRect(
                x: centerX - (buttonWidth / 2),
                y: centerY - (buttonHeight / 2),
                width: buttonWidth,
                height: buttonHeight
            )

            if frame.contains(point) {
                return button
            }
        }

        return nil
    }

    private func isOnHandle(_ point: CGPoint, for button: GamepadButton) -> Bool {
        guard let handleLayer = handleLayers[button] else {
            return false
        }

        return !handleLayer.isHidden && handleLayer.frame.contains(point)
    }

    private func highlight(_ button: GamepadButton?) {
        buttonLayers.values.forEach {
            $0.borderWidth = 0
            $0.shadowOpacity = 0
        }
        handleLayers.values.forEach { $0.isHidden = true }

        guard let button, let buttonLayer = buttonLayers[button] else {
            selectedButton = nil
            return
        }

        buttonLayer.borderWidth = 2
        buttonLayer.borderColor = NSColor.white.cgColor
        buttonLayer.shadowOpacity = 0.6
        buttonLayer.shadowColor = NSColor.white.cgColor
        buttonLayer.shadowRadius = 4
        buttonLayer.shadowOffset = .zero
        handleLayers[button]?.isHidden = false
        selectedButton = button
    }

    private func updateHandleFrame(for button: GamepadButton, buttonLayer: CALayer) {
        guard let handleLayer = handleLayers[button] else {
            return
        }

        handleLayer.frame = CGRect(
            x: buttonLayer.frame.maxX - handleSize,
            y: buttonLayer.frame.minY,
            width: handleSize,
            height: handleSize
        )
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
