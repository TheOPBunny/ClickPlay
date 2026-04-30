import Cocoa

final class ProfileListViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {

    var onProfileSelected: ((Profile) -> Void)?

    private final class SidebarItem: NSObject {
        let profileID: UUID
        let parentID: UUID?

        init(profileID: UUID, parentID: UUID?) {
            self.profileID = profileID
            self.parentID = parentID
        }

        var isSubProfile: Bool {
            parentID != nil
        }
    }

    private let outlineView = NSOutlineView()
    private let scrollView = NSScrollView()
    private let titleLabel = NSTextField(labelWithString: "Profiles")
    private let bar = NSStackView()
    private var isReloadingSelection = false
    private var isCollapsed = false
    private var templateManagerWindowController: NSWindowController?

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

        outlineView.addTableColumn(nameColumn)
        outlineView.outlineTableColumn = nameColumn
        outlineView.headerView = nil
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.rowHeight = 28
        outlineView.usesAlternatingRowBackgroundColors = true

        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .boldSystemFont(ofSize: 13)
        titleLabel.lineBreakMode = .byTruncatingTail

        let header = NSStackView(views: [
            titleLabel,
            NSView(),
        ])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 6
        header.edgeInsets = NSEdgeInsets(top: 4, left: 6, bottom: 4, right: 6)
        header.translatesAutoresizingMaskIntoConstraints = false

        bar.addArrangedSubview(makeButton(title: "+", action: #selector(showAddProfileMenu(_:))))
        bar.addArrangedSubview(makeButton(title: "⎘", action: #selector(duplicateSelection)))
        bar.addArrangedSubview(makeButton(title: "−", action: #selector(deleteSelection)))
        bar.addArrangedSubview(makeButton(title: "...", action: #selector(showTemplateMenu(_:))))
        bar.addArrangedSubview(NSView())
        bar.orientation = .horizontal
        bar.spacing = 4
        bar.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(header)
        view.addSubview(scrollView)
        view.addSubview(bar)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 32),
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
            bar.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -4),
            bar.heightAnchor.constraint(equalToConstant: 26),
            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bar.topAnchor, constant: -4),
        ])

        reload()
    }

    func setCollapsed(_ collapsed: Bool) {
        isCollapsed = collapsed
        titleLabel.isHidden = collapsed
        scrollView.isHidden = collapsed
        bar.isHidden = collapsed
    }

    func reload() {
        isReloadingSelection = true
        defer { isReloadingSelection = false }

        outlineView.reloadData()
        expandAllProfiles()
        selectActiveSubProfile()
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let item = item as? SidebarItem else {
            return profiles.count
        }

        return profile(with: item.profileID)?.subProfiles.count ?? 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let item = item as? SidebarItem,
           let profile = profile(with: item.profileID) {
            return SidebarItem(profileID: profile.subProfiles[index].id, parentID: profile.id)
        }

        return SidebarItem(profileID: profiles[index].id, parentID: nil)
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let item = item as? SidebarItem, !item.isSubProfile else {
            return false
        }

        return !(profile(with: item.profileID)?.subProfiles.isEmpty ?? true)
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let item = item as? SidebarItem else {
            return nil
        }

        let resolvedName = item.isSubProfile
            ? subProfile(with: item.profileID, parentID: item.parentID)?.name
            : profile(with: item.profileID)?.name
        let label = NSTextField(labelWithString: resolvedName ?? "")
        label.font = item.isSubProfile ? .systemFont(ofSize: 13) : .boldSystemFont(ofSize: 13)
        label.lineBreakMode = .byTruncatingTail
        return label
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        if isReloadingSelection {
            return
        }

        guard let item = outlineView.item(atRow: outlineView.selectedRow) as? SidebarItem else {
            return
        }

        if let parentID = item.parentID,
           let subProfile = subProfile(with: item.profileID, parentID: parentID) {
            ProfileStore.shared.setActiveSubProfile(subProfile.id, in: parentID)
            onProfileSelected?(subProfile)
            return
        }

        ProfileStore.shared.setActive(item.profileID)
        onProfileSelected?(ProfileStore.shared.activeResolvedProfile)
    }

    private func makeButton(title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .smallSquare
        return button
    }

    @objc private func showAddProfileMenu(_ sender: NSButton) {
        let menu = NSMenu()

        let templateProfileItem = NSMenuItem(title: "New Profile from Template", action: nil, keyEquivalent: "")
        templateProfileItem.submenu = makeTemplateSubmenu(kind: .profile)
        menu.addItem(templateProfileItem)

        let blankProfileItem = NSMenuItem(title: "New Blank Profile", action: #selector(addBlankProfile), keyEquivalent: "")
        blankProfileItem.target = self
        menu.addItem(blankProfileItem)

        menu.addItem(NSMenuItem.separator())

        let templateLayerItem = NSMenuItem(title: "New Layer from Template", action: nil, keyEquivalent: "")
        templateLayerItem.submenu = makeTemplateSubmenu(kind: .layer)
        templateLayerItem.isEnabled = selectedParentID() != nil
        menu.addItem(templateLayerItem)

        let blankLayerItem = NSMenuItem(title: "New Blank Layer", action: #selector(addBlankSubProfile), keyEquivalent: "")
        blankLayerItem.target = self
        blankLayerItem.isEnabled = selectedParentID() != nil
        menu.addItem(blankLayerItem)

        menu.popUp(positioning: nil, at: CGPoint(x: 0, y: sender.bounds.maxY + 2), in: sender)
    }

    @objc private func addBlankProfile() {
        let profile = Profile.makeBlank(name: "Profile \(profiles.count + 1)").asTopLevelContainer()
        add(profile: profile)
    }

    @objc private func addBlankSubProfile() {
        addSubProfile(fromTemplate: false)
    }

    @objc private func addDefaultTemplateProfile() {
        let profile = Profile.makeStarterTemplate(name: "Profile \(profiles.count + 1)").asTopLevelContainer()
        add(profile: profile)
    }

    @objc private func addDefaultTemplateSubProfile() {
        addSubProfile(fromTemplate: true)
    }

    @objc private func addProfileFromSavedTemplate(_ sender: NSMenuItem) {
        guard let templateID = representedTemplateID(sender) else { return }
        let existingNames = Set(profiles.map(\.name))
        let baseName = ProfileTemplateStore.shared.templates(kind: .profile)
            .first { $0.id == templateID }?.name ?? "Profile"
        let name = uniqueName(baseName, existingNames: existingNames)
        guard let profile = ProfileTemplateStore.shared.makeProfile(fromTemplateID: templateID, name: name) else {
            return
        }
        add(profile: profile)
    }

    @objc private func addSubProfileFromSavedTemplate(_ sender: NSMenuItem) {
        guard let parentID = selectedParentID(),
              let templateID = representedTemplateID(sender),
              let parentProfile = profile(with: parentID) else {
            return
        }
        let existingNames = Set(parentProfile.subProfiles.map(\.name))
        let baseName = ProfileTemplateStore.shared.templates(kind: .layer)
            .first { $0.id == templateID }?.name ?? "Layer"
        let name = uniqueName(baseName, existingNames: existingNames)
        guard let layer = ProfileTemplateStore.shared.makeLayer(fromTemplateID: templateID, name: name),
              ProfileStore.shared.addSubProfile(layer, to: parentID) != nil else {
            return
        }

        onProfileSelected?(ProfileStore.shared.activeResolvedProfile)
    }

    @objc private func showTemplateMenu(_ sender: NSButton) {
        let menu = NSMenu()

        let saveItem = NSMenuItem(title: "Save Current as Template...", action: #selector(saveCurrentAsTemplate), keyEquivalent: "")
        saveItem.target = self
        saveItem.isEnabled = selectedSidebarItem() != nil
        menu.addItem(saveItem)

        let manageItem = NSMenuItem(title: "Manage Templates...", action: #selector(showTemplateManager), keyEquivalent: "")
        manageItem.target = self
        menu.addItem(manageItem)

        menu.popUp(positioning: nil, at: CGPoint(x: 0, y: sender.bounds.maxY + 2), in: sender)
    }

    @objc private func saveCurrentAsTemplate() {
        guard let item = selectedSidebarItem(),
              let selectedProfile = profile(for: item) else {
            return
        }

        let kind: ProfileTemplateKind = item.isSubProfile ? .layer : .profile
        let prompt = item.isSubProfile ? "Save Layer Template" : "Save Profile Template"
        guard let name = promptForName(title: prompt, message: "Choose a name for this template.", defaultName: selectedProfile.name) else {
            return
        }

        ProfileTemplateStore.shared.saveTemplate(named: name, kind: kind, profile: selectedProfile)
    }

    @objc private func showTemplateManager() {
        if let templateManagerWindowController {
            templateManagerWindowController.showWindow(self)
            templateManagerWindowController.window?.makeKeyAndOrderFront(self)
            return
        }

        let controller = TemplateManagerViewController()
        let window = NSWindow(contentViewController: controller)
        window.title = "Manage Templates"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 520, height: 360))
        window.minSize = NSSize(width: 420, height: 280)
        let windowController = NSWindowController(window: window)
        windowController.shouldCascadeWindows = true
        templateManagerWindowController = windowController
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.templateManagerWindowController = nil
        }
        windowController.showWindow(self)
    }

    private func add(profile: Profile) {
        ProfileStore.shared.upsert(profile)
        ProfileStore.shared.setActive(profile.id)
        onProfileSelected?(ProfileStore.shared.activeResolvedProfile)
    }

    private func addSubProfile(fromTemplate: Bool) {
        guard let parentID = selectedParentID(),
              ProfileStore.shared.addSubProfile(to: parentID, fromTemplate: fromTemplate) != nil else {
            return
        }

        onProfileSelected?(ProfileStore.shared.activeResolvedProfile)
    }

    @objc private func duplicateSelection() {
        guard let item = outlineView.item(atRow: outlineView.selectedRow) as? SidebarItem else {
            return
        }

        if let parentID = item.parentID {
            guard ProfileStore.shared.duplicateSubProfile(item.profileID, in: parentID) != nil else {
                return
            }
            onProfileSelected?(ProfileStore.shared.activeResolvedProfile)
            return
        }

        guard let duplicatedProfile = ProfileStore.shared.duplicate(item.profileID) else {
            return
        }

        ProfileStore.shared.setActive(duplicatedProfile.id)
        onProfileSelected?(ProfileStore.shared.activeResolvedProfile)
    }

    @objc private func deleteSelection() {
        guard let item = outlineView.item(atRow: outlineView.selectedRow) as? SidebarItem else {
            return
        }

        if let parentID = item.parentID {
            ProfileStore.shared.deleteSubProfile(item.profileID, in: parentID)
            onProfileSelected?(ProfileStore.shared.activeResolvedProfile)
            return
        }

        ProfileStore.shared.delete(item.profileID)
        onProfileSelected?(ProfileStore.shared.activeResolvedProfile)
    }

    private func expandAllProfiles() {
        var row = 0
        while row < outlineView.numberOfRows {
            if let item = outlineView.item(atRow: row) {
                outlineView.expandItem(item)
            }
            row += 1
        }
    }

    private func selectActiveSubProfile() {
        let activeProfile = ProfileStore.shared.activeProfile
        let selectedID = activeProfile.activeSubProfileID ?? activeProfile.subProfiles.first?.id ?? activeProfile.id

        for row in 0..<outlineView.numberOfRows {
            guard let item = outlineView.item(atRow: row) as? SidebarItem else {
                continue
            }

            if item.profileID == selectedID {
                outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                return
            }
        }

        outlineView.deselectAll(nil)
    }

    private func selectedParentID() -> UUID? {
        guard let item = outlineView.item(atRow: outlineView.selectedRow) as? SidebarItem else {
            return ProfileStore.shared.activeProfileID
        }

        return item.parentID ?? item.profileID
    }

    private func selectedSidebarItem() -> SidebarItem? {
        outlineView.item(atRow: outlineView.selectedRow) as? SidebarItem
    }

    private func profile(for item: SidebarItem) -> Profile? {
        if let parentID = item.parentID {
            return subProfile(with: item.profileID, parentID: parentID)
        }

        return profile(with: item.profileID)
    }

    private func makeTemplateSubmenu(kind: ProfileTemplateKind) -> NSMenu {
        let menu = NSMenu()
        let templates = ProfileTemplateStore.shared.templates(kind: kind)

        let defaultSelector = kind == .profile
            ? #selector(addDefaultTemplateProfile)
            : #selector(addDefaultTemplateSubProfile)
        let defaultItem = NSMenuItem(title: "Default Template", action: defaultSelector, keyEquivalent: "")
        defaultItem.target = self
        menu.addItem(defaultItem)

        guard !templates.isEmpty else {
            menu.addItem(NSMenuItem.separator())
            let emptyItem = NSMenuItem(title: "No Saved Templates", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
            return menu
        }

        menu.addItem(NSMenuItem.separator())
        for template in templates {
            let selector = kind == .profile
                ? #selector(addProfileFromSavedTemplate(_:))
                : #selector(addSubProfileFromSavedTemplate(_:))
            let item = NSMenuItem(title: template.name, action: selector, keyEquivalent: "")
            item.target = self
            item.representedObject = template.id.uuidString
            menu.addItem(item)
        }

        return menu
    }

    private func representedTemplateID(_ sender: NSMenuItem) -> UUID? {
        guard let idString = sender.representedObject as? String else { return nil }
        return UUID(uuidString: idString)
    }

    private func uniqueName(_ baseName: String, existingNames: Set<String>) -> String {
        let trimmedBaseName = baseName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedBaseName = trimmedBaseName.isEmpty ? "Untitled" : trimmedBaseName
        guard existingNames.contains(resolvedBaseName) else {
            return resolvedBaseName
        }

        var index = 2
        while true {
            let candidate = "\(resolvedBaseName) \(index)"
            if !existingNames.contains(candidate) {
                return candidate
            }
            index += 1
        }
    }

    private func promptForName(title: String, message: String, defaultName: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        textField.stringValue = defaultName
        textField.selectText(nil)
        alert.accessoryView = textField

        guard alert.runModal() == .alertFirstButtonReturn else {
            return nil
        }

        let trimmed = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultName : trimmed
    }

    private func profile(with id: UUID) -> Profile? {
        profiles.first { $0.id == id }
    }

    private func subProfile(with id: UUID, parentID: UUID?) -> Profile? {
        guard let parentID,
              let profile = profile(with: parentID) else {
            return nil
        }

        return profile.subProfiles.first { $0.id == id }
    }
}

private final class TemplateManagerViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {

    private let segmentedControl = NSSegmentedControl(labels: ["Profiles", "Layers"], trackingMode: .selectOne, target: nil, action: nil)
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let renameButton = NSButton(title: "Rename", target: nil, action: nil)
    private let deleteButton = NSButton(title: "Delete", target: nil, action: nil)
    private let emptyLabel = NSTextField(labelWithString: "No saved templates")
    private var templatesDidChangeObserver: NSObjectProtocol?

    private var selectedKind: ProfileTemplateKind {
        segmentedControl.selectedSegment == 1 ? .layer : .profile
    }

    private var visibleTemplates: [ProfileTemplate] {
        ProfileTemplateStore.shared.templates(kind: selectedKind)
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 360))
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        segmentedControl.target = self
        segmentedControl.action = #selector(changeTemplateKind)
        segmentedControl.selectedSegment = 0
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false

        let nameColumn = NSTableColumn(identifier: .init("name"))
        nameColumn.title = "Name"
        nameColumn.resizingMask = .autoresizingMask
        tableView.addTableColumn(nameColumn)
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 28
        tableView.usesAlternatingRowBackgroundColors = true

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        renameButton.target = self
        renameButton.action = #selector(renameSelectedTemplate)
        renameButton.bezelStyle = .rounded

        deleteButton.target = self
        deleteButton.action = #selector(deleteSelectedTemplate)
        deleteButton.bezelStyle = .rounded

        let buttonBar = NSStackView(views: [NSView(), renameButton, deleteButton])
        buttonBar.orientation = .horizontal
        buttonBar.spacing = 8
        buttonBar.translatesAutoresizingMaskIntoConstraints = false

        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(segmentedControl)
        view.addSubview(scrollView)
        view.addSubview(emptyLabel)
        view.addSubview(buttonBar)

        NSLayoutConstraint.activate([
            segmentedControl.topAnchor.constraint(equalTo: view.topAnchor, constant: 14),
            segmentedControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            segmentedControl.widthAnchor.constraint(equalToConstant: 180),

            scrollView.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            scrollView.bottomAnchor.constraint(equalTo: buttonBar.topAnchor, constant: -12),

            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),

            buttonBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            buttonBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            buttonBar.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -14),
            buttonBar.heightAnchor.constraint(equalToConstant: 30),
        ])

        templatesDidChangeObserver = NotificationCenter.default.addObserver(
            forName: ProfileTemplateStore.templatesDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reload()
        }

        reload()
    }

    deinit {
        if let templatesDidChangeObserver {
            NotificationCenter.default.removeObserver(templatesDidChangeObserver)
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        visibleTemplates.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard visibleTemplates.indices.contains(row) else { return nil }
        let label = NSTextField(labelWithString: visibleTemplates[row].name)
        label.lineBreakMode = .byTruncatingTail
        return label
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateButtonState()
    }

    @objc private func changeTemplateKind() {
        reload()
    }

    @objc private func renameSelectedTemplate() {
        guard let template = selectedTemplate() else { return }
        let alert = NSAlert()
        alert.messageText = "Rename Template"
        alert.informativeText = "Choose a new name for this template."
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        textField.stringValue = template.name
        textField.selectText(nil)
        alert.accessoryView = textField

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        ProfileTemplateStore.shared.renameTemplate(id: template.id, to: textField.stringValue)
    }

    @objc private func deleteSelectedTemplate() {
        guard let template = selectedTemplate() else { return }
        ProfileTemplateStore.shared.deleteTemplate(id: template.id)
    }

    private func selectedTemplate() -> ProfileTemplate? {
        let row = tableView.selectedRow
        guard visibleTemplates.indices.contains(row) else {
            return nil
        }

        return visibleTemplates[row]
    }

    private func reload() {
        tableView.reloadData()
        tableView.deselectAll(nil)
        emptyLabel.isHidden = !visibleTemplates.isEmpty
        updateButtonState()
    }

    private func updateButtonState() {
        let hasSelection = selectedTemplate() != nil
        renameButton.isEnabled = hasSelection
        deleteButton.isEnabled = hasSelection
    }
}
