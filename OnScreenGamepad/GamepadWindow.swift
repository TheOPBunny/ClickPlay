import Cocoa

final class GamepadWindow: NSPanel {

    private var gamepadHidden = false
    private var togglePill: NSPanel?

    static let defaultSize = CGSize(width: 420, height: 300)

    convenience init() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let sw = screen.visibleFrame.width
        let size = GamepadWindow.defaultSize
        let origin = NSPoint(
            x: screen.visibleFrame.minX + (sw - size.width) / 2,
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

        let profile = ProfileStore.shared.activeProfile
        let content = GamepadContentView(frame: NSRect(origin: .zero, size: size), profile: profile)
        contentView = content

        alphaValue = profile.opacity
        setupTogglePill(near: frame)

        NSLog("[GamepadWindow] Created. level=\(level.rawValue) ignoresMouseEvents=\(ignoresMouseEvents) canBecomeKey=\(canBecomeKey)")
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // Called by the pan gesture in GamepadContentView
    func updatePillPosition() {
        guard let pill = togglePill else { return }
        let pillSize = CGSize(width: 36, height: 20)
        pill.setFrameOrigin(NSPoint(
            x: frame.maxX - pillSize.width - 8,
            y: frame.maxY + 4
        ))
    }

    private func setupTogglePill(near padFrame: NSRect) {
        let pillSize = CGSize(width: 36, height: 20)
        let pillOrigin = NSPoint(x: padFrame.maxX - pillSize.width - 8, y: padFrame.maxY + 4)
        let pill = NSPanel(
            contentRect: NSRect(origin: pillOrigin, size: pillSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        pill.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
        pill.isOpaque = false
        pill.backgroundColor = .clear
        pill.ignoresMouseEvents = false
        pill.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        pill.isReleasedWhenClosed = false
        pill.hidesOnDeactivate = false

        let pillView = NSView(frame: NSRect(origin: .zero, size: pillSize))
        pillView.wantsLayer = true
        pillView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.6).cgColor
        pillView.layer?.cornerRadius = 10

        let btn = NSButton(frame: NSRect(x: 0, y: 0, width: pillSize.width, height: pillSize.height))
        btn.title = "⌃"
        btn.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        btn.isBordered = false
        btn.contentTintColor = .white
        btn.target = self
        btn.action = #selector(toggleGamepad)
        pillView.addSubview(btn)

        pill.contentView = pillView
        pill.orderFrontRegardless()
        self.togglePill = pill
    }

    @objc private func toggleGamepad() {
        gamepadHidden.toggle()
        NSLog("[GamepadWindow] toggleGamepad hidden=\(gamepadHidden)")
        if gamepadHidden {
            orderOut(nil)
            pillButton()?.title = "⌄"
        } else {
            orderFrontRegardless()
            pillButton()?.title = "⌃"
        }
    }

    private func pillButton() -> NSButton? {
        togglePill?.contentView?.subviews.first(where: { $0 is NSButton }) as? NSButton
    }

    func showGamepad() {
        gamepadHidden = false
        orderFrontRegardless()
        togglePill?.orderFrontRegardless()
        pillButton()?.title = "⌃"
    }

    func reloadProfile() {
        let profile = ProfileStore.shared.activeProfile
        alphaValue = profile.opacity
        (contentView as? GamepadContentView)?.reload(profile: profile)
    }
}
