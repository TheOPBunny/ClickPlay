import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {

    var gamepadWindow: GamepadWindow?
    var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Always create the status bar item immediately so there's always something visible
        setupStatusBar()

        // Check accessibility — prompt if needed
        let trusted = AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        )

        NSLog("OnScreenGamepad launched. Accessibility trusted: \(trusted)")

        if trusted {
            launchGamepad()
        } else {
            NSLog("Waiting for accessibility permission. Grant it in System Settings, then click 'Show Gamepad' in the menu bar icon.")
            pollForPermission()
        }
    }

    func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let btn = statusItem?.button else {
            NSLog("ERROR: Could not create status bar item")
            return
        }
        btn.title = "🎮"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show Gamepad", action: #selector(showGamepad), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Hide Gamepad", action: #selector(hideGamepad), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Grant Accessibility Permission", action: #selector(openAccessibility), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    func launchGamepad() {
        DispatchQueue.main.async {
            NSLog("Launching gamepad window...")
            self.gamepadWindow = GamepadWindow()
            self.gamepadWindow?.makeKeyAndOrderFront(nil)
            self.gamepadWindow?.orderFrontRegardless()
            NSLog("Gamepad window frame: \(self.gamepadWindow?.frame ?? .zero)")
        }
    }

    func pollForPermission() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            if AXIsProcessTrusted() {
                NSLog("Accessibility permission granted — launching gamepad.")
                self?.launchGamepad()
            } else {
                self?.pollForPermission()
            }
        }
    }

    @objc func showGamepad() {
        if gamepadWindow == nil {
            launchGamepad()
        } else {
            gamepadWindow?.makeKeyAndOrderFront(nil)
            gamepadWindow?.orderFrontRegardless()
        }
    }

    @objc func hideGamepad() {
        gamepadWindow?.orderOut(nil)
    }

    @objc func openAccessibility() {
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        )
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
