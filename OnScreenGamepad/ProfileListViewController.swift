import Cocoa

final class ProfileListViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {

    var onProfileSelected: ((Profile) -> Void)?

    private let tableView = NSTableView()
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

        tableView.addTableColumn(nameColumn)
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 28
        tableView.usesAlternatingRowBackgroundColors = true

        scrollView.documentView = tableView
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
        bar.addArrangedSubview(makeButton(title: "⎘", action: #selector(duplicateProfile)))
        bar.addArrangedSubview(makeButton(title: "−", action: #selector(deleteProfile)))
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

    @objc private func showAddProfileMenu(_ sender: NSButton) {
        let menu = NSMenu()

        let templateItem = NSMenuItem(title: "New from Template", action: #selector(addProfileFromTemplate), keyEquivalent: "")
        templateItem.target = self
        menu.addItem(templateItem)

        let blankItem = NSMenuItem(title: "New Blank", action: #selector(addBlankProfile), keyEquivalent: "")
        blankItem.target = self
        menu.addItem(blankItem)

        menu.popUp(positioning: nil, at: CGPoint(x: 0, y: sender.bounds.maxY + 2), in: sender)
    }

    @objc private func addProfileFromTemplate() {
        let profile = Profile.makeStarterTemplate(name: "Profile \(profiles.count + 1)")
        add(profile: profile)
    }

    @objc private func addBlankProfile() {
        let profile = Profile.makeBlank(name: "Profile \(profiles.count + 1)")
        add(profile: profile)
    }

    private func add(profile: Profile) {
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
