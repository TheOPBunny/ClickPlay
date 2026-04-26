import Cocoa

final class ConfiguratorViewController: NSSplitViewController {

    private enum Metrics {
        static let collapsedSidebarWidth: CGFloat = 44
        static let minimumSidebarWidth: CGFloat = 140
        static let defaultSidebarWidth: CGFloat = 240
        static let maximumSidebarWidth: CGFloat = 640
    }

    private enum DefaultsKey {
        static let sidebarExpandedWidth = "Configurator.sidebarExpandedWidth"
        static let sidebarCollapsed = "Configurator.sidebarCollapsed"
    }

    private let profileListViewController = ProfileListViewController()
    private let editorViewController = ButtonEditorViewController()
    private var profilesDidChangeObserver: NSObjectProtocol?
    private var shouldSkipNextEditorRefresh = false
    private var isSidebarCollapsed = false
    private var lastExpandedSidebarWidth = Metrics.defaultSidebarWidth
    private var hasRestoredSidebarLayout = false

    override func viewDidLoad() {
        super.viewDidLoad()
        loadSidebarDefaults()

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: profileListViewController)
        sidebarItem.minimumThickness = Metrics.collapsedSidebarWidth
        sidebarItem.maximumThickness = Metrics.maximumSidebarWidth
        sidebarItem.canCollapse = false
        sidebarItem.preferredThicknessFraction = 0.22

        addSplitViewItem(sidebarItem)
        addSplitViewItem(NSSplitViewItem(viewController: editorViewController))
        splitView.autosaveName = "ConfiguratorSplitView"

        editorViewController.onToggleSidebar = { [weak self] in
            self?.toggleSidebar()
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

    private func toggleSidebar() {
        guard splitView.arrangedSubviews.count > 1 else {
            return
        }

        let currentWidth = splitView.arrangedSubviews[0].frame.width
        if isSidebarCollapsed {
            isSidebarCollapsed = false
            profileListViewController.setCollapsed(false)
            setSidebarWidth(lastExpandedSidebarWidth)
        } else {
            if currentWidth > Metrics.collapsedSidebarWidth + 1 {
                updateLastExpandedSidebarWidth(currentWidth)
            }

            isSidebarCollapsed = true
            profileListViewController.setCollapsed(true)
            setSidebarWidth(Metrics.collapsedSidebarWidth)
        }

        saveSidebarDefaults()
    }

    private func setSidebarWidth(_ width: CGFloat) {
        splitView.setPosition(width, ofDividerAt: 0)
        splitView.layoutSubtreeIfNeeded()
    }

    private func syncSidebarStateFromCurrentWidth() {
        guard splitView.arrangedSubviews.count > 1 else {
            return
        }

        let currentWidth = splitView.arrangedSubviews[0].frame.width
        if isSidebarCollapsed {
            if currentWidth > Metrics.collapsedSidebarWidth + 24 {
                isSidebarCollapsed = false
                profileListViewController.setCollapsed(false)
                updateLastExpandedSidebarWidth(currentWidth)
                saveSidebarDefaults()
            }
        } else if currentWidth > Metrics.collapsedSidebarWidth + 1 && currentWidth < Metrics.minimumSidebarWidth {
            setSidebarWidth(Metrics.minimumSidebarWidth)
        } else if currentWidth > Metrics.collapsedSidebarWidth + 1 {
            updateLastExpandedSidebarWidth(currentWidth)
            saveSidebarDefaults()
        } else {
            isSidebarCollapsed = true
            profileListViewController.setCollapsed(true)
            saveSidebarDefaults()
        }
    }

    private func restoreSidebarLayoutIfNeeded() {
        guard splitView.arrangedSubviews.count > 1, splitView.bounds.width > 0 else {
            return
        }

        hasRestoredSidebarLayout = true
        profileListViewController.setCollapsed(isSidebarCollapsed)
        setSidebarWidth(isSidebarCollapsed ? Metrics.collapsedSidebarWidth : lastExpandedSidebarWidth)
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
