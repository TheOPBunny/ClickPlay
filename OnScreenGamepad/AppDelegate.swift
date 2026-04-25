import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {

    var gamepadWindow: GamepadWindow?
    var statusItem: NSStatusItem?
    private lazy var configuratorWindowController = ConfiguratorWindowController()
    private let supportedOpacityValues: [Double] = [0.25, 0.4, 0.55, 0.7, 0.85, 1.0]

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupMainMenu()
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

    func setupMainMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        let editItem = NSMenuItem()
        mainMenu.addItem(appItem)
        mainMenu.addItem(editItem)

        let appMenu = NSMenu(title: "OnScreenGamepad")
        appMenu.addItem(
            NSMenuItem(
                title: "Quit OnScreenGamepad",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            )
        )
        appItem.submenu = appMenu

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        let redoItem = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redoItem)
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Delete", action: NSSelectorFromString("delete:"), keyEquivalent: "\u{8}"))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: "Align Left", action: NSSelectorFromString("alignLeft:"), keyEquivalent: ""))
        editMenu.addItem(NSMenuItem(title: "Align Center X", action: NSSelectorFromString("alignCenterX:"), keyEquivalent: ""))
        editMenu.addItem(NSMenuItem(title: "Align Right", action: NSSelectorFromString("alignRight:"), keyEquivalent: ""))
        editMenu.addItem(NSMenuItem(title: "Align Top", action: NSSelectorFromString("alignTop:"), keyEquivalent: ""))
        editMenu.addItem(NSMenuItem(title: "Align Center Y", action: NSSelectorFromString("alignCenterY:"), keyEquivalent: ""))
        editMenu.addItem(NSMenuItem(title: "Align Bottom", action: NSSelectorFromString("alignBottom:"), keyEquivalent: ""))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: "Distribute Horizontally", action: NSSelectorFromString("distributeHorizontally:"), keyEquivalent: ""))
        editMenu.addItem(NSMenuItem(title: "Distribute Vertically", action: NSSelectorFromString("distributeVertically:"), keyEquivalent: ""))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: "Equalize Widths", action: NSSelectorFromString("equalizeWidths:"), keyEquivalent: ""))
        editMenu.addItem(NSMenuItem(title: "Equalize Heights", action: NSSelectorFromString("equalizeHeights:"), keyEquivalent: ""))
        editMenu.addItem(NSMenuItem(title: "Equalize Both", action: NSSelectorFromString("equalizeBoth:"), keyEquivalent: ""))
        editItem.submenu = editMenu

        NSApp.mainMenu = nil
        NSApp.mainMenu = mainMenu
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

    func makeGamepadMenu() -> NSMenu {
        let menu = NSMenu(title: "Gamepad")

        let profilesItem = NSMenuItem(title: "Profiles", action: nil, keyEquivalent: "")
        profilesItem.submenu = makeProfilesMenu()
        menu.addItem(profilesItem)

        let transparencyItem = NSMenuItem(title: "Transparency", action: nil, keyEquivalent: "")
        transparencyItem.submenu = makeTransparencyMenu()
        menu.addItem(transparencyItem)

        let fadeItem = NSMenuItem(title: "Fade After", action: nil, keyEquivalent: "")
        fadeItem.submenu = makeFadeMenu()
        menu.addItem(fadeItem)

        menu.addItem(NSMenuItem.separator())

        let editProfilesItem = NSMenuItem(title: "Edit Profiles…", action: #selector(showConfigurator), keyEquivalent: "")
        editProfilesItem.target = self
        menu.addItem(editProfilesItem)

        return menu
    }

    private func makeTransparencyMenu() -> NSMenu {
        let transparencyMenu = NSMenu(title: "Transparency")
        let currentOpacity = ProfileStore.shared.activeProfile.opacity

        for opacity in supportedOpacityValues {
            let percentage = Int(opacity * 100)
            let item = NSMenuItem(title: "\(percentage)%", action: #selector(setActiveProfileOpacity(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = opacity
            item.state = abs(currentOpacity - opacity) < 0.001 ? .on : .off
            transparencyMenu.addItem(item)
        }

        return transparencyMenu
    }

    private func makeFadeMenu() -> NSMenu {
        let fadeMenu = NSMenu(title: "Fade After")
        let currentTimeout = GamepadSettings.fadeTimeout

        for option in GamepadSettings.fadeTimeoutOptions {
            let item = NSMenuItem(title: option.title, action: #selector(setGlobalFadeTimeout(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = option.seconds.map(NSNumber.init(value:)) ?? NSNull()
            item.state = fadeTimeoutsMatch(currentTimeout, option.seconds) ? .on : .off
            fadeMenu.addItem(item)
        }

        return fadeMenu
    }

    func launchGamepad() {
        DispatchQueue.main.async {
            if let gamepadWindow = self.gamepadWindow {
                gamepadWindow.showGamepad()
                return
            }

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

    @objc func setActiveProfileOpacity(_ sender: NSMenuItem) {
        guard let opacity = sender.representedObject as? Double else { return }

        var profile = ProfileStore.shared.activeProfile
        guard abs(profile.opacity - opacity) >= 0.001 else { return }

        profile.opacity = opacity
        ProfileStore.shared.upsert(profile)
    }

    @objc func setGlobalFadeTimeout(_ sender: NSMenuItem) {
        if let timeoutValue = sender.representedObject as? NSNumber {
            GamepadSettings.fadeTimeout = timeoutValue.doubleValue
            return
        }

        GamepadSettings.fadeTimeout = nil
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
            guard let self else {
                return
            }

            let configuratorWindowController = self.configuratorWindowController
            configuratorWindowController.prepareEditorWindow()
            NSApp.setActivationPolicy(.regular)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                configuratorWindowController.showEditorWindow()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    self.setupMainMenu()
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
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

    private func fadeTimeoutsMatch(_ lhs: TimeInterval?, _ rhs: TimeInterval?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case let (lhs?, rhs?):
            return abs(lhs - rhs) < 0.001
        default:
            return false
        }
    }
}
