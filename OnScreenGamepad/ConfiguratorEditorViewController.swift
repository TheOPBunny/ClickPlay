import Cocoa

final class ConfiguratorViewController: NSSplitViewController {

    private enum Metrics {
        static let minimumSidebarWidth: CGFloat = 72
        static let defaultSidebarWidth: CGFloat = 280
        static let maximumSidebarWidth: CGFloat = 900
    }

    private enum DefaultsKey {
        static let sidebarExpandedWidth = "Configurator.sidebarExpandedWidth"
        static let sidebarCollapsed = "Configurator.sidebarCollapsed"
    }

    private let profileListViewController = ProfileListViewController()
    private let editorViewController = ButtonEditorViewController()
    private var sidebarItem: NSSplitViewItem?
    private var profilesDidChangeObserver: NSObjectProtocol?
    private var shouldSkipNextEditorRefresh = false
    private var isSidebarCollapsed = false
    private var lastExpandedSidebarWidth = Metrics.defaultSidebarWidth
    private var hasRestoredSidebarLayout = false

    override func viewDidLoad() {
        super.viewDidLoad()
        loadSidebarDefaults()

        splitView.isVertical = true
        splitView.dividerStyle = .thin

        let sidebarItem = NSSplitViewItem(viewController: profileListViewController)
        sidebarItem.minimumThickness = Metrics.minimumSidebarWidth
        sidebarItem.maximumThickness = Metrics.maximumSidebarWidth
        sidebarItem.canCollapse = true
        sidebarItem.preferredThicknessFraction = 0.25
        sidebarItem.holdingPriority = .defaultLow
        self.sidebarItem = sidebarItem

        let editorItem = NSSplitViewItem(viewController: editorViewController)
        editorItem.holdingPriority = .defaultHigh

        addSplitViewItem(sidebarItem)
        addSplitViewItem(editorItem)

        editorViewController.onToggleSidebar = { [weak self] in
            self?.toggleSidebar()
        }
        editorViewController.onSavePanelLayout = { [weak self] in
            self?.savePanelLayout()
        }

        profileListViewController.onProfileSelected = { [weak self] profile in
            self?.editorViewController.load(profile: profile)
        }

        editorViewController.onProfileSaved = { [weak self] profile in
            self?.shouldSkipNextEditorRefresh = true
            ProfileStore.shared.upsert(profile)
        }

        profilesDidChangeObserver = NotificationCenter.default.addObserver(
            forName: ProfileStore.profilesDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else {
                return
            }

            self.profileListViewController.reload()

            if self.shouldSkipNextEditorRefresh {
                self.shouldSkipNextEditorRefresh = false
                return
            }

            self.editorViewController.refreshFromStoreIfNeeded()
        }

        editorViewController.load(profile: ProfileStore.shared.activeProfile)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        if !hasRestoredSidebarLayout {
            restoreSidebarLayoutIfNeeded()
            return
        }

        syncSidebarStateFromCurrentWidth()
    }

    deinit {
        if let profilesDidChangeObserver {
            NotificationCenter.default.removeObserver(profilesDidChangeObserver)
        }
    }

    func savePanelLayout() {
        syncSidebarStateFromCurrentWidth()
        saveSidebarDefaults()
        editorViewController.savePanelLayout()
    }

    private func toggleSidebar() {
        guard splitView.arrangedSubviews.count > 1 else {
            return
        }

        if isSidebarCollapsed {
            isSidebarCollapsed = false
            sidebarItem?.isCollapsed = false
            setSidebarWidth(lastExpandedSidebarWidth)
        } else {
            let currentWidth = splitView.arrangedSubviews[0].frame.width
            if currentWidth >= Metrics.minimumSidebarWidth {
                updateLastExpandedSidebarWidth(currentWidth)
            }

            isSidebarCollapsed = true
            sidebarItem?.isCollapsed = true
        }

        saveSidebarDefaults()
    }

    private func setSidebarWidth(_ width: CGFloat) {
        let clampedWidth = min(max(width, Metrics.minimumSidebarWidth), Metrics.maximumSidebarWidth)
        sidebarItem?.minimumThickness = Metrics.minimumSidebarWidth
        sidebarItem?.maximumThickness = Metrics.maximumSidebarWidth
        splitView.setPosition(clampedWidth, ofDividerAt: 0)
        splitView.layoutSubtreeIfNeeded()
    }

    private func syncSidebarStateFromCurrentWidth() {
        guard splitView.arrangedSubviews.count > 1 else {
            return
        }

        if sidebarItem?.isCollapsed == true {
            isSidebarCollapsed = true
            return
        }

        let currentWidth = splitView.arrangedSubviews[0].frame.width
        isSidebarCollapsed = false
        if currentWidth > 0 && currentWidth < Metrics.minimumSidebarWidth {
            setSidebarWidth(Metrics.minimumSidebarWidth)
        } else if currentWidth >= Metrics.minimumSidebarWidth {
            updateLastExpandedSidebarWidth(currentWidth)
            saveSidebarDefaults()
        }
    }

    private func restoreSidebarLayoutIfNeeded() {
        guard splitView.arrangedSubviews.count > 1, splitView.bounds.width > 0 else {
            return
        }

        hasRestoredSidebarLayout = true
        sidebarItem?.isCollapsed = isSidebarCollapsed
        if !isSidebarCollapsed {
            setSidebarWidth(lastExpandedSidebarWidth)
        }
    }

    private func updateLastExpandedSidebarWidth(_ width: CGFloat) {
        lastExpandedSidebarWidth = min(max(width, Metrics.minimumSidebarWidth), Metrics.maximumSidebarWidth)
    }

    private func loadSidebarDefaults() {
        let defaults = UserDefaults.standard
        isSidebarCollapsed = defaults.bool(forKey: DefaultsKey.sidebarCollapsed)

        let savedWidth = defaults.double(forKey: DefaultsKey.sidebarExpandedWidth)
        if savedWidth > 0 {
            updateLastExpandedSidebarWidth(savedWidth)
        }
    }

    private func saveSidebarDefaults() {
        let defaults = UserDefaults.standard
        defaults.set(isSidebarCollapsed, forKey: DefaultsKey.sidebarCollapsed)
        defaults.set(Double(lastExpandedSidebarWidth), forKey: DefaultsKey.sidebarExpandedWidth)
    }
}
