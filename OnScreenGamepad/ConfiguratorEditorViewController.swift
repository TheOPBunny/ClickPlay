import Cocoa

final class ConfiguratorViewController: NSSplitViewController {

    private let profileListViewController = ProfileListViewController()
    private let editorViewController = ButtonEditorViewController()
    private var profilesDidChangeObserver: NSObjectProtocol?
    private var shouldSkipNextEditorRefresh = false

    override func viewDidLoad() {
        super.viewDidLoad()

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: profileListViewController)
        sidebarItem.minimumThickness = 200
        sidebarItem.maximumThickness = 360
        sidebarItem.canCollapse = true
        sidebarItem.preferredThicknessFraction = 0.22

        addSplitViewItem(sidebarItem)
        addSplitViewItem(NSSplitViewItem(viewController: editorViewController))
        splitView.autosaveName = "ConfiguratorSplitView"

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

    deinit {
        if let profilesDidChangeObserver {
            NotificationCenter.default.removeObserver(profilesDidChangeObserver)
        }
    }
}
