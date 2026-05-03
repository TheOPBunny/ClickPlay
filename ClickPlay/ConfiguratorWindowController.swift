import Cocoa

final class ConfiguratorWindowController: NSWindowController, NSWindowDelegate {

    var onClose: (() -> Void)?
    private var configuratorViewController: ConfiguratorViewController?

    convenience init() {
        let viewController = ConfiguratorViewController()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 780),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        window.title = "Gamepad Configurator"
        window.contentViewController = viewController
        window.center()
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        window.tabbingMode = .disallowed
        window.setFrameAutosaveName("ConfiguratorWindow")
        window.contentMinSize = NSSize(width: 760, height: 680)

        self.init(window: window)
        configuratorViewController = viewController
        window.delegate = self
    }

    func showEditorWindow() {
        if let window {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }

            if !window.isVisible {
                window.center()
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

    func flushPanelLayoutDefaults() {
        configuratorViewController?.flushPanelLayoutDefaults()
    }

    private func activateEditorApp() {
        NSApp.activate(ignoringOtherApps: true)
    }
}
