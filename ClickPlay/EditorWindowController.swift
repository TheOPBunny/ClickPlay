import Cocoa

final class EditorWindowController: NSWindowController, NSWindowDelegate {

    var onClose: (() -> Void)?
    private var editorViewController: EditorViewController?

    convenience init() {
        let viewController = EditorViewController()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 780),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        window.title = "Click Play Editor"
        window.contentViewController = viewController
        if !window.setFrameUsingName("EditorWindow") {
            window.center()
        }
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        window.tabbingMode = .disallowed
        window.setFrameAutosaveName("EditorWindow")
        window.contentMinSize = NSSize(width: 760, height: 680)

        self.init(window: window)
        editorViewController = viewController
        window.delegate = self
    }

    func showEditorWindow() {
        if let window {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
        }

        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        activateEditorApp()
    }

    func windowWillClose(_ notification: Notification) {
        flushPanelLayoutDefaults()
        onClose?()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        editorViewController?.confirmSaveIfNeeded() ?? true
    }

    func flushPanelLayoutDefaults() {
        editorViewController?.flushPanelLayoutDefaults()
    }

    @discardableResult
    func saveChanges() -> Bool {
        editorViewController?.saveChanges() ?? true
    }

    func confirmSaveIfNeeded() -> Bool {
        editorViewController?.confirmSaveIfNeeded() ?? true
    }

    func addProfile() {
        editorViewController?.addProfile()
    }

    func addLayer() {
        editorViewController?.addLayer()
    }

    func removeProfile() {
        editorViewController?.removeProfile()
    }

    func removeLayer() {
        editorViewController?.removeLayer()
    }

    private func activateEditorApp() {
        NSApp.activate(ignoringOtherApps: true)
    }
}
