import Cocoa

final class ConfiguratorWindowController: NSWindowController, NSWindowDelegate {

    convenience init() {
        let viewController = ConfiguratorViewController()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 620),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        window.title = "Gamepad Configurator"
        window.contentViewController = viewController
        window.center()
        window.isReleasedWhenClosed = false

        self.init(window: window)
        window.delegate = self
    }

    func showEditorWindow() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
