import Cocoa

final class ConfiguratorWindowController: NSWindowController, NSWindowDelegate {

    var onClose: (() -> Void)?

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
        window.contentMinSize = NSSize(width: 980, height: 680)

        self.init(window: window)
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
        onClose?()
    }

    private func activateEditorApp() {
        NSApp.activate(ignoringOtherApps: true)
    }
}
