import Cocoa
import SwiftUI

/// Coordinates app lifetime, the menu bar entry point, onboarding, and the gamepad/editor windows.
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {

    // Long-lived UI controllers are owned here so the status-bar app can reopen them without recreating state.
    var gamepadWindow: GamepadWindow?
    var statusItem: NSStatusItem?
    private var onboardingWindowController: NSWindowController?
    private var editorWindowController: EditorWindowController?
    private var updateCheckWindowController: NSWindowController?
    private var updateCheckViewModel: UpdateCheckViewModel?

    // Runtime state used to rebuild menus, avoid duplicate permission polling, and restore focus after editing.
    private let supportedOpacityValues: [Double] = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]
    private let updateChecker = UpdateChecker.shared
    private var availableUpdate: UpdateCheckResult?
    private var lastActiveNonSelfApplication: NSRunningApplication?
    private var workspaceActivationObserver: NSObjectProtocol?
    private var mouseDiagnosticStateObserver: NSObjectProtocol?
    private var addProfileFromTemplateItem: NSMenuItem?
    private var addLayerFromTemplateItem: NSMenuItem?
    private var isPollingForPermission = false
    private let firstRunIntroCompletedKey = "firstRunIntroCompleted"

    deinit {
        if let workspaceActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceActivationObserver)
        }
        if let mouseDiagnosticStateObserver {
            NotificationCenter.default.removeObserver(mouseDiagnosticStateObserver)
        }
    }

    // MARK: - Application Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        setupMainMenu()
        setupStatusBar()
        observeMouseDiagnosticState()
        startTrackingActiveApplications()
        scheduleAutomaticUpdateCheck()

        // AXIsProcessTrusted() — NO prompt, just checks current state.
        // NOTE: If you see a re-prompt after every build, it's because Xcode's
        // "Automatic" code signing re-signs the binary with a new identity each
        // build, which invalidates macOS TCC trust. Fix: in Xcode target →
        // Signing & Capabilities, set Team and let it stabilize, then copy the
        // built .app to /Applications and run it from there instead of via ⌘R.
        let trusted = AXIsProcessTrusted()
        debugLog("Click Play launched. Accessibility trusted: \(trusted)")

        if trusted {
            launchGamepad()
        } else {
            showFirstRunOnboarding()
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        editorWindowController?.flushPanelLayoutDefaults()
        MouseDiagnosticController.shared.setCaptureTestEnabled(false)
        MouseDiagnosticController.shared.setEnabled(false)
        gamepadWindow?.releaseAllInputs()
        KeyInjector.shared.releaseAllHeldKeys()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard editorWindowController?.confirmSaveIfNeeded() ?? true else {
            return .terminateCancel
        }

        return .terminateNow
    }

    // MARK: - Menu Construction

    func setupMainMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        let fileItem = NSMenuItem()
        let editItem = NSMenuItem()
        let viewItem = NSMenuItem()
        mainMenu.addItem(appItem)
        mainMenu.addItem(fileItem)
        mainMenu.addItem(editItem)
        mainMenu.addItem(viewItem)

        let appMenu = NSMenu(title: "Click Play")
        appMenu.addItem(
            NSMenuItem(
                title: "Quit Click Play",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            )
        )
        appItem.submenu = appMenu

        let fileMenu = NSMenu(title: "File")
        fileMenu.delegate = self
        fileMenu.addItem(NSMenuItem(title: "Save Changes", action: #selector(saveEditorChanges(_:)), keyEquivalent: "s"))
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(NSMenuItem(title: "Add Profile", action: #selector(addEditorProfile(_:)), keyEquivalent: ""))
        fileMenu.addItem(NSMenuItem(title: "Add Layer", action: #selector(addEditorLayer(_:)), keyEquivalent: ""))
        let addProfileFromTemplateItem = NSMenuItem(title: "Add Profile from Template", action: nil, keyEquivalent: "")
        addProfileFromTemplateItem.submenu = makeTemplateCreationMenu(kind: .profile)
        self.addProfileFromTemplateItem = addProfileFromTemplateItem
        fileMenu.addItem(addProfileFromTemplateItem)
        let addLayerFromTemplateItem = NSMenuItem(title: "Add Layer from Template", action: nil, keyEquivalent: "")
        addLayerFromTemplateItem.submenu = makeTemplateCreationMenu(kind: .layer)
        self.addLayerFromTemplateItem = addLayerFromTemplateItem
        fileMenu.addItem(addLayerFromTemplateItem)
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(NSMenuItem(title: "Save Current as Template…", action: #selector(saveCurrentEditorSelectionAsTemplate(_:)), keyEquivalent: ""))
        fileMenu.addItem(NSMenuItem(title: "Manage Templates…", action: #selector(showTemplateManager(_:)), keyEquivalent: ""))
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(NSMenuItem(title: "Remove Profile", action: #selector(removeEditorProfile(_:)), keyEquivalent: ""))
        fileMenu.addItem(NSMenuItem(title: "Remove Layer", action: #selector(removeEditorLayer(_:)), keyEquivalent: ""))
        for item in fileMenu.items {
            item.target = self
        }
        fileItem.submenu = fileMenu

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: NSSelectorFromString("undo:"), keyEquivalent: "z"))
        let redoItem = NSMenuItem(title: "Redo", action: NSSelectorFromString("redo:"), keyEquivalent: "Z")
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

        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(NSMenuItem(title: "Zoom In", action: NSSelectorFromString("zoomIn:"), keyEquivalent: "+"))
        viewMenu.addItem(NSMenuItem(title: "Zoom Out", action: NSSelectorFromString("zoomOut:"), keyEquivalent: "-"))
        viewMenu.addItem(NSMenuItem(title: "Actual Size", action: NSSelectorFromString("actualSize:"), keyEquivalent: "0"))
        viewItem.submenu = viewMenu

        NSApp.mainMenu = mainMenu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu.title == "File" else {
            return
        }

        addProfileFromTemplateItem?.submenu = makeTemplateCreationMenu(kind: .profile)
        addLayerFromTemplateItem?.submenu = makeTemplateCreationMenu(kind: .layer)
    }

    // MARK: - Status Bar

    func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let btn = statusItem?.button else {
            errorLog("ERROR: Could not create status bar item")
            return
        }
        configureStatusBarIcon(for: btn)
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

    private func configureStatusBarIcon(for button: NSStatusBarButton) {
        button.title = ""
        button.toolTip = "Click Play"

        guard let icon = NSImage(named: "Click-Play-menubar-template") else {
            errorLog("ERROR: Could not load Click Play menu bar icon")
            button.title = "CP"
            return
        }

        let iconHeight: CGFloat = 16
        let aspectRatio = icon.size.width / icon.size.height
        icon.size = NSSize(width: iconHeight * aspectRatio, height: iconHeight)
        icon.isTemplate = true
        button.image = icon
        button.imagePosition = .imageOnly
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

        let editProfilesItem = NSMenuItem(title: "Open Editor…", action: #selector(showEditor), keyEquivalent: ",")
        editProfilesItem.target = self
        menu.addItem(editProfilesItem)
        menu.addItem(NSMenuItem.separator())

        let updateTitle = availableUpdate == nil ? "Check for Updates…" : "Update Available…"
        let updateItem = NSMenuItem(title: updateTitle, action: #selector(checkForUpdates(_:)), keyEquivalent: "")
        updateItem.target = self
        menu.addItem(updateItem)
        menu.addItem(NSMenuItem.separator())

        let profilesItem = NSMenuItem(title: "Profiles", action: nil, keyEquivalent: "")
        profilesItem.submenu = makeProfilesMenu()
        menu.addItem(profilesItem)

        menu.addItem(NSMenuItem.separator())
        let accessibilityItem = NSMenuItem(title: "Grant Accessibility Permission", action: #selector(openAccessibility), keyEquivalent: "")
        accessibilityItem.target = self
        menu.addItem(accessibilityItem)

        let mouseDiagnosticsItem = NSMenuItem(title: "Mouse Diagnostics", action: #selector(toggleMouseDiagnostics(_:)), keyEquivalent: "")
        mouseDiagnosticsItem.target = self
        mouseDiagnosticsItem.state = MouseDiagnosticController.shared.isEnabled ? .on : .off
        menu.addItem(mouseDiagnosticsItem)

        let mouseCaptureTestTitle = MouseDiagnosticController.shared.isCaptureTestPending
            ? "Mouse Capture Test (starts in 10s)"
            : "Mouse Capture Test"
        let mouseCaptureTestItem = NSMenuItem(title: mouseCaptureTestTitle, action: #selector(toggleMouseCaptureTest(_:)), keyEquivalent: "")
        mouseCaptureTestItem.target = self
        mouseCaptureTestItem.state = mouseCaptureTestState()
        menu.addItem(mouseCaptureTestItem)
        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    // MARK: - Gamepad Menus

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

        let fadeItem = NSMenuItem(title: "Fade After…", action: nil, keyEquivalent: "")
        fadeItem.submenu = makeFadeMenu()
        menu.addItem(fadeItem)

        let showPointerItem = NSMenuItem(title: "Show Pointer Location", action: #selector(toggleShowPointerLocation(_:)), keyEquivalent: "")
        showPointerItem.target = self
        showPointerItem.state = ProfileStore.shared.activeProfile.showPointerLocation ? .on : .off
        menu.addItem(showPointerItem)

        menu.addItem(NSMenuItem.separator())

        let editProfilesItem = NSMenuItem(title: "Open Editor…", action: #selector(showEditor), keyEquivalent: "")
        editProfilesItem.target = self
        menu.addItem(editProfilesItem)

        return menu
    }

    private func makeTransparencyMenu() -> NSMenu {
        let transparencyMenu = NSMenu(title: "Transparency")
        let currentOpacity = ProfileStore.shared.activeResolvedProfile.opacity

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
        let fadeMenu = NSMenu(title: "Fade After…")
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

    private func makeTemplateCreationMenu(kind: ProfileTemplateKind) -> NSMenu {
        let menu = NSMenu(title: kind == .profile ? "Add Profile from Template" : "Add Layer from Template")
        let templates = ProfileTemplateStore.shared.templates(kind: kind)
        guard !templates.isEmpty else {
            let emptyItem = NSMenuItem(title: "No Saved Templates", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
            return menu
        }

        for template in templates {
            let selector = kind == .profile
                ? #selector(addProfileFromSavedTemplate(_:))
                : #selector(addLayerFromSavedTemplate(_:))
            let item = NSMenuItem(title: template.name, action: selector, keyEquivalent: "")
            item.target = self
            item.representedObject = template.id.uuidString
            menu.addItem(item)
        }

        return menu
    }

    // MARK: - Gamepad Launch and Onboarding

    func launchGamepad() {
        DispatchQueue.main.async {
            if let gamepadWindow = self.gamepadWindow {
                gamepadWindow.showGamepad()
                return
            }

            debugLog("Launching gamepad window...")
            self.gamepadWindow = GamepadWindow()
            self.gamepadWindow?.orderFrontRegardless()
            debugLog("Gamepad window frame: \(self.gamepadWindow?.frame ?? .zero)")
        }
    }

    private func showFirstRunOnboarding() {
        let introCompleted = UserDefaults.standard.bool(forKey: firstRunIntroCompletedKey)
        showFirstRunOnboarding(startingAt: introCompleted ? .accessibility : .welcome)
    }

    private func showFirstRunOnboarding(startingAt initialStep: FirstRunOnboardingStep) {
        if let onboardingWindow = onboardingWindowController?.window {
            centerOnboardingWindow(onboardingWindow)
            onboardingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let onboardingView = FirstRunOnboardingView(
            initialStep: initialStep,
            onFinishedIntro: { [weak self] in
                self?.markFirstRunIntroCompleted()
            },
            onGrantPermission: { [weak self] in
                self?.requestAccessibilityPermission()
            },
            onLearnMore: {
                NSWorkspace.shared.open(URL(string: "https://github.com/TheOPBunny/ClickPlay")!)
            }
        )

        let hostingController = NSHostingController(rootView: onboardingView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Click Play"
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titlebarAppearsTransparent = true
        window.setContentSize(NSSize(width: 720, height: 620))
        centerOnboardingWindow(window)
        window.delegate = self

        let windowController = NSWindowController(window: window)
        onboardingWindowController = windowController
        windowController.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func centerOnboardingWindow(_ window: NSWindow) {
        let screen = NSScreen.main ?? window.screen ?? NSScreen.screens.first
        guard let visibleFrame = screen?.visibleFrame else {
            window.center()
            return
        }

        let size = window.frame.size
        let origin = NSPoint(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.midY - size.height / 2
        )
        window.setFrameOrigin(origin)
    }

    private func markFirstRunIntroCompleted() {
        UserDefaults.standard.set(true, forKey: firstRunIntroCompletedKey)
    }

    private func requestAccessibilityPermission() {
        markFirstRunIntroCompleted()
        AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        )
        startPollingForPermission()
    }

    private func startPollingForPermission() {
        guard !isPollingForPermission else { return }

        isPollingForPermission = true
        pollForPermission()
    }

    // MARK: - Profile and Settings Actions

    func pollForPermission() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            if AXIsProcessTrusted() {
                debugLog("Accessibility permission granted — launching gamepad.")
                self?.isPollingForPermission = false
                self?.onboardingWindowController?.close()
                self?.onboardingWindowController = nil
                self?.launchGamepad()
            } else {
                self?.pollForPermission()
            }
        }
    }

    @objc func switchProfile(_ sender: NSMenuItem) {
        guard let idStr = sender.representedObject as? String,
              let id = UUID(uuidString: idStr) else { return }
        activateProfileIfAllowed(id)
    }

    @discardableResult
    func activateProfileIfAllowed(_ id: UUID) -> Bool {
        guard confirmEditorNavigationIfNeeded() else {
            rebuildMenu()
            return false
        }

        ProfileStore.shared.setActive(id)
        return true
    }

    @discardableResult
    func activateSubProfileIfAllowed(_ id: UUID) -> Bool {
        guard confirmEditorNavigationIfNeeded() else {
            return false
        }

        ProfileStore.shared.setActiveSubProfile(id)
        return true
    }

    @objc func setActiveProfileOpacity(_ sender: NSMenuItem) {
        guard let opacity = sender.representedObject as? Double else { return }

        var profile = ProfileStore.shared.activeResolvedProfile
        guard abs(profile.opacity - opacity) >= 0.001 else { return }

        profile.opacity = opacity
        if let parentProfile = ProfileStore.shared.parentProfile(containingSubProfileID: profile.id) {
            ProfileStore.shared.upsertSubProfile(profile, in: parentProfile.id)
        } else {
            ProfileStore.shared.upsert(profile)
        }
    }

    @objc func setGlobalFadeTimeout(_ sender: NSMenuItem) {
        if let timeoutValue = sender.representedObject as? NSNumber {
            GamepadSettings.fadeTimeout = timeoutValue.doubleValue
            return
        }

        GamepadSettings.fadeTimeout = nil
    }

    @objc func toggleShowPointerLocation(_ sender: NSMenuItem) {
        ProfileStore.shared.updateActiveProfileShowPointerLocation(!ProfileStore.shared.activeProfile.showPointerLocation)
    }

    @objc func toggleMouseDiagnostics(_ sender: NSMenuItem) {
        let enabled = MouseDiagnosticController.shared.toggle()
        sender.state = enabled ? .on : .off
        rebuildMenu()
    }

    @objc func toggleMouseCaptureTest(_ sender: NSMenuItem) {
        let enabled = MouseDiagnosticController.shared.toggleCaptureTest()
        sender.state = enabled ? mouseCaptureTestState() : .off
        rebuildMenu()
    }

    private func mouseCaptureTestState() -> NSControl.StateValue {
        if MouseDiagnosticController.shared.isCaptureTestEnabled {
            return .on
        }

        if MouseDiagnosticController.shared.isCaptureTestPending {
            return .mixed
        }

        return .off
    }

    // MARK: - Window and Editor Actions

    @objc func showGamepad() {
        guard AXIsProcessTrusted() else {
            showFirstRunOnboarding(startingAt: .accessibility)
            return
        }

        if gamepadWindow == nil {
            launchGamepad()
        } else {
            gamepadWindow?.showGamepad()
        }
    }

    @objc func hideGamepad() {
        gamepadWindow?.hideGamepad()
    }

    @objc func saveEditorChanges(_ sender: Any?) {
        getEditorWindowController().showEditorWindow()
        getEditorWindowController().saveChanges()
    }

    @objc func addEditorProfile(_ sender: Any?) {
        getEditorWindowController().showEditorWindow()
        getEditorWindowController().addProfile()
    }

    @objc func addEditorLayer(_ sender: Any?) {
        getEditorWindowController().showEditorWindow()
        getEditorWindowController().addLayer()
    }

    @objc func addDefaultTemplateProfile(_ sender: Any?) {
        getEditorWindowController().showEditorWindow()
        getEditorWindowController().addDefaultTemplateProfile()
    }

    @objc func addDefaultTemplateLayer(_ sender: Any?) {
        getEditorWindowController().showEditorWindow()
        getEditorWindowController().addDefaultTemplateLayer()
    }

    @objc func addProfileFromSavedTemplate(_ sender: NSMenuItem) {
        guard let templateID = templateID(from: sender) else { return }
        getEditorWindowController().showEditorWindow()
        getEditorWindowController().addProfileFromTemplate(id: templateID)
    }

    @objc func addLayerFromSavedTemplate(_ sender: NSMenuItem) {
        guard let templateID = templateID(from: sender) else { return }
        getEditorWindowController().showEditorWindow()
        getEditorWindowController().addLayerFromTemplate(id: templateID)
    }

    @objc func saveCurrentEditorSelectionAsTemplate(_ sender: Any?) {
        getEditorWindowController().showEditorWindow()
        getEditorWindowController().saveCurrentAsTemplate()
    }

    @objc func showTemplateManager(_ sender: Any?) {
        getEditorWindowController().showEditorWindow()
        getEditorWindowController().showTemplateManager()
    }

    @objc func removeEditorProfile(_ sender: Any?) {
        getEditorWindowController().showEditorWindow()
        getEditorWindowController().removeProfile()
    }

    @objc func removeEditorLayer(_ sender: Any?) {
        getEditorWindowController().showEditorWindow()
        getEditorWindowController().removeLayer()
    }

    @objc func showEditor() {
        updateLastActiveApplicationIfNeeded(NSWorkspace.shared.frontmostApplication)
        getEditorWindowController().showEditorWindow()
    }

    @MainActor
    @objc func checkForUpdates(_ sender: Any?) {
        let initialState = availableUpdate.map(UpdateCheckViewState.updateAvailable) ?? .checking
        showUpdateCheckWindow(initialState: initialState)
    }

    @objc func openAccessibility() {
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        )
    }

    // MARK: - Helpers

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow === onboardingWindowController?.window {
            onboardingWindowController = nil
        }

        if notification.object as? NSWindow === updateCheckWindowController?.window {
            updateCheckWindowController = nil
            updateCheckViewModel = nil
        }
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

    private func confirmEditorNavigationIfNeeded() -> Bool {
        editorWindowController?.confirmSaveIfNeeded() ?? true
    }

    private func templateID(from sender: NSMenuItem) -> UUID? {
        guard let idString = sender.representedObject as? String else {
            return nil
        }

        return UUID(uuidString: idString)
    }

    private func startTrackingActiveApplications() {
        updateLastActiveApplicationIfNeeded(NSWorkspace.shared.frontmostApplication)

        workspaceActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.updateLastActiveApplicationIfNeeded(application)
        }
    }

    private func observeMouseDiagnosticState() {
        mouseDiagnosticStateObserver = NotificationCenter.default.addObserver(
            forName: MouseDiagnosticController.stateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.rebuildMenu()
        }
    }

    private func updateLastActiveApplicationIfNeeded(_ application: NSRunningApplication?) {
        guard let application, application.processIdentifier != NSRunningApplication.current.processIdentifier else {
            return
        }

        lastActiveNonSelfApplication = application
    }

    private func restorePreviousApplicationFocus() {
        guard let application = lastActiveNonSelfApplication, !application.isTerminated else {
            return
        }

        application.activate(options: [.activateIgnoringOtherApps])
    }

    private func getEditorWindowController() -> EditorWindowController {
        if let editorWindowController {
            return editorWindowController
        }

        let controller = EditorWindowController()
        controller.onClose = { [weak self] in
            self?.restorePreviousApplicationFocus()
        }
        editorWindowController = controller
        return controller
    }

    private func scheduleAutomaticUpdateCheck() {
        let checker = updateChecker

        Task { [weak self] in
            do {
                guard let result = try await checker.checkForUpdatesIfNeeded(),
                      result.isUpdateAvailable else {
                    return
                }

                await MainActor.run { [weak self] in
                    self?.handleUpdateCheckResult(result)
                    self?.showUpdateCheckWindow(initialState: .updateAvailable(result))
                }
            } catch {
                debugLog("Automatic update check failed: \(error.localizedDescription)")
            }
        }
    }

    @MainActor
    private func handleUpdateCheckResult(_ result: UpdateCheckResult) {
        availableUpdate = result.isUpdateAvailable ? result : nil
        statusItem?.button?.toolTip = result.isUpdateAvailable ? "Click Play - Update available" : "Click Play"
        rebuildMenu()
    }

    @MainActor
    private func showUpdateCheckWindow(initialState: UpdateCheckViewState) {
        updateCheckWindowController?.close()
        updateCheckWindowController = nil
        updateCheckViewModel = nil

        let viewModel = UpdateCheckViewModel(
            checker: updateChecker,
            initialState: initialState,
            onResult: { [weak self] result in
                self?.handleUpdateCheckResult(result)
            },
            onSkip: { [weak self] result in
                self?.handleSkippedUpdateResult(result)
            }
        )
        let view = UpdateCheckView(
            viewModel: viewModel,
            onDismiss: { [weak self] in
                self?.closeUpdateCheckWindow()
            }
        )

        let hostingController = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Software Update"
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titlebarAppearsTransparent = true
        window.setContentSize(NSSize(width: 440, height: 270))
        window.center()
        window.delegate = self

        let windowController = NSWindowController(window: window)
        updateCheckViewModel = viewModel
        updateCheckWindowController = windowController
        windowController.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @MainActor
    private func handleSkippedUpdateResult(_ result: UpdateCheckResult) {
        guard availableUpdate?.latestVersion == result.latestVersion else {
            return
        }

        availableUpdate = nil
        statusItem?.button?.toolTip = "Click Play"
        rebuildMenu()
    }

    @MainActor
    private func closeUpdateCheckWindow() {
        updateCheckWindowController?.close()
        updateCheckWindowController = nil
        updateCheckViewModel = nil
    }
}
