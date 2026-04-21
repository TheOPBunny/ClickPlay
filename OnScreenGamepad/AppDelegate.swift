import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {

    var gamepadWindow: GamepadWindow?
    var statusItem: NSStatusItem?
    private lazy var configuratorWindowController = ConfiguratorWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusBar()

        // AXIsProcessTrusted() — NO prompt, just checks current state.
        // NOTE: If you see a re-prompt after every build, it's because Xcode's
        // "Automatic" code signing re-signs the binary with a new identity each
        // build, which invalidates macOS TCC trust. Fix: in Xcode target →
        // Signing & Capabilities, set Team and let it stabilize, then copy the
        // built .app to /Applications and run it from there instead of via ⌘R.
        let trusted = AXIsProcessTrusted()
        NSLog("OnScreenGamepad launched. Accessibility trusted: \(trusted)")

        if trusted {
            launchGamepad()
        } else {
            // Show the system prompt exactly once
            AXIsProcessTrustedWithOptions(
                [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            )
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
        btn.target = self
        btn.action = #selector(statusBarClicked)
        btn.sendAction(on: [.leftMouseUp, .rightMouseUp])
        rebuildMenu()

        // Rebuild menu and reload gamepad whenever profiles change
        NotificationCenter.default.addObserver(
            forName: ProfileStore.profilesDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.rebuildMenu()
            self?.gamepadWindow?.reloadProfile()
        }
    }

    @objc func statusBarClicked() {
        rebuildMenu()
        statusItem?.popUpMenu(statusItem!.menu!)
    }

    func rebuildMenu() {
        let menu = NSMenu()

        menu.addItem(NSMenuItem(title: "Show Gamepad", action: #selector(showGamepad), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Hide Gamepad", action: #selector(hideGamepad), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Edit Profiles…", action: #selector(showConfigurator), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())

        // Profile switcher
        let profilesHeader = NSMenuItem(title: "Profiles", action: nil, keyEquivalent: "")
        profilesHeader.isEnabled = false
        menu.addItem(profilesHeader)

        for profile in ProfileStore.shared.profiles {
            let item = NSMenuItem(title: profile.name, action: #selector(switchProfile(_:)), keyEquivalent: "")
            item.representedObject = profile.id.uuidString
            item.target = self
            if profile.id == ProfileStore.shared.activeProfileID {
                item.state = .on
            }
            menu.addItem(item)
        }

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

    @objc func switchProfile(_ sender: NSMenuItem) {
        guard let idStr = sender.representedObject as? String,
              let id = UUID(uuidString: idStr) else { return }
        ProfileStore.shared.setActive(id)
        gamepadWindow?.reloadProfile()
        rebuildMenu()
    }

    @objc func showGamepad() {
        if gamepadWindow == nil {
            launchGamepad()
        } else {
            gamepadWindow?.showGamepad()
        }
    }

    @objc func hideGamepad() {
        gamepadWindow?.orderOut(nil)
    }

    @objc func showConfigurator() {
        configuratorWindowController.showEditorWindow()
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
