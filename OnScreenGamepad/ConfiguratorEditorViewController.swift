import Cocoa

final class ConfiguratorViewController: NSSplitViewController {

    private let profileListViewController = ProfileListViewController()
    private let editorViewController = ButtonEditorViewController()
    private var profilesDidChangeObserver: NSObjectProtocol?

    override func viewDidLoad() {
        super.viewDidLoad()

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: profileListViewController)
        sidebarItem.minimumThickness = 200
        sidebarItem.maximumThickness = 260

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
