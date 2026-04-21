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
        statusItem?.button?.performClick(nil)
    }

    func rebuildMenu() {
        let menu = NSMenu()

        let showItem = NSMenuItem(title: "Show Gamepad", action: #selector(showGamepad), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)

        let hideItem = NSMenuItem(title: "Hide Gamepad", action: #selector(hideGamepad), keyEquivalent: "")
        hideItem.target = self
        menu.addItem(hideItem)

        let editProfilesItem = NSMenuItem(title: "Edit Profiles…", action: #selector(showConfigurator), keyEquivalent: ",")
        editProfilesItem.target = self
        menu.addItem(editProfilesItem)
        menu.addItem(NSMenuItem.separator())

        let profilesItem = NSMenuItem(title: "Profiles", action: nil, keyEquivalent: "")
        profilesItem.submenu = makeProfilesMenu()
        menu.addItem(profilesItem)

        menu.addItem(NSMenuItem.separator())
        let accessibilityItem = NSMenuItem(title: "Grant Accessibility Permission", action: #selector(openAccessibility), keyEquivalent: "")
        accessibilityItem.target = self
        menu.addItem(accessibilityItem)
        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    private func makeProfilesMenu() -> NSMenu {
        let profilesMenu = NSMenu(title: "Profiles")

        for profile in ProfileStore.shared.profiles {
            let item = NSMenuItem(title: profile.name, action: #selector(switchProfile(_:)), keyEquivalent: "")
            item.representedObject = profile.id.uuidString
            item.target = self
            item.state = profile.id == ProfileStore.shared.activeProfileID ? .on : .off
            profilesMenu.addItem(item)
        }

        return profilesMenu
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
        DispatchQueue.main.async { [weak self] in
            self?.configuratorWindowController.showEditorWindow()
        }
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
