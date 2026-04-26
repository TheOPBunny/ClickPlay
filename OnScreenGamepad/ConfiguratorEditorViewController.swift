import Cocoa

final class ConfiguratorViewController: NSViewController, NSSplitViewDelegate {

    private enum Metrics {
        static let minimumSidebarWidth: CGFloat = 160
        static let defaultSidebarWidth: CGFloat = 280
        static let maximumSidebarWidth: CGFloat = 900
        static let minimumEditorWidth: CGFloat = 420
    }

    private enum DefaultsKey {
        static let sidebarExpandedWidth = "Configurator.sidebarExpandedWidth"
        static let sidebarCollapsed = "Configurator.sidebarCollapsed"
    }

    private let profileListViewController = ProfileListViewController()
    private let editorViewController = ButtonEditorViewController()
    private let splitView = NSSplitView()
    private var profilesDidChangeObserver: NSObjectProtocol?
    private var shouldSkipNextEditorRefresh = false
    private var isSidebarCollapsed = false
    private var lastExpandedSidebarWidth = Metrics.defaultSidebarWidth
    private var hasRestoredSidebarLayout = false
    private var lastKnownSplitViewWidth: CGFloat = 0

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 980, height: 700))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        loadSidebarDefaults()

        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.delegate = self
        splitView.translatesAutoresizingMaskIntoConstraints = false

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

        addChild(profileListViewController)
        addChild(editorViewController)
        splitView.addArrangedSubview(profileListViewController.view)
        splitView.addArrangedSubview(editorViewController.view)
        splitView.setHoldingPriority(.defaultLow, forSubviewAt: 0)
        splitView.setHoldingPriority(.defaultHigh, forSubviewAt: 1)

        view.addSubview(splitView)
        NSLayoutConstraint.activate([
            splitView.topAnchor.constraint(equalTo: view.topAnchor),
            splitView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            splitView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

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

        lastKnownSplitViewWidth = splitView.bounds.width
    }

    deinit {
        if let profilesDidChangeObserver {
            NotificationCenter.default.removeObserver(profilesDidChangeObserver)
        }
    }

    func savePanelLayout() {
        if hasRestoredSidebarLayout {
            syncSidebarStateFromCurrentWidth()
        }
        saveSidebarDefaults()
        editorViewController.savePanelLayout()
    }

    private func toggleSidebar() {
        guard splitView.arrangedSubviews.count > 1 else {
            return
        }

        if isSidebarCollapsed {
            isSidebarCollapsed = false
            profileListViewController.view.isHidden = false
            splitView.adjustSubviews()
            setSidebarWidth(lastExpandedSidebarWidth)
        } else {
            let currentWidth = splitView.arrangedSubviews[0].frame.width
            if currentWidth >= Metrics.minimumSidebarWidth {
                updateLastExpandedSidebarWidth(currentWidth)
            }

            isSidebarCollapsed = true
            profileListViewController.view.isHidden = true
            splitView.adjustSubviews()
        }

        saveSidebarDefaults()
    }

    private func setSidebarWidth(_ width: CGFloat) {
        let clampedWidth = min(max(width, Metrics.minimumSidebarWidth), Metrics.maximumSidebarWidth)
        splitView.setPosition(clampedWidth, ofDividerAt: 0)
        splitView.layoutSubtreeIfNeeded()
    }

    private func syncSidebarStateFromCurrentWidth() {
        guard splitView.arrangedSubviews.count > 1 else {
            return
        }

        if profileListViewController.view.isHidden {
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
        profileListViewController.view.isHidden = isSidebarCollapsed
        splitView.adjustSubviews()
        lastKnownSplitViewWidth = splitView.bounds.width
        if !isSidebarCollapsed {
            setSidebarWidth(lastExpandedSidebarWidth)
        }
    }

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        guard splitView == self.splitView, dividerIndex == 0, !isSidebarCollapsed else {
            return proposedMinimumPosition
        }

        return Metrics.minimumSidebarWidth
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        guard splitView == self.splitView, dividerIndex == 0 else {
            return proposedMaximumPosition
        }

        let availableMax = splitView.bounds.width - splitView.dividerThickness - Metrics.minimumEditorWidth
        return min(Metrics.maximumSidebarWidth, max(Metrics.minimumSidebarWidth, availableMax))
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        guard let resizedSplitView = notification.object as? NSSplitView, resizedSplitView == splitView else {
            return
        }

        guard hasRestoredSidebarLayout else {
            return
        }

        let currentSplitViewWidth = splitView.bounds.width
        let isWindowResize = abs(currentSplitViewWidth - lastKnownSplitViewWidth) > 0.5
        lastKnownSplitViewWidth = currentSplitViewWidth
        guard !isWindowResize else {
            return
        }

        syncSidebarStateFromCurrentWidth()
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

    func flushPanelLayoutDefaults() {
        savePanelLayout()
        UserDefaults.standard.synchronize()
    }
}
