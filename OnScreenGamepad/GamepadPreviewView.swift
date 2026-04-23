import Cocoa

final class GamepadPreviewView: NSView {

    var onButtonSelected: ((GamepadButton) -> Void)?
    var onButtonMoved: ((GamepadButton, Double, Double) -> Void)?
    var onButtonResized: ((GamepadButton, Double, Double) -> Void)?

    private var buttonLayers: [GamepadButton: CALayer] = [:]
    private var handleLayers: [GamepadButton: CALayer] = [:]
    private var selectedButton: GamepadButton?
    private var profile = ProfileStore.shared.activeProfile
    private var lastRenderedSize: CGSize = .zero

    private enum DragMode {
        case move
        case resizeBottomRight
    }

    private var dragMode: DragMode = .move
    private var dragButton: GamepadButton?
    private var dragStartMouse: CGPoint = .zero
    private var dragStartButtonCenter: CGPoint = .zero
    private var dragStartButtonSize: CGSize = .zero

    private let handleSize: CGFloat = 8

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.10, alpha: 1).cgColor
        layer?.cornerRadius = 14
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func reload(profile: Profile, keepSelection: Bool) {
        let previousSelection = keepSelection ? selectedButton : nil
        let shouldRebuild = bounds.size != lastRenderedSize
        self.profile = profile
        lastRenderedSize = bounds.size

        if shouldRebuild {
            rebuildLayers()
        } else {
            updateExistingLayers()
        }

        highlight(previousSelection)
    }

    private func rebuildLayers() {
        buttonLayers.values.forEach { $0.removeFromSuperlayer() }
        handleLayers.values.forEach { $0.removeFromSuperlayer() }
        buttonLayers.removeAll()
        handleLayers.removeAll()

        let width = bounds.width
        let height = bounds.height

        for button in GamepadButton.allCases {
            guard let config = profile.buttons[button.rawValue], config.enabled else {
                continue
            }

            let centerX = CGFloat(config.x) * width
            let centerY = CGFloat(config.y) * height
            let buttonWidth = CGFloat(config.width) * width
            let buttonHeight = CGFloat(config.height) * height

            let buttonLayer = CALayer()
            buttonLayer.frame = CGRect(
                x: centerX - (buttonWidth / 2),
                y: centerY - (buttonHeight / 2),
                width: buttonWidth,
                height: buttonHeight
            )
            buttonLayer.backgroundColor = NSColor(hex: config.colorHex).withAlphaComponent(0.85).cgColor
            buttonLayer.cornerRadius = 6

            let textLayer = CATextLayer()
            textLayer.string = config.resolvedDisplayLabel
            textLayer.fontSize = 10
            textLayer.alignmentMode = .center
            textLayer.foregroundColor = NSColor.white.cgColor
            textLayer.contentsScale = window?.backingScaleFactor ?? 2
            textLayer.frame = buttonLayer.bounds
            buttonLayer.addSublayer(textLayer)

            layer?.addSublayer(buttonLayer)
            buttonLayers[button] = buttonLayer

            let handleLayer = CALayer()
            handleLayer.frame = CGRect(
                x: buttonLayer.frame.maxX - handleSize,
                y: buttonLayer.frame.minY,
                width: handleSize,
                height: handleSize
            )
            handleLayer.backgroundColor = NSColor.white.withAlphaComponent(0.7).cgColor
            handleLayer.cornerRadius = 2
            handleLayer.isHidden = true
            layer?.addSublayer(handleLayer)
            handleLayers[button] = handleLayer
        }
    }

    private func updateExistingLayers() {
        let activeButtons = Set(GamepadButton.allCases.filter {
            guard let config = profile.buttons[$0.rawValue] else {
                return false
            }

            return config.enabled
        })

        for button in Array(buttonLayers.keys) where !activeButtons.contains(button) {
            buttonLayers[button]?.removeFromSuperlayer()
            buttonLayers.removeValue(forKey: button)

            handleLayers[button]?.removeFromSuperlayer()
            handleLayers.removeValue(forKey: button)
        }

        for button in GamepadButton.allCases {
            guard let config = profile.buttons[button.rawValue], config.enabled else {
                continue
            }

            let buttonLayer = buttonLayers[button] ?? makeButtonLayer(for: button)
            let handleLayer = handleLayers[button] ?? makeHandleLayer(for: button)
            update(buttonLayer: buttonLayer, handleLayer: handleLayer, with: config)
        }
    }

    private func makeButtonLayer(for button: GamepadButton) -> CALayer {
        let buttonLayer = CALayer()
        buttonLayer.cornerRadius = 6

        let textLayer = CATextLayer()
        textLayer.fontSize = 10
        textLayer.alignmentMode = .center
        textLayer.foregroundColor = NSColor.white.cgColor
        textLayer.contentsScale = window?.backingScaleFactor ?? 2
        buttonLayer.addSublayer(textLayer)

        layer?.addSublayer(buttonLayer)
        buttonLayers[button] = buttonLayer
        return buttonLayer
    }

    private func makeHandleLayer(for button: GamepadButton) -> CALayer {
        let handleLayer = CALayer()
        handleLayer.backgroundColor = NSColor.white.withAlphaComponent(0.7).cgColor
        handleLayer.cornerRadius = 2
        handleLayer.isHidden = true
        layer?.addSublayer(handleLayer)
        handleLayers[button] = handleLayer
        return handleLayer
    }

    private func update(buttonLayer: CALayer, handleLayer: CALayer, with config: ButtonConfig) {
        let width = bounds.width
        let height = bounds.height
        let centerX = CGFloat(config.x) * width
        let centerY = CGFloat(config.y) * height
        let buttonWidth = CGFloat(config.width) * width
        let buttonHeight = CGFloat(config.height) * height

        buttonLayer.frame = CGRect(
            x: centerX - (buttonWidth / 2),
            y: centerY - (buttonHeight / 2),
            width: buttonWidth,
            height: buttonHeight
        )
        buttonLayer.backgroundColor = NSColor(hex: config.colorHex).withAlphaComponent(0.85).cgColor

        if let textLayer = buttonLayer.sublayers?.first as? CATextLayer {
            textLayer.string = config.resolvedDisplayLabel
            textLayer.contentsScale = window?.backingScaleFactor ?? 2
            textLayer.frame = buttonLayer.bounds
        }

        handleLayer.frame = CGRect(
            x: buttonLayer.frame.maxX - handleSize,
            y: buttonLayer.frame.minY,
            width: handleSize,
            height: handleSize
        )
    }

    override func layout() {
        super.layout()
        guard bounds.size != .zero, bounds.size != lastRenderedSize else {
            return
        }

        reload(profile: profile, keepSelection: true)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let button = button(at: point), let config = profile.buttons[button.rawValue] else {
            highlight(nil)
            return
        }

        highlight(button)
        onButtonSelected?(button)
        dragButton = button
        dragStartMouse = point

        let width = bounds.width
        let height = bounds.height
        dragStartButtonCenter = CGPoint(x: CGFloat(config.x) * width, y: CGFloat(config.y) * height)
        dragStartButtonSize = CGSize(width: CGFloat(config.width) * width, height: CGFloat(config.height) * height)
        dragMode = isOnHandle(point, for: button) ? .resizeBottomRight : .move
    }

    override func mouseDragged(with event: NSEvent) {
        guard let button = dragButton else {
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        let deltaX = point.x - dragStartMouse.x
        let deltaY = point.y - dragStartMouse.y
        let width = bounds.width
        let height = bounds.height

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        switch dragMode {
        case .move:
            let nextX = (dragStartButtonCenter.x + deltaX).clamped(to: 0 ... width)
            let nextY = (dragStartButtonCenter.y + deltaY).clamped(to: 0 ... height)

            if let buttonLayer = buttonLayers[button] {
                buttonLayer.position = CGPoint(x: nextX, y: nextY)
                updateHandleFrame(for: button, buttonLayer: buttonLayer)
            }

            onButtonMoved?(button, nextX / width, nextY / height)

        case .resizeBottomRight:
            let resizeCenter = dragStartButtonCenter
            let maxWidth = min(resizeCenter.x * 2, (width - resizeCenter.x) * 2)
            let maxHeight = min(resizeCenter.y * 2, (height - resizeCenter.y) * 2)
            let newWidth = (dragStartButtonSize.width + deltaX).clamped(to: 20 ... max(20, maxWidth))
            let newHeight = (dragStartButtonSize.height - deltaY).clamped(to: 14 ... max(14, maxHeight))

            if let buttonLayer = buttonLayers[button] {
                let center = buttonLayer.position
                buttonLayer.bounds = CGRect(origin: .zero, size: CGSize(width: newWidth, height: newHeight))
                buttonLayer.position = center

                if let textLayer = buttonLayer.sublayers?.first {
                    textLayer.frame = buttonLayer.bounds
                }

                updateHandleFrame(for: button, buttonLayer: buttonLayer)
            }

            onButtonResized?(button, newWidth / width, newHeight / height)
        }

        CATransaction.commit()
    }

    override func mouseUp(with event: NSEvent) {
        dragButton = nil
    }

    private func button(at point: CGPoint) -> GamepadButton? {
        let width = bounds.width
        let height = bounds.height

        for button in GamepadButton.allCases {
            guard let config = profile.buttons[button.rawValue], config.enabled else {
                continue
            }

            let centerX = CGFloat(config.x) * width
            let centerY = CGFloat(config.y) * height
            let buttonWidth = CGFloat(config.width) * width
            let buttonHeight = CGFloat(config.height) * height
            let frame = CGRect(
                x: centerX - (buttonWidth / 2),
                y: centerY - (buttonHeight / 2),
                width: buttonWidth,
                height: buttonHeight
            )

            if frame.contains(point) {
                return button
            }
        }

        return nil
    }

    private func isOnHandle(_ point: CGPoint, for button: GamepadButton) -> Bool {
        guard let handleLayer = handleLayers[button] else {
            return false
        }

        return !handleLayer.isHidden && handleLayer.frame.contains(point)
    }

    private func highlight(_ button: GamepadButton?) {
        buttonLayers.values.forEach {
            $0.borderWidth = 0
            $0.shadowOpacity = 0
        }
        handleLayers.values.forEach { $0.isHidden = true }

        guard let button, let buttonLayer = buttonLayers[button] else {
            selectedButton = nil
            return
        }

        buttonLayer.borderWidth = 2
        buttonLayer.borderColor = NSColor.white.cgColor
        buttonLayer.shadowOpacity = 0.6
        buttonLayer.shadowColor = NSColor.white.cgColor
        buttonLayer.shadowRadius = 4
        buttonLayer.shadowOffset = .zero
        handleLayers[button]?.isHidden = false
        selectedButton = button
    }

    private func updateHandleFrame(for button: GamepadButton, buttonLayer: CALayer) {
        guard let handleLayer = handleLayers[button] else {
            return
        }

        handleLayer.frame = CGRect(
            x: buttonLayer.frame.maxX - handleSize,
            y: buttonLayer.frame.minY,
            width: handleSize,
            height: handleSize
        )
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
