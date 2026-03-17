import Cocoa

class KeyboardWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

class KeyboardViewController: NSViewController {
    override func loadView() {
        let view = NSView()
        view.frame = NSRect(x: 0, y: 0, width: 300, height: 100)
        self.view = view

        let keys = ["A", "B", "Space"]
        for (i, key) in keys.enumerated() {
            let button = NSButton(title: key, target: self, action: #selector(keyPressed(_:)))
            button.frame = NSRect(x: 20 + i * 90, y: 30, width: 80, height: 40)
            button.bezelStyle = .rounded
            button.tag = i
            view.addSubview(button)
        }
    }

    @objc func keyPressed(_ sender: NSButton) {
        let key = sender.title

        let keyCode: CGKeyCode = {
            switch key {
            case "A": return 0
            case "B": return 11
            case "Space": return 49
            default: return 0
            }
        }()

        let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let viewController = KeyboardViewController()

        window = KeyboardWindow(contentViewController: viewController)
        window.setContentSize(NSSize(width: 300, height: 100))
        window.styleMask = [.titled, .closable]
        window.level = .floating
        window.title = "On-Screen Keyboard"
        window.makeKeyAndOrderFront(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
