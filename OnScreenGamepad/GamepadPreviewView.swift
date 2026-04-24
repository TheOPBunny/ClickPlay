import Cocoa

final class GamepadPreviewView: NSView {

    var onButtonSelected: ((GamepadButton) -> Void)?
    var onButtonMoved: ((GamepadButton, Double, Double) -> Void)?
    var onButtonResized: ((GamepadButton, Double, Double) -> Void)?
    var maximumWorkspaceSize = CGSize(width: 1000, height: 1000)
    var usesCenteredOrigin = false

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
        layer?.backgroundColor = NSColor.clear.cgColor
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

    func syncConfig(_ config: ButtonConfig, for button: GamepadButton) {
        profile.buttons[button.rawValue] = config
    }

    private func rebuildLayers() {
        buttonLayers.values.forEach { $0.removeFromSuperlayer() }
        handleLayers.values.forEach { $0.removeFromSuperlayer() }
        buttonLayers.removeAll()
        handleLayers.removeAll()

        for button in GamepadButton.allCases {
            guard let config = profile.buttons[button.rawValue], config.enabled else {
                continue
            }

            let center = canvasPoint(forModelPoint: CGPoint(x: config.x, y: config.y))
            let buttonWidth = CGFloat(config.editorWidth > 0 ? config.editorWidth : config.width)
            let buttonHeight = CGFloat(config.editorHeight > 0 ? config.editorHeight : config.height)

            let buttonLayer = CALayer()
            buttonLayer.frame = CGRect(
                x: center.x - (buttonWidth / 2),
                y: center.y - (buttonHeight / 2),
                width: buttonWidth,
                height: buttonHeight
            )
            buttonLayer.backgroundColor = NSColor(hex: config.colorHex).withAlphaComponent(0.85).cgColor
            buttonLayer.cornerRadius = 6

            let textLayer = CATextLayer()
            textLayer.string = NSAttributedString(
                string: config.resolvedDisplayLabel,
                attributes: config.resolvedLabelAttributes
            )
            textLayer.fontSize = config.labelFontSize
            textLayer.alignmentMode = .center
            textLayer.foregroundColor = NSColor.white.cgColor
            textLayer.contentsScale = window?.backingScaleFactor ?? 2
            textLayer.frame = textFrame(in: buttonLayer.bounds, config: config)
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
        let center = canvasPoint(forModelPoint: CGPoint(x: config.x, y: config.y))
        let buttonWidth = CGFloat(config.editorWidth > 0 ? config.editorWidth : config.width)
        let buttonHeight = CGFloat(config.editorHeight > 0 ? config.editorHeight : config.height)

        buttonLayer.frame = CGRect(
            x: center.x - (buttonWidth / 2),
            y: center.y - (buttonHeight / 2),
            width: buttonWidth,
            height: buttonHeight
        )
        buttonLayer.backgroundColor = NSColor(hex: config.colorHex).withAlphaComponent(0.85).cgColor

        if let textLayer = buttonLayer.sublayers?.first as? CATextLayer {
            textLayer.string = NSAttributedString(
                string: config.resolvedDisplayLabel,
                attributes: config.resolvedLabelAttributes
            )
            textLayer.fontSize = config.labelFontSize
            textLayer.contentsScale = window?.backingScaleFactor ?? 2
            textLayer.frame = textFrame(in: buttonLayer.bounds, config: config)
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
        let canvasPoint = convert(event.locationInWindow, from: nil)
        let point = modelPoint(forCanvasPoint: canvasPoint)
        guard let button = button(at: point), let config = profile.buttons[button.rawValue] else {
            highlight(nil)
            return
        }

        highlight(button)
        onButtonSelected?(button)
        dragButton = button
        dragStartMouse = point

        dragStartButtonCenter = CGPoint(x: CGFloat(config.x), y: CGFloat(config.y))
        dragStartButtonSize = CGSize(
            width: CGFloat(config.editorWidth > 0 ? config.editorWidth : config.width),
            height: CGFloat(config.editorHeight > 0 ? config.editorHeight : config.height)
        )
        dragMode = isOnHandle(canvasPoint, for: button) ? .resizeBottomRight : .move
    }

    override func mouseDragged(with event: NSEvent) {
        guard let button = dragButton else {
            return
        }

        let point = modelPoint(forCanvasPoint: convert(event.locationInWindow, from: nil))
        let deltaX = point.x - dragStartMouse.x
        let deltaY = point.y - dragStartMouse.y
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        switch dragMode {
        case .move:
            let halfWidth = dragStartButtonSize.width / 2
            let halfHeight = dragStartButtonSize.height / 2
            let nextX = (dragStartButtonCenter.x + deltaX).clamped(to: permittedCenterXRange(halfWidth: halfWidth))
            let nextY = (dragStartButtonCenter.y + deltaY).clamped(to: permittedCenterYRange(halfHeight: halfHeight))

            if let buttonLayer = buttonLayers[button] {
                buttonLayer.position = canvasPoint(forModelPoint: CGPoint(x: nextX, y: nextY))
                updateHandleFrame(for: button, buttonLayer: buttonLayer)
            }

            onButtonMoved?(button, nextX, nextY)

        case .resizeBottomRight:
            let maxWidth = max(20, maximumWidth(forCenterX: dragStartButtonCenter.x))
            let maxHeight = max(14, maximumHeight(forCenterY: dragStartButtonCenter.y))
            let newWidth = (dragStartButtonSize.width + deltaX).clamped(to: 20 ... maxWidth)
            let newHeight = (dragStartButtonSize.height - deltaY).clamped(to: 14 ... maxHeight)

            if let buttonLayer = buttonLayers[button] {
                let center = buttonLayer.position
                buttonLayer.bounds = CGRect(origin: .zero, size: CGSize(width: newWidth, height: newHeight))
                buttonLayer.position = center

                if
                    let config = profile.buttons[button.rawValue],
                    let textLayer = buttonLayer.sublayers?.first
                {
                    textLayer.frame = textFrame(in: buttonLayer.bounds, config: config)
                }

                updateHandleFrame(for: button, buttonLayer: buttonLayer)
            }

            onButtonResized?(button, newWidth, newHeight)
        }

        CATransaction.commit()
    }

    override func mouseUp(with event: NSEvent) {
        dragButton = nil
    }

    private func button(at point: CGPoint) -> GamepadButton? {
        for button in GamepadButton.allCases {
            guard let config = profile.buttons[button.rawValue], config.enabled else {
                continue
            }

            let centerX = CGFloat(config.x)
            let centerY = CGFloat(config.y)
            let buttonWidth = CGFloat(config.editorWidth > 0 ? config.editorWidth : config.width)
            let buttonHeight = CGFloat(config.editorHeight > 0 ? config.editorHeight : config.height)
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

    private func textFrame(in bounds: CGRect, config: ButtonConfig) -> CGRect {
        let measuredSize = NSString(string: "Ag").size(withAttributes: config.resolvedLabelAttributes)
        let height = ceil(measuredSize.height)
        let y = round((bounds.height - height) / 2) - 1

        return CGRect(x: 2, y: max(0, y), width: max(0, bounds.width - 4), height: height)
    }

    private func canvasPoint(forModelPoint point: CGPoint) -> CGPoint {
        guard usesCenteredOrigin else {
            return point
        }

        return CGPoint(
            x: point.x + (maximumWorkspaceSize.width / 2),
            y: point.y + (maximumWorkspaceSize.height / 2)
        )
    }

    private func modelPoint(forCanvasPoint point: CGPoint) -> CGPoint {
        guard usesCenteredOrigin else {
            return point
        }

        return CGPoint(
            x: point.x - (maximumWorkspaceSize.width / 2),
            y: point.y - (maximumWorkspaceSize.height / 2)
        )
    }

    private func permittedCenterXRange(halfWidth: CGFloat) -> ClosedRange<CGFloat> {
        if usesCenteredOrigin {
            let halfWorkspaceWidth = maximumWorkspaceSize.width / 2
            return (-halfWorkspaceWidth + halfWidth) ... (halfWorkspaceWidth - halfWidth)
        }

        return halfWidth ... (maximumWorkspaceSize.width - halfWidth)
    }

    private func permittedCenterYRange(halfHeight: CGFloat) -> ClosedRange<CGFloat> {
        if usesCenteredOrigin {
            let halfWorkspaceHeight = maximumWorkspaceSize.height / 2
            return (-halfWorkspaceHeight + halfHeight) ... (halfWorkspaceHeight - halfHeight)
        }

        return halfHeight ... (maximumWorkspaceSize.height - halfHeight)
    }

    private func maximumWidth(forCenterX centerX: CGFloat) -> CGFloat {
        if usesCenteredOrigin {
            let halfWorkspaceWidth = maximumWorkspaceSize.width / 2
            return min(halfWorkspaceWidth - centerX, halfWorkspaceWidth + centerX) * 2
        }

        return (maximumWorkspaceSize.width - centerX) * 2
    }

    private func maximumHeight(forCenterY centerY: CGFloat) -> CGFloat {
        if usesCenteredOrigin {
            let halfWorkspaceHeight = maximumWorkspaceSize.height / 2
            return min(halfWorkspaceHeight - centerY, halfWorkspaceHeight + centerY) * 2
        }

        return centerY * 2
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
