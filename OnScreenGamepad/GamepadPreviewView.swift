import Cocoa

struct ButtonEditorGeometry {
    var centerX: Double
    var centerY: Double
    var width: Double
    var height: Double
    var anchoredResize: AnchoredButtonResize?
}

struct AnchoredButtonResize {
    var anchorX: Double
    var anchorY: Double
    var resizesFromLeft: Bool
    var resizesFromBottom: Bool
}

final class GamepadPreviewView: NSView {

    var onButtonSelected: ((GamepadButton) -> Void)?
    var onButtonMoved: ((GamepadButton, Double, Double) -> Void)?
    var onButtonResized: ((GamepadButton, ButtonEditorGeometry) -> ButtonEditorGeometry)?
    var maximumWorkspaceSize = CGSize(width: 1000, height: 1000)
    var usesCenteredOrigin = false

    private var buttonLayers: [GamepadButton: CALayer] = [:]
    private var handleLayers: [GamepadButton: [ResizeCorner: CALayer]] = [:]
    private var selectedButton: GamepadButton?
    private var profile = ProfileStore.shared.activeProfile
    private var lastRenderedSize: CGSize = .zero

    private enum ResizeCorner: CaseIterable {
        case topLeft
        case topRight
        case bottomLeft
        case bottomRight

        var cursor: NSCursor {
            switch self {
            case .topLeft, .bottomRight:
                return .diagonalResizeNorthWestSouthEast
            case .topRight, .bottomLeft:
                return .diagonalResizeNorthEastSouthWest
            }
        }
    }

    private enum DragMode {
        case move
        case resize(ResizeCorner)
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

    func select(button: GamepadButton) {
        guard let config = profile.buttons[button.rawValue], config.enabled else {
            highlight(nil)
            return
        }

        if buttonLayers[button] == nil {
            let buttonLayer = makeButtonLayer(for: button)
            let handles = makeHandleLayers(for: button)
            update(buttonLayer: buttonLayer, handleLayers: handles, with: config)
        }

        highlight(button)
        onButtonSelected?(button)
    }

    private func rebuildLayers() {
        buttonLayers.values.forEach { $0.removeFromSuperlayer() }
        handleLayers.values.flatMap(\.values).forEach { $0.removeFromSuperlayer() }
        buttonLayers.removeAll()
        handleLayers.removeAll()

        for button in profile.orderedButtonIDs {
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

            let handles = makeHandleLayers(for: button)
            update(buttonLayer: buttonLayer, handleLayers: handles, with: config)
        }
    }

    private func updateExistingLayers() {
        let activeButtons = Set(profile.orderedButtonIDs.filter {
            guard let config = profile.buttons[$0.rawValue] else {
                return false
            }

            return config.enabled
        })

        for button in Array(buttonLayers.keys) where !activeButtons.contains(button) {
            buttonLayers[button]?.removeFromSuperlayer()
            buttonLayers.removeValue(forKey: button)

            handleLayers[button]?.values.forEach { $0.removeFromSuperlayer() }
            handleLayers.removeValue(forKey: button)
        }

        for button in profile.orderedButtonIDs {
            guard let config = profile.buttons[button.rawValue], config.enabled else {
                continue
            }

            let buttonLayer = buttonLayers[button] ?? makeButtonLayer(for: button)
            let handles = handleLayers[button] ?? makeHandleLayers(for: button)
            update(buttonLayer: buttonLayer, handleLayers: handles, with: config)
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

    private func makeHandleLayers(for button: GamepadButton) -> [ResizeCorner: CALayer] {
        let handles = Dictionary(uniqueKeysWithValues: ResizeCorner.allCases.map { corner in
            let handleLayer = CALayer()
            handleLayer.backgroundColor = NSColor.white.withAlphaComponent(0.7).cgColor
            handleLayer.borderColor = NSColor.black.withAlphaComponent(0.35).cgColor
            handleLayer.borderWidth = 0.5
            handleLayer.cornerRadius = 2
            handleLayer.isHidden = true
            layer?.addSublayer(handleLayer)
            return (corner, handleLayer)
        })
        handleLayers[button] = handles
        return handles
    }

    private func update(buttonLayer: CALayer, handleLayers: [ResizeCorner: CALayer], with config: ButtonConfig) {
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

        updateHandleFrames(handleLayers, buttonLayer: buttonLayer)
    }

    override func layout() {
        super.layout()
        guard bounds.size != .zero, bounds.size != lastRenderedSize else {
            return
        }

        reload(profile: profile, keepSelection: true)
    }

    override func resetCursorRects() {
        super.resetCursorRects()

        guard let selectedButton, let handles = handleLayers[selectedButton] else {
            return
        }

        for (corner, handleLayer) in handles where !handleLayer.isHidden {
            addCursorRect(handleLayer.frame, cursor: corner.cursor)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let canvasPoint = convert(event.locationInWindow, from: nil)
        let point = modelPoint(forCanvasPoint: canvasPoint)
        let handleHit = resizeHandle(at: canvasPoint)
        guard let button = handleHit?.button ?? button(at: point), let config = profile.buttons[button.rawValue] else {
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
        if let corner = handleHit?.corner {
            dragMode = .resize(corner)
        } else {
            dragMode = .move
        }
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

        case .resize(let corner):
            let proposedGeometry = resizedGeometry(corner: corner, deltaX: deltaX, deltaY: deltaY)
            let appliedGeometry = onButtonResized?(button, proposedGeometry) ?? proposedGeometry

            if let buttonLayer = buttonLayers[button] {
                buttonLayer.bounds = CGRect(
                    origin: .zero,
                    size: CGSize(width: appliedGeometry.width, height: appliedGeometry.height)
                )
                buttonLayer.position = canvasPoint(
                    forModelPoint: CGPoint(x: appliedGeometry.centerX, y: appliedGeometry.centerY)
                )

                if
                    let config = profile.buttons[button.rawValue],
                    let textLayer = buttonLayer.sublayers?.first
                {
                    textLayer.frame = textFrame(in: buttonLayer.bounds, config: config)
                }

                updateHandleFrames(for: button, buttonLayer: buttonLayer)
            }
        }

        CATransaction.commit()
    }

    override func mouseUp(with event: NSEvent) {
        dragButton = nil
    }

    override func mouseMoved(with event: NSEvent) {
        let canvasPoint = convert(event.locationInWindow, from: nil)
        if let hit = resizeHandle(at: canvasPoint) {
            hit.corner.cursor.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    private func button(at point: CGPoint) -> GamepadButton? {
        for button in profile.orderedButtonIDs {
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

    private func resizeHandle(at point: CGPoint) -> (button: GamepadButton, corner: ResizeCorner)? {
        guard let selectedButton, let handles = handleLayers[selectedButton] else {
            return nil
        }

        for corner in ResizeCorner.allCases {
            guard let handleLayer = handles[corner], !handleLayer.isHidden, handleLayer.frame.contains(point) else {
                continue
            }

            return (selectedButton, corner)
        }

        return nil
    }

    private func highlight(_ button: GamepadButton?) {
        buttonLayers.values.forEach {
            $0.borderWidth = 0
            $0.shadowOpacity = 0
        }
        handleLayers.values.flatMap(\.values).forEach { $0.isHidden = true }

        guard let button, let buttonLayer = buttonLayers[button] else {
            selectedButton = nil
            window?.invalidateCursorRects(for: self)
            return
        }

        buttonLayer.borderWidth = 2
        buttonLayer.borderColor = NSColor.white.cgColor
        buttonLayer.shadowOpacity = 0.6
        buttonLayer.shadowColor = NSColor.white.cgColor
        buttonLayer.shadowRadius = 4
        buttonLayer.shadowOffset = .zero
        handleLayers[button]?.values.forEach { $0.isHidden = false }
        selectedButton = button
        window?.invalidateCursorRects(for: self)
    }

    private func updateHandleFrame(for button: GamepadButton, buttonLayer: CALayer) {
        guard let handles = handleLayers[button] else {
            return
        }

        updateHandleFrames(handles, buttonLayer: buttonLayer)
    }

    private func updateHandleFrames(for button: GamepadButton, buttonLayer: CALayer) {
        guard let handles = handleLayers[button] else {
            return
        }

        updateHandleFrames(handles, buttonLayer: buttonLayer)
    }

    private func updateHandleFrames(_ handles: [ResizeCorner: CALayer], buttonLayer: CALayer) {
        let halfHandle = handleSize / 2
        let frame = buttonLayer.frame

        handles[.topLeft]?.frame = CGRect(
            x: frame.minX - halfHandle,
            y: frame.maxY - halfHandle,
            width: handleSize,
            height: handleSize
        )
        handles[.topRight]?.frame = CGRect(
            x: frame.maxX - halfHandle,
            y: frame.maxY - halfHandle,
            width: handleSize,
            height: handleSize
        )
        handles[.bottomLeft]?.frame = CGRect(
            x: frame.minX - halfHandle,
            y: frame.minY - halfHandle,
            width: handleSize,
            height: handleSize
        )
        handles[.bottomRight]?.frame = CGRect(
            x: frame.maxX - halfHandle,
            y: frame.minY - halfHandle,
            width: handleSize,
            height: handleSize
        )

        window?.invalidateCursorRects(for: self)
    }

    private func resizedGeometry(corner: ResizeCorner, deltaX: CGFloat, deltaY: CGFloat) -> ButtonEditorGeometry {
        let startMinX = dragStartButtonCenter.x - (dragStartButtonSize.width / 2)
        let startMaxX = dragStartButtonCenter.x + (dragStartButtonSize.width / 2)
        let startMinY = dragStartButtonCenter.y - (dragStartButtonSize.height / 2)
        let startMaxY = dragStartButtonCenter.y + (dragStartButtonSize.height / 2)

        let minWidth: CGFloat = 20
        let minHeight: CGFloat = 14

        switch corner {
        case .topLeft:
            let width = max(minWidth, dragStartButtonSize.width - deltaX)
            let height = max(minHeight, dragStartButtonSize.height + deltaY)
            return ButtonEditorGeometry(
                centerX: startMaxX - (width / 2),
                centerY: startMinY + (height / 2),
                width: width,
                height: height,
                anchoredResize: AnchoredButtonResize(
                    anchorX: startMaxX,
                    anchorY: startMinY,
                    resizesFromLeft: true,
                    resizesFromBottom: false
                )
            )
        case .topRight:
            let width = max(minWidth, dragStartButtonSize.width + deltaX)
            let height = max(minHeight, dragStartButtonSize.height + deltaY)
            return ButtonEditorGeometry(
                centerX: startMinX + (width / 2),
                centerY: startMinY + (height / 2),
                width: width,
                height: height,
                anchoredResize: AnchoredButtonResize(
                    anchorX: startMinX,
                    anchorY: startMinY,
                    resizesFromLeft: false,
                    resizesFromBottom: false
                )
            )
        case .bottomLeft:
            let width = max(minWidth, dragStartButtonSize.width - deltaX)
            let height = max(minHeight, dragStartButtonSize.height - deltaY)
            return ButtonEditorGeometry(
                centerX: startMaxX - (width / 2),
                centerY: startMaxY - (height / 2),
                width: width,
                height: height,
                anchoredResize: AnchoredButtonResize(
                    anchorX: startMaxX,
                    anchorY: startMaxY,
                    resizesFromLeft: true,
                    resizesFromBottom: true
                )
            )
        case .bottomRight:
            let width = max(minWidth, dragStartButtonSize.width + deltaX)
            let height = max(minHeight, dragStartButtonSize.height - deltaY)
            return ButtonEditorGeometry(
                centerX: startMinX + (width / 2),
                centerY: startMaxY - (height / 2),
                width: width,
                height: height,
                anchoredResize: AnchoredButtonResize(
                    anchorX: startMinX,
                    anchorY: startMaxY,
                    resizesFromLeft: false,
                    resizesFromBottom: true
                )
            )
        }
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
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

private extension NSCursor {
    static var diagonalResizeNorthWestSouthEast: NSCursor {
        NSCursor.diagonalResizeCursor(angleDegrees: -45)
    }

    static var diagonalResizeNorthEastSouthWest: NSCursor {
        NSCursor.diagonalResizeCursor(angleDegrees: 45)
    }

    static func diagonalResizeCursor(angleDegrees: CGFloat) -> NSCursor {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()

        NSGraphicsContext.current?.imageInterpolation = .high
        let transform = NSAffineTransform()
        transform.translateX(by: size.width / 2, yBy: size.height / 2)
        transform.rotate(byDegrees: angleDegrees)
        transform.translateX(by: -size.width / 2, yBy: -size.height / 2)
        transform.concat()

        let path = NSBezierPath()
        path.lineWidth = 1.8
        path.lineCapStyle = .round
        path.move(to: CGPoint(x: 3, y: 9))
        path.line(to: CGPoint(x: 15, y: 9))
        path.move(to: CGPoint(x: 3, y: 9))
        path.line(to: CGPoint(x: 7, y: 5))
        path.move(to: CGPoint(x: 3, y: 9))
        path.line(to: CGPoint(x: 7, y: 13))
        path.move(to: CGPoint(x: 15, y: 9))
        path.line(to: CGPoint(x: 11, y: 5))
        path.move(to: CGPoint(x: 15, y: 9))
        path.line(to: CGPoint(x: 11, y: 13))
        NSColor.white.setStroke()
        path.stroke()

        image.unlockFocus()
        return NSCursor(image: image, hotSpot: CGPoint(x: size.width / 2, y: size.height / 2))
    }
}
