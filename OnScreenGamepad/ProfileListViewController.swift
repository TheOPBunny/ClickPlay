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

        let templateProfileItem = NSMenuItem(title: "New Profile from Template", action: #selector(addProfileFromTemplate), keyEquivalent: "")
        templateProfileItem.target = self
        menu.addItem(templateProfileItem)

        let blankProfileItem = NSMenuItem(title: "New Blank Profile", action: #selector(addBlankProfile), keyEquivalent: "")
        blankProfileItem.target = self
        menu.addItem(blankProfileItem)

        menu.addItem(NSMenuItem.separator())

        let templateLayerItem = NSMenuItem(title: "New Layer from Template", action: #selector(addSubProfileFromTemplate), keyEquivalent: "")
        templateLayerItem.target = self
        templateLayerItem.isEnabled = selectedParentID() != nil
        menu.addItem(templateLayerItem)

        let blankLayerItem = NSMenuItem(title: "New Blank Layer", action: #selector(addBlankSubProfile), keyEquivalent: "")
        blankLayerItem.target = self
        blankLayerItem.isEnabled = selectedParentID() != nil
        menu.addItem(blankLayerItem)

        menu.popUp(positioning: nil, at: CGPoint(x: 0, y: sender.bounds.maxY + 2), in: sender)
    }

    @objc private func addProfileFromTemplate() {
        let profile = Profile.makeStarterTemplate(name: "Profile \(profiles.count + 1)").asTopLevelContainer()
        add(profile: profile)
    }

    @objc private func addBlankProfile() {
        let profile = Profile.makeBlank(name: "Profile \(profiles.count + 1)").asTopLevelContainer()
        add(profile: profile)
    }

    @objc private func addSubProfileFromTemplate() {
        addSubProfile(fromTemplate: true)
    }

    @objc private func addBlankSubProfile() {
        addSubProfile(fromTemplate: false)
    }

    private func add(profile: Profile) {
        ProfileStore.shared.upsert(profile)
        ProfileStore.shared.setActive(profile.id)
        onProfileSelected?(ProfileStore.shared.activeResolvedProfile)
    }

    private func addSubProfile(fromTemplate: Bool) {
        guard let parentID = selectedParentID(),
              let subProfile = ProfileStore.shared.addSubProfile(to: parentID, fromTemplate: fromTemplate) else {
            return
        }

        onProfileSelected?(subProfile)
    }

    @objc private func duplicateSelection() {
        guard let item = outlineView.item(atRow: outlineView.selectedRow) as? SidebarItem else {
            return
        }

        if let parentID = item.parentID {
            guard let duplicatedSubProfile = ProfileStore.shared.duplicateSubProfile(item.profileID, in: parentID) else {
                return
            }
            onProfileSelected?(duplicatedSubProfile)
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
