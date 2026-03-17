import Cocoa

/// A borderless, always-on-top, draggable, transparent overlay window.
final class GamepadWindow: NSPanel {

    private var dragStart: NSPoint = .zero
    private var opacity: CGFloat = 0.90

    // Desired size of the gamepad UI
    static let defaultSize = CGSize(width: 420, height: 280)

    convenience init() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let sw = screen.visibleFrame.width
        let sh = screen.visibleFrame.height
        let size = GamepadWindow.defaultSize
        // Default: bottom-center of screen
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

        // Float above all normal windows.
        // CGWindowLevelForKey(.floatingWindow) = 3; +1 keeps us above other panels.
        // Use .screenSaver level (1000) so we clear most overlays.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false

        // Content
        let content = GamepadContentView(frame: NSRect(origin: .zero, size: size))
        contentView = content

        // Opacity slider + close/hide buttons in a tiny HUD
        addControlStrip()

        alphaValue = opacity
    }

    // MARK: - Panel overrides

    // We want the panel to NOT steal focus from other apps
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override var acceptsFirstResponder: Bool { false }

    // MARK: - Dragging

    override func mouseDown(with event: NSEvent) {
        dragStart = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        let current = event.locationInWindow
        let dx = current.x - dragStart.x
        let dy = current.y - dragStart.y
        var origin = frame.origin
        origin.x += dx
        origin.y += dy
        setFrameOrigin(origin)
    }

    // MARK: - Control Strip

    private func addControlStrip() {
        let strip = NSView(frame: NSRect(x: 0, y: frame.height - 22, width: frame.width, height: 22))
        strip.autoresizingMask = [.width, .minYMargin]
        strip.wantsLayer = true
        strip.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.4).cgColor
        strip.layer?.cornerRadius = 20
        strip.layer?.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]

        // Close button
        let closeBtn = makeStripButton(title: "✕", x: 8)
        closeBtn.action = #selector(hideGamepad)
        closeBtn.target = self
        strip.addSubview(closeBtn)

        // Opacity label
        let opacLabel = NSTextField(labelWithString: "Opacity:")
        opacLabel.font = NSFont.systemFont(ofSize: 9)
        opacLabel.textColor = .white
        opacLabel.frame = NSRect(x: 38, y: 3, width: 50, height: 16)
        strip.addSubview(opacLabel)

        // Opacity slider
        let slider = NSSlider(frame: NSRect(x: 90, y: 4, width: 120, height: 14))
        slider.minValue = 0.25
        slider.maxValue = 1.0
        slider.doubleValue = Double(opacity)
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(opacityChanged(_:))
        strip.addSubview(slider)

        // Drag hint
        let hint = NSTextField(labelWithString: "⠿ drag")
        hint.font = NSFont.systemFont(ofSize: 9)
        hint.textColor = NSColor.white.withAlphaComponent(0.4)
        hint.frame = NSRect(x: frame.width - 55, y: 3, width: 48, height: 16)
        strip.addSubview(hint)

        contentView?.addSubview(strip)
    }

    private func makeStripButton(title: String, x: CGFloat) -> NSButton {
        let btn = NSButton(frame: NSRect(x: x, y: 2, width: 28, height: 18))
        btn.title = title
        btn.font = NSFont.systemFont(ofSize: 10)
        btn.isBordered = false
        btn.wantsLayer = true
        btn.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.15).cgColor
        btn.layer?.cornerRadius = 4
        (btn.cell as? NSButtonCell)?.backgroundColor = .clear
        btn.contentTintColor = .white
        return btn
    }

    @objc private func hideGamepad() {
        orderOut(nil)
    }

    @objc private func showGamepad() {
        makeKeyAndOrderFront(nil)
        orderFrontRegardless()
    }

    @objc private func opacityChanged(_ sender: NSSlider) {
        alphaValue = sender.doubleValue
        opacity = sender.doubleValue
    }
}
