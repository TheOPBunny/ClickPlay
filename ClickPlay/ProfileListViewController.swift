import Cocoa

/// Sidebar controller for top-level profiles and nested layers, including rename, drag/drop, templates, and undo.
final class ProfileListViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate, NSMenuItemValidation, NSTextFieldDelegate {

    var onProfileSelected: ((Profile) -> Void)?
    var onProfileSelectionRequested: (() -> Bool)?
    private typealias SidebarClipboard = (profile: Profile, isLayer: Bool)

    // NSOutlineView compares object identity, so SidebarItem supplies stable equality for profile/layer rows.
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

        override var hash: Int {
            var hasher = Hasher()
            hasher.combine(profileID)
            hasher.combine(parentID)
            return hasher.finalize()
        }

        override func isEqual(_ object: Any?) -> Bool {
            guard let other = object as? SidebarItem else {
                return false
            }

            return profileID == other.profileID && parentID == other.parentID
        }
    }

    private struct ProfileDeleteUndoContext {
        var profile: Profile
        var index: Int
        var activeProfileID: UUID
    }

    private struct LayerDeleteUndoContext {
        var layer: Profile
        var parentID: UUID
        var index: Int
        var activeProfileID: UUID
        var activeSubProfileID: UUID?
    }

    private let outlineView = NSOutlineView()
    private let scrollView = NSScrollView()
    private let titleLabel = NSTextField(labelWithString: "Profiles")
    private let dropIndicatorView = NSView()
    private let sidebarUndoManager = UndoManager()
    private var isReloadingSelection = false
    private var localClipboard: SidebarClipboard?
    private var templateManagerWindowController: NSWindowController?
    private var lastSelectionChangeTime = Date.distantPast
    private let renameAfterSelectionDelay: TimeInterval = 0.65
    private let sidebarDragType = NSPasteboard.PasteboardType("com.clickplay.sidebar-profile-item")

    // The sidebar always mirrors ProfileStore; mutations go through the store so the gamepad reloads consistently.
    private var profiles: [Profile] {
        ProfileStore.shared.profiles
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 400))
    }

    override var undoManager: UndoManager? {
        sidebarUndoManager
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let nameColumn = NSTableColumn(identifier: .init("name"))
        nameColumn.title = "Profiles"
        nameColumn.isEditable = true

        outlineView.addTableColumn(nameColumn)
        outlineView.outlineTableColumn = nameColumn
        outlineView.headerView = nil
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.target = self
        outlineView.action = #selector(outlineClicked(_:))
        outlineView.rowHeight = 28
        outlineView.usesAlternatingRowBackgroundColors = true
        outlineView.registerForDraggedTypes([sidebarDragType])
        outlineView.setDraggingSourceOperationMask(.move, forLocal: true)
        configureDropIndicator()
        let contextMenu = NSMenu()
        contextMenu.delegate = self
        outlineView.menu = contextMenu

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

        view.addSubview(header)
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 32),
            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        reload()
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
        let identifier = NSUserInterfaceItemIdentifier("ProfileNameCell")
        let cell = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? NSTableCellView()
        cell.identifier = identifier

        let textField: NSTextField
        if let existingTextField = cell.textField {
            textField = existingTextField
        } else {
            textField = NSTextField()
            textField.isBordered = false
            textField.drawsBackground = false
            textField.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(textField)
            cell.textField = textField
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }

        textField.stringValue = resolvedName ?? ""
        textField.font = item.isSubProfile ? .systemFont(ofSize: 13) : .boldSystemFont(ofSize: 13)
        textField.lineBreakMode = .byTruncatingTail
        textField.isEditable = true
        textField.delegate = self
        return cell
    }

    func outlineView(_ outlineView: NSOutlineView, setObjectValue object: Any?, for tableColumn: NSTableColumn?, byItem item: Any?) {
        guard let item = item as? SidebarItem,
              let name = object as? String else {
            return
        }

        rename(item, to: name)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let textField = obj.object as? NSTextField else {
            return
        }

        commitRename(from: textField)
    }

    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        guard let item = item as? SidebarItem else {
            return nil
        }

        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(dragPayload(for: item), forType: sidebarDragType)
        return pasteboardItem
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        validateDrop info: NSDraggingInfo,
        proposedItem item: Any?,
        proposedChildIndex index: Int
    ) -> NSDragOperation {
        guard let draggedItem = draggedSidebarItem(from: info.draggingPasteboard) else {
            hideDropIndicator()
            return []
        }

        if draggedItem.isSubProfile {
            guard let target = normalizedLayerDropTarget(
                for: draggedItem,
                proposedItem: item,
                proposedChildIndex: index,
                draggingInfo: info
            ) else {
                hideDropIndicator()
                return []
            }

            outlineView.setDropItem(target.parentItem, dropChildIndex: target.childIndex)
            showDropIndicator(parentItem: target.parentItem, childIndex: target.childIndex)
            return .move
        }

        guard let targetIndex = normalizedProfileDropIndex(
            proposedItem: item,
            proposedChildIndex: index,
            draggingInfo: info
        ) else {
            hideDropIndicator()
            return []
        }

        outlineView.setDropItem(nil, dropChildIndex: targetIndex)
        showDropIndicator(parentItem: nil, childIndex: targetIndex)
        return .move
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        acceptDrop info: NSDraggingInfo,
        item: Any?,
        childIndex index: Int
    ) -> Bool {
        hideDropIndicator()

        guard let draggedItem = draggedSidebarItem(from: info.draggingPasteboard) else {
            return false
        }

        if draggedItem.isSubProfile {
            guard let target = normalizedLayerDropTarget(
                for: draggedItem,
                proposedItem: item,
                proposedChildIndex: index,
                draggingInfo: info
            ),
                  ProfileStore.shared.moveSubProfile(
                    draggedItem.profileID,
                    in: target.parentItem.profileID,
                    to: target.childIndex
                  ) else {
                return false
            }

            onProfileSelected?(ProfileStore.shared.activeResolvedProfile)
            return true
        }

        guard let targetIndex = normalizedProfileDropIndex(
            proposedItem: item,
            proposedChildIndex: index,
            draggingInfo: info
        ),
              ProfileStore.shared.moveProfile(draggedItem.profileID, to: targetIndex) else {
            return false
        }

        onProfileSelected?(ProfileStore.shared.activeResolvedProfile)
        return true
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        draggingSession session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        hideDropIndicator()
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        if isReloadingSelection {
            return
        }

        guard let item = outlineView.item(atRow: outlineView.selectedRow) as? SidebarItem else {
            return
        }

        lastSelectionChangeTime = Date()

        guard onProfileSelectionRequested?() ?? true else {
            restoreActiveSelection()
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

    @objc func addBlankProfile() {
        let profile = Profile.makeBlank(name: "Profile \(profiles.count + 1)").asTopLevelContainer()
        add(profile: profile)
    }

    @objc func addBlankSubProfile() {
        addSubProfile(fromTemplate: false)
    }

    @objc func addDefaultTemplateProfile() {
        let profile = Profile.makeStarterTemplate(name: "Profile \(profiles.count + 1)").asTopLevelContainer()
        add(profile: profile)
    }

    @objc func addDefaultTemplateSubProfile() {
        addSubProfile(fromTemplate: true)
    }

    func addProfileFromTemplate(id templateID: UUID) {
        let existingNames = Set(profiles.map(\.name))
        let baseName = ProfileTemplateStore.shared.templates(kind: .profile)
            .first { $0.id == templateID }?.name ?? "Profile"
        let name = uniqueName(baseName, existingNames: existingNames)
        guard let profile = ProfileTemplateStore.shared.makeProfile(fromTemplateID: templateID, name: name) else {
            return
        }
        add(profile: profile)
    }

    func addSubProfileFromTemplate(id templateID: UUID) {
        guard let parentID = selectedParentID(),
              let parentProfile = profile(with: parentID) else { return }
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

    @objc func saveCurrentAsTemplate() {
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

    @objc func showTemplateManager() {
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

    @objc func duplicateSelection() {
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

    @objc func deleteSelection() {
        guard let item = outlineView.item(atRow: outlineView.selectedRow) as? SidebarItem,
              canDeleteSelection,
              let selectedProfile = profile(for: item),
              confirmDelete(profile: selectedProfile, isLayer: item.isSubProfile) else {
            return
        }

        if let parentID = item.parentID {
            guard let parentProfile = profile(with: parentID),
                  let index = parentProfile.subProfiles.firstIndex(where: { $0.id == item.profileID }) else {
                return
            }
            let undoContext = LayerDeleteUndoContext(
                layer: selectedProfile,
                parentID: parentID,
                index: index,
                activeProfileID: ProfileStore.shared.activeProfileID,
                activeSubProfileID: parentProfile.activeSubProfileID
            )
            ProfileStore.shared.deleteSubProfile(item.profileID, in: parentID)
            registerLayerDeleteUndo(undoContext)
            onProfileSelected?(ProfileStore.shared.activeResolvedProfile)
            return
        }

        guard let index = profiles.firstIndex(where: { $0.id == item.profileID }) else {
            return
        }
        let undoContext = ProfileDeleteUndoContext(
            profile: selectedProfile,
            index: index,
            activeProfileID: ProfileStore.shared.activeProfileID
        )
        ProfileStore.shared.delete(item.profileID)
        registerProfileDeleteUndo(undoContext)
        onProfileSelected?(ProfileStore.shared.activeResolvedProfile)
    }

    @objc func cut(_ sender: Any?) {
        guard copySelectionToLocalClipboard() else {
            return
        }

        deleteSelection()
    }

    @objc func copy(_ sender: Any?) {
        _ = copySelectionToLocalClipboard()
    }

    @objc func paste(_ sender: Any?) {
        guard let localClipboard else {
            return
        }

        if localClipboard.isLayer {
            guard let parentID = selectedParentID() else {
                return
            }

            var layer = localClipboard.profile.copyWithNewIDs()
            layer.subProfiles = []
            layer.activeSubProfileID = nil
            _ = ProfileStore.shared.addSubProfile(layer, to: parentID)
            onProfileSelected?(ProfileStore.shared.activeResolvedProfile)
            return
        }

        let profile = localClipboard.profile.copyWithNewIDs().asTopLevelContainer()
        add(profile: profile)
    }

    @objc func delete(_ sender: Any?) {
        deleteSelection()
    }

    @objc func rename(_ sender: Any?) {
        beginRenameSelected()
    }

    @objc func undo(_ sender: Any?) {
        sidebarUndoManager.undo()
    }

    @objc func redo(_ sender: Any?) {
        sidebarUndoManager.redo()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(undo(_:)):
            menuItem.title = sidebarUndoManager.undoMenuItemTitle
            return sidebarUndoManager.canUndo
        case #selector(redo(_:)):
            menuItem.title = sidebarUndoManager.redoMenuItemTitle
            return sidebarUndoManager.canRedo
        case #selector(cut(_:)), #selector(delete(_:)):
            return canDeleteSelection
        case #selector(copy(_:)):
            return selectedSidebarItem() != nil
        case #selector(paste(_:)):
            return localClipboard != nil
        default:
            return true
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if outlineView.clickedRow >= 0 {
            outlineView.selectRowIndexes(IndexSet(integer: outlineView.clickedRow), byExtendingSelection: false)
        }

        menu.removeAllItems()
        addContextItem("Cut", action: #selector(cut(_:)), to: menu, enabled: canDeleteSelection)
        addContextItem("Copy", action: #selector(copy(_:)), to: menu, enabled: selectedSidebarItem() != nil)
        addContextItem("Paste", action: #selector(paste(_:)), to: menu, enabled: localClipboard != nil)
        menu.addItem(NSMenuItem.separator())
        addContextItem("Duplicate", action: #selector(duplicateSelection), to: menu, enabled: selectedSidebarItem() != nil)
        addContextItem("Delete", action: #selector(deleteSelection), to: menu, enabled: canDeleteSelection)
        menu.addItem(NSMenuItem.separator())
        addContextItem("Rename", action: #selector(rename(_:)), to: menu, enabled: selectedSidebarItem() != nil)
    }

    func deleteSelectedProfile() {
        guard let item = selectedSidebarItem(), !item.isSubProfile else {
            return
        }

        deleteSelection()
    }

    func deleteSelectedLayer() {
        guard let item = selectedSidebarItem(), item.isSubProfile else {
            return
        }

        deleteSelection()
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

    private func restoreActiveSelection() {
        isReloadingSelection = true
        selectActiveSubProfile()
        isReloadingSelection = false
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

    private var canDeleteSelection: Bool {
        guard let item = selectedSidebarItem() else {
            return false
        }

        if item.isSubProfile, let parentID = item.parentID {
            return (profile(with: parentID)?.subProfiles.count ?? 0) > 1
        }

        return profiles.count > 1
    }

    private func addContextItem(_ title: String, action: Selector, to menu: NSMenu, enabled: Bool) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.isEnabled = enabled
        menu.addItem(item)
    }

    private func copySelectionToLocalClipboard() -> Bool {
        guard let item = selectedSidebarItem(),
              let profile = profile(for: item) else {
            return false
        }

        localClipboard = (profile, item.isSubProfile)
        return true
    }

    private func beginRenameSelected() {
        let selectedRow = outlineView.selectedRow
        guard selectedRow >= 0 else {
            return
        }

        outlineView.editColumn(0, row: selectedRow, with: nil, select: true)
    }

    private func commitRename(from textField: NSTextField) {
        let row = outlineView.row(for: textField)
        guard row >= 0,
              let item = outlineView.item(atRow: row) as? SidebarItem else {
            return
        }

        rename(item, to: textField.stringValue)
    }

    private func rename(_ item: SidebarItem, to name: String) {
        if let parentID = item.parentID {
            ProfileStore.shared.renameSubProfile(item.profileID, in: parentID, to: name)
            return
        }

        ProfileStore.shared.rename(item.profileID, to: name)
    }

    @objc private func outlineClicked(_ sender: NSOutlineView) {
        guard sender.clickedRow >= 0,
              sender.clickedColumn >= 0,
              sender.window?.currentEvent?.clickCount == 1,
              sender.clickedRow == sender.selectedRow,
              clickedNameCellContainsCurrentEvent(row: sender.clickedRow),
              Date().timeIntervalSince(lastSelectionChangeTime) >= renameAfterSelectionDelay else {
            return
        }

        beginRenameSelected()
    }

    private func clickedNameCellContainsCurrentEvent(row: Int) -> Bool {
        guard let event = outlineView.window?.currentEvent else {
            return false
        }

        let eventPoint = outlineView.convert(event.locationInWindow, from: nil)
        return outlineView.frameOfCell(atColumn: 0, row: row).contains(eventPoint)
    }

    private func configureDropIndicator() {
        dropIndicatorView.wantsLayer = true
        dropIndicatorView.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        dropIndicatorView.layer?.cornerRadius = 1.5
        dropIndicatorView.isHidden = true
        dropIndicatorView.autoresizingMask = [.width]
        outlineView.addSubview(dropIndicatorView)
    }

    private func normalizedProfileDropIndex(
        proposedItem item: Any?,
        proposedChildIndex index: Int,
        draggingInfo: NSDraggingInfo
    ) -> Int? {
        closestProfileDropIndex(to: outlineDropY(for: draggingInfo))
    }

    private func normalizedLayerDropTarget(
        for draggedItem: SidebarItem,
        proposedItem item: Any?,
        proposedChildIndex index: Int,
        draggingInfo: NSDraggingInfo
    ) -> (parentItem: SidebarItem, childIndex: Int)? {
        guard let parentID = draggedItem.parentID,
              let parentProfile = profile(with: parentID) else {
            return nil
        }

        guard let childIndex = closestLayerDropIndex(
            in: parentProfile,
            to: outlineDropY(for: draggingInfo)
        ) else {
            return nil
        }

        let parentItem = visibleSidebarItem(profileID: parentID, parentID: nil)
            ?? SidebarItem(profileID: parentID, parentID: nil)
        return (parentItem, childIndex)
    }

    private func outlineDropY(for draggingInfo: NSDraggingInfo) -> CGFloat {
        let dropPoint = outlineView.convert(draggingInfo.draggingLocation, from: nil)
        return dropPoint.y
    }

    private func closestProfileDropIndex(to y: CGFloat) -> Int? {
        var candidates: [(index: Int, y: CGFloat)] = []

        for (index, profile) in profiles.enumerated() {
            let rowItem = SidebarItem(profileID: profile.id, parentID: nil)
            if let edgeY = rowEdgeY(for: rowItem, edge: .before) {
                candidates.append((index, edgeY))
            }
        }

        if let lastProfile = profiles.last,
           let lastRow = lastVisibleDescendantRow(of: lastProfile.id) {
            candidates.append((profiles.count, rowEdgeY(forRow: lastRow, edge: .after)))
        }

        return closestCandidate(to: y, candidates: candidates)
    }

    private func closestLayerDropIndex(in parentProfile: Profile, to y: CGFloat) -> Int? {
        var candidates: [(index: Int, y: CGFloat)] = []

        for (index, subProfile) in parentProfile.subProfiles.enumerated() {
            let rowItem = SidebarItem(profileID: subProfile.id, parentID: parentProfile.id)
            if let edgeY = rowEdgeY(for: rowItem, edge: .before) {
                candidates.append((index, edgeY))
            }
        }

        if let lastSubProfile = parentProfile.subProfiles.last {
            let rowItem = SidebarItem(profileID: lastSubProfile.id, parentID: parentProfile.id)
            if let edgeY = rowEdgeY(for: rowItem, edge: .after) {
                candidates.append((parentProfile.subProfiles.count, edgeY))
            }
        }

        return closestCandidate(to: y, candidates: candidates)
    }

    private func closestCandidate(to y: CGFloat, candidates: [(index: Int, y: CGFloat)]) -> Int? {
        candidates.min { left, right in
            abs(left.y - y) < abs(right.y - y)
        }?.index
    }

    private func showDropIndicator(parentItem: SidebarItem?, childIndex: Int) {
        guard let y = dropIndicatorY(parentItem: parentItem, childIndex: childIndex) else {
            hideDropIndicator()
            return
        }

        let height = 3.0
        let inset = 6.0
        dropIndicatorView.frame = NSRect(
            x: inset,
            y: y - (height / 2),
            width: max(outlineView.bounds.width - (inset * 2), 0),
            height: height
        )
        dropIndicatorView.isHidden = false
        outlineView.addSubview(dropIndicatorView, positioned: .above, relativeTo: nil)
    }

    private func hideDropIndicator() {
        dropIndicatorView.isHidden = true
    }

    private func dropIndicatorY(parentItem: SidebarItem?, childIndex: Int) -> CGFloat? {
        if let parentItem {
            guard let parentProfile = profile(with: parentItem.profileID),
                  !parentProfile.subProfiles.isEmpty else {
                return nil
            }

            if childIndex < parentProfile.subProfiles.count {
                let rowItem = SidebarItem(profileID: parentProfile.subProfiles[childIndex].id, parentID: parentProfile.id)
                return rowEdgeY(for: rowItem, edge: .before)
            }

            guard let lastSubProfile = parentProfile.subProfiles.last else {
                return nil
            }

            let rowItem = SidebarItem(profileID: lastSubProfile.id, parentID: parentProfile.id)
            return rowEdgeY(for: rowItem, edge: .after)
        }

        guard !profiles.isEmpty else {
            return nil
        }

        if childIndex < profiles.count {
            let rowItem = SidebarItem(profileID: profiles[childIndex].id, parentID: nil)
            return rowEdgeY(for: rowItem, edge: .before)
        }

        guard let lastRow = lastVisibleDescendantRow(of: profiles[profiles.count - 1].id) else {
            return nil
        }

        return rowEdgeY(forRow: lastRow, edge: .after)
    }

    private enum DropIndicatorEdge {
        case before
        case after
    }

    private func rowEdgeY(for item: SidebarItem, edge: DropIndicatorEdge) -> CGFloat? {
        let row = row(for: item)
        guard row >= 0 else {
            return nil
        }

        return rowEdgeY(forRow: row, edge: edge)
    }

    private func rowEdgeY(forRow row: Int, edge: DropIndicatorEdge) -> CGFloat {
        let rowFrame = outlineView.rect(ofRow: row)
        switch (outlineView.isFlipped, edge) {
        case (true, .before), (false, .after):
            return rowFrame.minY
        case (true, .after), (false, .before):
            return rowFrame.maxY
        }
    }

    private func row(for sidebarItem: SidebarItem) -> Int {
        for row in 0..<outlineView.numberOfRows {
            guard let item = outlineView.item(atRow: row) as? SidebarItem,
                  item.profileID == sidebarItem.profileID,
                  item.parentID == sidebarItem.parentID else {
                continue
            }

            return row
        }

        return -1
    }

    private func visibleSidebarItem(profileID: UUID, parentID: UUID?) -> SidebarItem? {
        for row in 0..<outlineView.numberOfRows {
            guard let item = outlineView.item(atRow: row) as? SidebarItem,
                  item.profileID == profileID,
                  item.parentID == parentID else {
                continue
            }

            return item
        }

        return nil
    }

    private func lastVisibleDescendantRow(of profileID: UUID) -> Int? {
        var lastRow: Int?

        for row in 0..<outlineView.numberOfRows {
            guard let item = outlineView.item(atRow: row) as? SidebarItem else {
                continue
            }

            if item.profileID == profileID || item.parentID == profileID {
                lastRow = row
            }
        }

        return lastRow
    }

    private func dragPayload(for item: SidebarItem) -> String {
        [
            item.profileID.uuidString,
            item.parentID?.uuidString ?? "",
        ].joined(separator: "|")
    }

    private func draggedSidebarItem(from pasteboard: NSPasteboard) -> SidebarItem? {
        guard let payload = pasteboard.string(forType: sidebarDragType) else {
            return nil
        }

        let components = payload.split(separator: "|", omittingEmptySubsequences: false)
        guard components.count == 2,
              let profileID = UUID(uuidString: String(components[0])) else {
            return nil
        }

        let parentID = components[1].isEmpty ? nil : UUID(uuidString: String(components[1]))
        return SidebarItem(profileID: profileID, parentID: parentID)
    }

    private func profile(for item: SidebarItem) -> Profile? {
        if let parentID = item.parentID {
            return subProfile(with: item.profileID, parentID: parentID)
        }

        return profile(with: item.profileID)
    }

    private func confirmDelete(profile: Profile, isLayer: Bool) -> Bool {
        let itemKind = isLayer ? "Layer" : "Profile"
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Delete \(itemKind)?"
        alert.informativeText = "\"\(profile.name)\" will be removed. You can undo this from the Edit menu."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func registerProfileDeleteUndo(_ context: ProfileDeleteUndoContext) {
        sidebarUndoManager.registerUndo(withTarget: self) { target in
            target.restoreDeletedProfile(context)
        }
        sidebarUndoManager.setActionName("Delete Profile")
    }

    private func restoreDeletedProfile(_ context: ProfileDeleteUndoContext) {
        ProfileStore.shared.restoreProfile(
            context.profile,
            at: context.index,
            activeProfileID: context.activeProfileID
        )
        onProfileSelected?(ProfileStore.shared.activeResolvedProfile)
        sidebarUndoManager.registerUndo(withTarget: self) { target in
            target.redoProfileDelete(context)
        }
        sidebarUndoManager.setActionName("Delete Profile")
    }

    private func redoProfileDelete(_ context: ProfileDeleteUndoContext) {
        ProfileStore.shared.delete(context.profile.id)
        onProfileSelected?(ProfileStore.shared.activeResolvedProfile)
        registerProfileDeleteUndo(context)
    }

    private func registerLayerDeleteUndo(_ context: LayerDeleteUndoContext) {
        sidebarUndoManager.registerUndo(withTarget: self) { target in
            target.restoreDeletedLayer(context)
        }
        sidebarUndoManager.setActionName("Delete Layer")
    }

    private func restoreDeletedLayer(_ context: LayerDeleteUndoContext) {
        ProfileStore.shared.restoreSubProfile(
            context.layer,
            in: context.parentID,
            at: context.index,
            activeProfileID: context.activeProfileID,
            activeSubProfileID: context.activeSubProfileID
        )
        onProfileSelected?(ProfileStore.shared.activeResolvedProfile)
        sidebarUndoManager.registerUndo(withTarget: self) { target in
            target.redoLayerDelete(context)
        }
        sidebarUndoManager.setActionName("Delete Layer")
    }

    private func redoLayerDelete(_ context: LayerDeleteUndoContext) {
        ProfileStore.shared.deleteSubProfile(context.layer.id, in: context.parentID)
        onProfileSelected?(ProfileStore.shared.activeResolvedProfile)
        registerLayerDeleteUndo(context)
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

/// Modal controller for renaming and deleting saved profile/layer/group templates.
private final class TemplateManagerViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {

    private let segmentedControl = NSSegmentedControl(labels: ["Profiles", "Layers", "Groups"], trackingMode: .selectOne, target: nil, action: nil)
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let renameButton = NSButton(title: "Rename", target: nil, action: nil)
    private let deleteButton = NSButton(title: "Delete", target: nil, action: nil)
    private let emptyLabel = NSTextField(labelWithString: "No saved templates")
    private var templatesDidChangeObserver: NSObjectProtocol?

    private var selectedKind: ProfileTemplateKind {
        switch segmentedControl.selectedSegment {
        case 1:
            return .layer
        case 2:
            return .group
        default:
            return .profile
        }
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
            segmentedControl.widthAnchor.constraint(equalToConstant: 240),

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
