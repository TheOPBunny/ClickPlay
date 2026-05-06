import Cocoa

final class EditorWindowController: NSWindowController, NSWindowDelegate {

    private static let editorFrameAutosaveName = NSWindow.FrameAutosaveName("EditorWindow")

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
        window.contentMinSize = NSSize(width: 760, height: 680)
        if !window.setFrameUsingName(Self.editorFrameAutosaveName) {
            window.center()
        }
        window.contentViewController = viewController
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        window.tabbingMode = .disallowed
        window.setFrameAutosaveName(Self.editorFrameAutosaveName)

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
        editorViewController?.centerCanvasOnProfileContentWhenReady()
    }

    func windowWillClose(_ notification: Notification) {
        flushPanelLayoutDefaults()
        onClose?()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        editorViewController?.confirmSaveIfNeeded() ?? true
    }

    func windowDidMove(_ notification: Notification) {
        persistEditorWindowFrame()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        persistEditorWindowFrame()
    }

    func flushPanelLayoutDefaults() {
        persistEditorWindowFrame()
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

    func addDefaultTemplateProfile() {
        editorViewController?.addDefaultTemplateProfile()
    }

    func addDefaultTemplateLayer() {
        editorViewController?.addDefaultTemplateLayer()
    }

    func addProfileFromTemplate(id: UUID) {
        editorViewController?.addProfileFromTemplate(id: id)
    }

    func addLayerFromTemplate(id: UUID) {
        editorViewController?.addLayerFromTemplate(id: id)
    }

    func saveCurrentAsTemplate() {
        editorViewController?.saveCurrentAsTemplate()
    }

    func showTemplateManager() {
        editorViewController?.showTemplateManager()
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

    private func persistEditorWindowFrame() {
        guard let window else {
            return
        }

        window.saveFrame(usingName: Self.editorFrameAutosaveName)
        UserDefaults.standard.synchronize()
    }
}
