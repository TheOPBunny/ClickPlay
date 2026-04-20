import Cocoa

final class GamepadWindow: NSPanel {

    private var isMinimized = false

    convenience init() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let profile = ProfileStore.shared.activeProfile
        let size = GamepadContentView.windowSize(for: profile, minimized: false)
        let origin = NSPoint(
            x: screen.visibleFrame.minX + (screen.visibleFrame.width - size.width) / 2,
            y: screen.visibleFrame.minY + 20
        )
        let frame = NSRect(origin: origin, size: size)

        self.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false

        let content = GamepadContentView(frame: NSRect(origin: .zero, size: size), profile: profile)
        content.onToggleMinimize = { [weak self] in
            self?.toggleMinimized()
        }
        content.onHideOverlay = { [weak self] in
            self?.hideOverlay()
        }
        contentView = content

        alphaValue = profile.opacity
        NSLog("[GamepadWindow] Created. level=\(level.rawValue) ignoresMouseEvents=\(ignoresMouseEvents) canBecomeKey=\(canBecomeKey)")
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func showGamepad() {
        orderFrontRegardless()
    }

    func reloadProfile() {
        let profile = ProfileStore.shared.activeProfile
        alphaValue = profile.opacity
        resizeForCurrentState(using: profile)
        (contentView as? GamepadContentView)?.reload(profile: profile, minimized: isMinimized)
    }

    @objc private func hideOverlay() {
        orderOut(nil)
    }

    private func toggleMinimized() {
        isMinimized.toggle()
        let profile = ProfileStore.shared.activeProfile
        resizeForCurrentState(using: profile)
        (contentView as? GamepadContentView)?.setMinimized(isMinimized)
        NSLog("[GamepadWindow] toggleMinimized minimized=\(isMinimized)")
    }

    private func resizeForCurrentState(using profile: Profile) {
        let newSize = GamepadContentView.windowSize(for: profile, minimized: isMinimized)
        guard frame.size != newSize else { return }

        let currentFrame = frame
        let newOrigin = NSPoint(x: currentFrame.minX, y: currentFrame.maxY - newSize.height)
        setFrame(NSRect(origin: newOrigin, size: newSize), display: true)
    }
}
