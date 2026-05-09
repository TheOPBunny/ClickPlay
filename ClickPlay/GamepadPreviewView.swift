import Cocoa

/// Drawable editor object derived from ButtonConfig, with selection state added for canvas rendering.
struct CanvasButtonObject {
    let id: GamepadButton
    var frame: CGRect
    var label: String
    var colorHex: String
    var labelFontSize: Double
    var labelBold: Bool
    var labelItalic: Bool
    var labelColorHex: String
    var shape: ButtonShape
    var type: ButtonType
    var systemEvent: SystemEvent?
    var systemEventIconSize: SystemEventIconSize
    var isEnabled: Bool
    var isSelected: Bool
}

/// Lightweight group projection used by the preview for group selection and drag/resize bounds.
struct CanvasButtonGroupObject {
    let id: UUID
    var name: String
    var memberIDs: [GamepadButton]
}

/// Normalized geometry edits reported back to the editor so snapping and undo can stay model-based.
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

struct CanvasAlignmentGuide: Equatable {
    enum Orientation {
        case vertical
        case horizontal
    }

    var orientation: Orientation
    var position: CGFloat
}

struct CanvasGeometryChangeResult {
    var geometries: [GamepadButton: ButtonEditorGeometry]
    var guides: [CanvasAlignmentGuide]
}

enum ResizeCorner: CaseIterable {
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

enum CanvasDragState {
    case none
    case move(ids: Set<GamepadButton>, startFrames: [GamepadButton: CGRect], startMouse: CGPoint)
    case resize(id: GamepadButton, corner: ResizeCorner, startFrame: CGRect, startMouse: CGPoint)
    case moveGroup(id: UUID, startFrames: [GamepadButton: CGRect], startMouse: CGPoint)
    case resizeGroup(id: UUID, corner: ResizeCorner, startBounds: CGRect, startFrames: [GamepadButton: CGRect], startMouse: CGPoint)
    case marqueeSelect(start: CGPoint, current: CGPoint)
}

/// Live editor preview that supports selection, dragging, resizing, marquee selection, and alignment guides.
final class GamepadPreviewView: NSView {

    var onSelectionChanged: ((Set<GamepadButton>, UUID?) -> Void)?
    var onGeometryChanged: (([GamepadButton: ButtonEditorGeometry]) -> CanvasGeometryChangeResult)?
    var onGeometryChangeCompleted: ((_ before: [GamepadButton: CGRect], _ after: [GamepadButton: CGRect]) -> Void)?
    var maximumWorkspaceSize = CGSize(width: 1000, height: 1000)
    var workspaceOrigin = CGPoint.zero {
        didSet {
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
        }
    }
    var usesCenteredOrigin = false {
        didSet { needsDisplay = true }
    }

    // Rendered canvas objects are intentionally separate from Profile so in-progress geometry can be previewed safely.
    private var objects: [CanvasButtonObject] = []
    private var groups: [CanvasButtonGroupObject] = []
    private var selectedIDs = Set<GamepadButton>()
    private var selectedGroupID: UUID?
    private var dragState: CanvasDragState = .none
    private var currentDragStartFrames: [GamepadButton: CGRect] = [:]
    private var alignmentGuides: [CanvasAlignmentGuide] = []

    private let handleSize: CGFloat = 8

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        postsFrameChangedNotifications = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    func reload(objects: [CanvasButtonObject], groups: [CanvasButtonGroupObject], keepSelection: Bool) {
        let retainedSelection = keepSelection ? selectedIDs : []
        let retainedGroupID = keepSelection ? selectedGroupID : nil
        self.objects = objects
        self.groups = groups
        selectedIDs = Set(objects.map(\.id)).intersection(retainedSelection)
        if let retainedGroupID, group(for: retainedGroupID) != nil {
            selectedGroupID = retainedGroupID
        } else {
            selectedGroupID = nil
        }
        syncObjectSelection()
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    func reload(objects: [CanvasButtonObject], keepSelection: Bool) {
        reload(objects: objects, groups: groups, keepSelection: keepSelection)
    }

    func syncObject(_ object: CanvasButtonObject) {
        guard let index = objects.firstIndex(where: { $0.id == object.id }) else {
            return
        }

        var nextObject = object
        nextObject.isSelected = selectedIDs.contains(object.id)
        objects[index] = nextObject
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    func select(button: GamepadButton) {
        guard objects.contains(where: { $0.id == button && $0.isEnabled }) else {
            setSelection([])
            return
        }

        setSelection([button])
    }

    func select(buttons: Set<GamepadButton>) {
        setSelection(buttons)
    }

    func select(group id: UUID?) {
        setGroupSelection(id)
    }

    func currentSelection() -> Set<GamepadButton> {
        selectedIDs
    }

    func currentGroupSelection() -> UUID? {
        selectedGroupID
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        for guide in alignmentGuides {
            drawAlignmentGuide(guide)
        }

        for object in objects where object.isEnabled {
            drawButton(object)
        }

        if let selectedGroupID,
           let bounds = groupBounds(for: selectedGroupID).map(canvasFrame(for:)) {
            drawSelectedGroup(in: bounds)
        }

        if case let .marqueeSelect(start, current) = dragState {
            drawMarquee(from: start, to: current)
        }
    }

    override func resetCursorRects() {
        super.resetCursorRects()

        if let selectedGroupID,
           let bounds = groupBounds(for: selectedGroupID).map(canvasFrame(for:)) {
            for corner in ResizeCorner.allCases {
                addCursorRect(handleRect(for: corner, objectFrame: bounds), cursor: corner.cursor)
            }
            return
        }

        if selectedIDs.count == 1,
           let selectedID = selectedIDs.first,
           groupID(containing: selectedID) == nil,
           let object = object(for: selectedID) {
            for corner in ResizeCorner.allCases {
                addCursorRect(handleRect(for: corner, objectFrame: canvasFrame(for: object.frame)), cursor: corner.cursor)
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let canvasPoint = convert(event.locationInWindow, from: nil)
        let modelPoint = modelPoint(forCanvasPoint: canvasPoint)
        let isCommandClick = event.modifierFlags.contains(.command)

        if let handleHit = groupResizeHandle(atCanvasPoint: canvasPoint),
           let bounds = groupBounds(for: handleHit.groupID) {
            let memberFrames = groupMemberFrames(for: handleHit.groupID)
            setGroupSelection(handleHit.groupID)
            currentDragStartFrames = memberFrames
            dragState = .resizeGroup(
                id: handleHit.groupID,
                corner: handleHit.corner,
                startBounds: bounds,
                startFrames: memberFrames,
                startMouse: modelPoint
            )
            return
        }

        if let handleHit = resizeHandle(atCanvasPoint: canvasPoint), let object = object(for: handleHit.button) {
            setSelection([handleHit.button])
            currentDragStartFrames = [handleHit.button: object.frame]
            dragState = .resize(
                id: handleHit.button,
                corner: handleHit.corner,
                startFrame: object.frame,
                startMouse: modelPoint
            )
            return
        }

        if event.clickCount >= 2,
           let button = button(at: modelPoint),
           groupID(containing: button) != nil {
            setSelection([button])
            return
        }

        if isCommandClick, let button = button(at: modelPoint) {
            if let groupID = groupID(containing: button) {
                setGroupSelection(groupID)
                return
            }

            toggleSelection(button)
            return
        }

        if let selectedGroupID,
           let button = button(at: modelPoint),
           group(for: selectedGroupID)?.memberIDs.contains(button) == true {
            beginGroupMove(groupID: selectedGroupID, startMouse: modelPoint)
            return
        }

        if let selectedGroupID,
           let bounds = groupBounds(for: selectedGroupID),
           bounds.contains(modelPoint) {
            beginGroupMove(groupID: selectedGroupID, startMouse: modelPoint)
            return
        }

        if let selectedHit = button(at: modelPoint, restrictedTo: selectedIDs) {
            if let groupID = groupID(containing: selectedHit) {
                setGroupSelection(groupID)
                beginGroupMove(groupID: groupID, startMouse: modelPoint)
                return
            }

            beginMove(button: selectedHit, startMouse: modelPoint)
            return
        }

        if let button = button(at: modelPoint) {
            if let groupID = groupID(containing: button) {
                setGroupSelection(groupID)
                beginGroupMove(groupID: groupID, startMouse: modelPoint)
                return
            }

            setSelection([button])
            beginMove(button: button, startMouse: modelPoint)
            return
        }

        if let groupID = groupID(at: modelPoint) {
            setGroupSelection(groupID)
            beginGroupMove(groupID: groupID, startMouse: modelPoint)
            return
        }

        setSelection([])
        currentDragStartFrames = [:]
        alignmentGuides = []
        dragState = .marqueeSelect(start: canvasPoint, current: canvasPoint)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let canvasPoint = convert(event.locationInWindow, from: nil)
        let modelPoint = modelPoint(forCanvasPoint: canvasPoint)

        switch dragState {
        case .none:
            return

        case let .move(ids, startFrames, startMouse):
            let delta = CGPoint(x: modelPoint.x - startMouse.x, y: modelPoint.y - startMouse.y)
            var proposedGeometries: [GamepadButton: ButtonEditorGeometry] = [:]

            for id in ids {
                guard let startFrame = startFrames[id] else {
                    continue
                }

                let proposedFrame = startFrame.offsetBy(dx: delta.x, dy: delta.y)
                proposedGeometries[id] = ButtonEditorGeometry(
                    centerX: proposedFrame.midX,
                    centerY: proposedFrame.midY,
                    width: proposedFrame.width,
                    height: proposedFrame.height,
                    anchoredResize: nil
                )
            }

            applyGeometryChange(proposedGeometries)

        case let .resize(id, corner, startFrame, startMouse):
            let deltaX = modelPoint.x - startMouse.x
            let deltaY = modelPoint.y - startMouse.y
            let minimumSize = object(for: id).map { minimumEditorSize(for: $0.type) } ?? minimumEditorSize(for: .keyboard)
            let geometry = resizedGeometry(
                startFrame: startFrame,
                corner: corner,
                deltaX: deltaX,
                deltaY: deltaY,
                minimumSize: minimumSize
            )
            applyGeometryChange([id: geometry])

        case let .moveGroup(_, startFrames, startMouse):
            let delta = CGPoint(x: modelPoint.x - startMouse.x, y: modelPoint.y - startMouse.y)
            var proposedGeometries: [GamepadButton: ButtonEditorGeometry] = [:]

            for (id, startFrame) in startFrames {
                let proposedFrame = startFrame.offsetBy(dx: delta.x, dy: delta.y)
                proposedGeometries[id] = ButtonEditorGeometry(
                    centerX: proposedFrame.midX,
                    centerY: proposedFrame.midY,
                    width: proposedFrame.width,
                    height: proposedFrame.height,
                    anchoredResize: nil
                )
            }

            applyGeometryChange(proposedGeometries)

        case let .resizeGroup(_, corner, startBounds, startFrames, startMouse):
            let deltaX = modelPoint.x - startMouse.x
            let deltaY = modelPoint.y - startMouse.y
            let resizedBounds = frameForGeometry(resizedGeometry(
                startFrame: startBounds,
                corner: corner,
                deltaX: deltaX,
                deltaY: deltaY,
                minimumSize: CGSize(width: 24, height: 24)
            ))
            applyGeometryChange(scaledGroupGeometries(
                startBounds: startBounds,
                resizedBounds: resizedBounds,
                startFrames: startFrames
            ))

        case let .marqueeSelect(start, _):
            dragState = .marqueeSelect(start: start, current: canvasPoint)
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        switch dragState {
        case .move, .resize, .moveGroup, .resizeGroup:
            let afterFrames = currentDragStartFrames.keys.reduce(into: [GamepadButton: CGRect]()) { result, id in
                guard let object = object(for: id) else {
                    return
                }

                result[id] = object.frame
            }

            if afterFrames != currentDragStartFrames {
                onGeometryChangeCompleted?(currentDragStartFrames, afterFrames)
            }

        case let .marqueeSelect(start, current):
            setSelection(buttonsIntersectingMarquee(from: start, to: current))

        case .none:
            break
        }

        currentDragStartFrames = [:]
        alignmentGuides = []
        dragState = .none
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        let canvasPoint = convert(event.locationInWindow, from: nil)
        if let hit = groupResizeHandle(atCanvasPoint: canvasPoint) {
            hit.corner.cursor.set()
        } else if let hit = resizeHandle(atCanvasPoint: canvasPoint) {
            hit.corner.cursor.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    private func beginMove(button: GamepadButton, startMouse: CGPoint) {
        let ids = selectedIDs.contains(button) ? selectedIDs : [button]
        let startFrames = ids.reduce(into: [GamepadButton: CGRect]()) { result, id in
            guard let object = object(for: id) else {
                return
            }

            result[id] = object.frame
        }

        currentDragStartFrames = startFrames
        dragState = .move(ids: ids, startFrames: startFrames, startMouse: startMouse)
    }

    private func beginGroupMove(groupID: UUID, startMouse: CGPoint) {
        let startFrames = groupMemberFrames(for: groupID)
        guard !startFrames.isEmpty else {
            return
        }

        currentDragStartFrames = startFrames
        dragState = .moveGroup(id: groupID, startFrames: startFrames, startMouse: startMouse)
    }

    private func applyGeometryChange(_ proposedGeometries: [GamepadButton: ButtonEditorGeometry]) {
        let result = onGeometryChanged?(proposedGeometries) ?? CanvasGeometryChangeResult(
            geometries: proposedGeometries,
            guides: []
        )
        let appliedGeometries = result.geometries
        alignmentGuides = result.guides

        for (id, geometry) in appliedGeometries {
            guard let index = objects.firstIndex(where: { $0.id == id }) else {
                continue
            }

            objects[index].frame = CGRect(
                x: geometry.centerX - (geometry.width / 2),
                y: geometry.centerY - (geometry.height / 2),
                width: geometry.width,
                height: geometry.height
            )
        }

        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    private func setSelection(_ selection: Set<GamepadButton>) {
        selectedIDs = Set(objects.map(\.id)).intersection(selection)
        selectedGroupID = nil
        syncObjectSelection()
        onSelectionChanged?(selectedIDs, selectedGroupID)
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    private func setGroupSelection(_ groupID: UUID?) {
        guard let groupID, group(for: groupID) != nil else {
            selectedGroupID = nil
            selectedIDs = []
            syncObjectSelection()
            onSelectionChanged?(selectedIDs, selectedGroupID)
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
            return
        }

        selectedGroupID = groupID
        selectedIDs = []
        syncObjectSelection()
        onSelectionChanged?(selectedIDs, selectedGroupID)
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    private func toggleSelection(_ button: GamepadButton) {
        var nextSelection = selectedIDs
        if nextSelection.contains(button) {
            nextSelection.remove(button)
        } else {
            nextSelection.insert(button)
        }
        setSelection(nextSelection)
    }

    private func syncObjectSelection() {
        for index in objects.indices {
            objects[index].isSelected = selectedIDs.contains(objects[index].id)
        }
    }

    private func object(for id: GamepadButton) -> CanvasButtonObject? {
        objects.first { $0.id == id && $0.isEnabled }
    }

    private func group(for id: UUID) -> CanvasButtonGroupObject? {
        groups.first { $0.id == id }
    }

    private func groupID(containing button: GamepadButton) -> UUID? {
        groups.first { $0.memberIDs.contains(button) }?.id
    }

    private func groupID(at point: CGPoint) -> UUID? {
        for group in groups.reversed() {
            guard let bounds = groupBounds(for: group.id), bounds.contains(point) else {
                continue
            }

            return group.id
        }

        return nil
    }

    private func groupMemberFrames(for groupID: UUID) -> [GamepadButton: CGRect] {
        guard let group = group(for: groupID) else {
            return [:]
        }

        return group.memberIDs.reduce(into: [GamepadButton: CGRect]()) { result, id in
            guard let object = object(for: id) else {
                return
            }

            result[id] = object.frame
        }
    }

    private func groupBounds(for groupID: UUID) -> CGRect? {
        let frames = groupMemberFrames(for: groupID).values
        return frames.reduce(nil) { partial, frame in
            partial?.union(frame) ?? frame
        }
    }

    private func button(at point: CGPoint, restrictedTo ids: Set<GamepadButton>? = nil) -> GamepadButton? {
        for object in objects.reversed() where object.isEnabled {
            if let ids, !ids.contains(object.id) {
                continue
            }

            if objectContainsPoint(object, point: point) {
                return object.id
            }
        }

        return nil
    }

    private func buttonsIntersectingMarquee(from start: CGPoint, to current: CGPoint) -> Set<GamepadButton> {
        let marqueeRect = CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )

        guard marqueeRect.width > 1, marqueeRect.height > 1 else {
            return []
        }

        return Set(objects.compactMap { object in
            guard object.isEnabled, canvasFrame(for: object.frame).intersects(marqueeRect) else {
                return nil
            }
            return object.id
        })
    }

    private func resizeHandle(atCanvasPoint point: CGPoint) -> (button: GamepadButton, corner: ResizeCorner)? {
        guard selectedIDs.count == 1, let selectedID = selectedIDs.first, let object = object(for: selectedID) else {
            return nil
        }
        guard groupID(containing: selectedID) == nil else {
            return nil
        }

        let canvasFrame = canvasFrame(for: object.frame)
        for corner in ResizeCorner.allCases where handleRect(for: corner, objectFrame: canvasFrame).contains(point) {
            return (selectedID, corner)
        }

        return nil
    }

    private func groupResizeHandle(atCanvasPoint point: CGPoint) -> (groupID: UUID, corner: ResizeCorner)? {
        guard let selectedGroupID,
              let bounds = groupBounds(for: selectedGroupID) else {
            return nil
        }

        let canvasBounds = canvasFrame(for: bounds)
        for corner in ResizeCorner.allCases where handleRect(for: corner, objectFrame: canvasBounds).contains(point) {
            return (selectedGroupID, corner)
        }

        return nil
    }

    private func scaledGroupGeometries(
        startBounds: CGRect,
        resizedBounds: CGRect,
        startFrames: [GamepadButton: CGRect]
    ) -> [GamepadButton: ButtonEditorGeometry] {
        guard startBounds.width > 0, startBounds.height > 0 else {
            return [:]
        }

        let scaleX = resizedBounds.width / startBounds.width
        let scaleY = resizedBounds.height / startBounds.height

        return startFrames.reduce(into: [GamepadButton: ButtonEditorGeometry]()) { result, entry in
            let (button, startFrame) = entry
            let minimumSize = object(for: button).map { minimumEditorSize(for: $0.type) } ?? minimumEditorSize(for: .keyboard)
            let width = max(minimumSize.width, startFrame.width * scaleX)
            let height = max(minimumSize.height, startFrame.height * scaleY)
            let x = resizedBounds.minX + ((startFrame.minX - startBounds.minX) * scaleX)
            let y = resizedBounds.minY + ((startFrame.minY - startBounds.minY) * scaleY)

            result[button] = ButtonEditorGeometry(
                centerX: x + (width / 2),
                centerY: y + (height / 2),
                width: width,
                height: height,
                anchoredResize: nil
            )
        }
    }

    private func resizedGeometry(
        startFrame: CGRect,
        corner: ResizeCorner,
        deltaX: CGFloat,
        deltaY: CGFloat,
        minimumSize: CGSize
    ) -> ButtonEditorGeometry {
        let minWidth = minimumSize.width
        let minHeight = minimumSize.height

        switch corner {
        case .topLeft:
            let width = max(minWidth, startFrame.width - deltaX)
            let height = max(minHeight, startFrame.height + deltaY)
            return ButtonEditorGeometry(
                centerX: startFrame.maxX - (width / 2),
                centerY: startFrame.minY + (height / 2),
                width: width,
                height: height,
                anchoredResize: AnchoredButtonResize(
                    anchorX: startFrame.maxX,
                    anchorY: startFrame.minY,
                    resizesFromLeft: true,
                    resizesFromBottom: false
                )
            )

        case .topRight:
            let width = max(minWidth, startFrame.width + deltaX)
            let height = max(minHeight, startFrame.height + deltaY)
            return ButtonEditorGeometry(
                centerX: startFrame.minX + (width / 2),
                centerY: startFrame.minY + (height / 2),
                width: width,
                height: height,
                anchoredResize: AnchoredButtonResize(
                    anchorX: startFrame.minX,
                    anchorY: startFrame.minY,
                    resizesFromLeft: false,
                    resizesFromBottom: false
                )
            )

        case .bottomLeft:
            let width = max(minWidth, startFrame.width - deltaX)
            let height = max(minHeight, startFrame.height - deltaY)
            return ButtonEditorGeometry(
                centerX: startFrame.maxX - (width / 2),
                centerY: startFrame.maxY - (height / 2),
                width: width,
                height: height,
                anchoredResize: AnchoredButtonResize(
                    anchorX: startFrame.maxX,
                    anchorY: startFrame.maxY,
                    resizesFromLeft: true,
                    resizesFromBottom: true
                )
            )

        case .bottomRight:
            let width = max(minWidth, startFrame.width + deltaX)
            let height = max(minHeight, startFrame.height - deltaY)
            return ButtonEditorGeometry(
                centerX: startFrame.minX + (width / 2),
                centerY: startFrame.maxY - (height / 2),
                width: width,
                height: height,
                anchoredResize: AnchoredButtonResize(
                    anchorX: startFrame.minX,
                    anchorY: startFrame.maxY,
                    resizesFromLeft: false,
                    resizesFromBottom: true
                )
            )
        }
    }

    private func frameForGeometry(_ geometry: ButtonEditorGeometry) -> CGRect {
        CGRect(
            x: geometry.centerX - (geometry.width / 2),
            y: geometry.centerY - (geometry.height / 2),
            width: geometry.width,
            height: geometry.height
        )
    }

    private func drawButton(_ object: CanvasButtonObject) {
        let canvasFrame = canvasFrame(for: object.frame)
        if object.type == .joystick {
            drawJoystick(object, in: canvasFrame)
            return
        }

        let path = buttonPath(for: object.shape, in: canvasFrame)
        NSColor(hex: object.colorHex).withAlphaComponent(0.85).setFill()
        path.fill()

        if let systemEvent = object.systemEvent {
            drawSystemEventSymbol(systemEvent, for: object, in: canvasFrame)
        } else {
            drawLabel(for: object, in: canvasFrame)
        }

        guard object.isSelected else {
            return
        }

        NSColor.white.setStroke()
        path.lineWidth = 2
        path.stroke()

        drawSelectionGlow(for: object.shape, in: canvasFrame)

        if groupID(containing: object.id) == nil {
            for corner in ResizeCorner.allCases {
                drawResizeHandle(handleRect(for: corner, objectFrame: canvasFrame))
            }
        }
    }

    private func drawJoystick(_ object: CanvasButtonObject, in frame: CGRect) {
        let inset = max(
            CGFloat(ButtonSizing.joystickMinimumOuterInset),
            min(frame.width, frame.height) * CGFloat(ButtonSizing.joystickOuterInsetFraction)
        )
        let outerRect = frame.insetBy(dx: inset, dy: inset)
        let path = NSBezierPath(roundedRect: outerRect, xRadius: 8, yRadius: 8)
        NSColor(hex: object.colorHex).withAlphaComponent(0.36).setFill()
        path.fill()
        NSColor.white.withAlphaComponent(0.35).setStroke()
        path.lineWidth = 2
        path.stroke()

        let knobDiameter = joystickKnobDiameter(for: frame.size)
        let knobRect = CGRect(
            x: frame.midX - knobDiameter / 2,
            y: frame.midY - knobDiameter / 2,
            width: knobDiameter,
            height: knobDiameter
        )
        let knobPath = NSBezierPath(ovalIn: knobRect)
        NSColor(hex: object.colorHex).withAlphaComponent(0.88).setFill()
        knobPath.fill()
        NSColor.white.withAlphaComponent(0.72).setStroke()
        knobPath.lineWidth = 1
        knobPath.stroke()

        drawLabel(for: object, in: frame)

        guard object.isSelected else {
            return
        }

        NSColor.white.setStroke()
        path.lineWidth = 2
        path.stroke()
        drawSelectionGlow(for: .roundedRectangle, in: outerRect)

        for corner in ResizeCorner.allCases {
            drawResizeHandle(handleRect(for: corner, objectFrame: frame))
        }
    }

    private func drawLabel(for object: CanvasButtonObject, in frame: CGRect) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        let fontManager = NSFontManager.shared
        var font = NSFont.systemFont(ofSize: object.labelFontSize)

        if object.labelBold {
            font = fontManager.convert(font, toHaveTrait: .boldFontMask)
        }
        if object.labelItalic {
            font = fontManager.convert(font, toHaveTrait: .italicFontMask)
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(hex: object.labelColorHex),
            .paragraphStyle: paragraphStyle,
        ]
        let attributedLabel = NSAttributedString(string: object.label, attributes: attributes)
        let measuredSize = attributedLabel.size()
        let drawRect = CGRect(
            x: frame.minX + 2,
            y: frame.midY - (ceil(measuredSize.height) / 2) - 1,
            width: max(0, frame.width - 4),
            height: ceil(measuredSize.height)
        )
        attributedLabel.draw(in: drawRect)
    }

    private func drawSystemEventSymbol(_ event: SystemEvent, for object: CanvasButtonObject, in frame: CGRect) {
        let tint = ButtonConfig.systemEventSymbolColor(for: object.colorHex)
        let symbolSize = max(10, min(frame.width, frame.height) * object.systemEventIconSize.symbolScale)
        let fallbackObject = CanvasButtonObject(
            id: object.id,
            frame: object.frame,
            label: event.fallbackSymbol,
            colorHex: object.colorHex,
            labelFontSize: Double(symbolSize),
            labelBold: true,
            labelItalic: false,
            labelColorHex: tint.hexString,
            shape: object.shape,
            type: object.type,
            systemEvent: nil,
            systemEventIconSize: object.systemEventIconSize,
            isEnabled: object.isEnabled,
            isSelected: object.isSelected
        )
        drawLabel(for: fallbackObject, in: frame)
    }

    private func drawSelectionGlow(for shape: ButtonShape, in frame: CGRect) {
        NSGraphicsContext.saveGraphicsState()
        NSColor.white.withAlphaComponent(0.22).setStroke()
        let glowPath = buttonPath(for: shape, in: frame.insetBy(dx: -2, dy: -2))
        glowPath.lineWidth = 3
        glowPath.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawSelectedGroup(in frame: CGRect) {
        let path = NSBezierPath(roundedRect: frame.insetBy(dx: -4, dy: -4), xRadius: 8, yRadius: 8)
        NSColor.systemBlue.withAlphaComponent(0.08).setFill()
        path.fill()
        NSColor.systemBlue.withAlphaComponent(0.95).setStroke()
        path.lineWidth = 2
        path.stroke()

        for corner in ResizeCorner.allCases {
            drawResizeHandle(handleRect(for: corner, objectFrame: frame))
        }
    }

    private func buttonPath(for shape: ButtonShape, in frame: CGRect) -> NSBezierPath {
        switch shape {
        case .roundedRectangle:
            return NSBezierPath(roundedRect: frame, xRadius: 6, yRadius: 6)
        case .square:
            return NSBezierPath(rect: frame)
        case .oval:
            return NSBezierPath(ovalIn: frame)
        }
    }

    private func objectContainsPoint(_ object: CanvasButtonObject, point: CGPoint) -> Bool {
        guard object.frame.contains(point) else {
            return false
        }

        if object.type == .joystick {
            let inset = max(
                CGFloat(ButtonSizing.joystickMinimumOuterInset),
                min(object.frame.width, object.frame.height) * CGFloat(ButtonSizing.joystickOuterInsetFraction)
            )
            return object.frame.insetBy(dx: inset, dy: inset).contains(point)
        }

        switch object.shape {
        case .roundedRectangle, .square:
            return true
        case .oval:
            guard object.frame.width > 0, object.frame.height > 0 else {
                return false
            }

            let normalizedX = (point.x - object.frame.midX) / (object.frame.width / 2)
            let normalizedY = (point.y - object.frame.midY) / (object.frame.height / 2)
            return (normalizedX * normalizedX) + (normalizedY * normalizedY) <= 1
        }
    }

    private func minimumEditorSize(for type: ButtonType) -> CGSize {
        let minimumSize = ButtonSizing.minimumSize(for: type)
        return CGSize(width: CGFloat(minimumSize.width), height: CGFloat(minimumSize.height))
    }

    private func joystickKnobDiameter(for size: CGSize) -> CGFloat {
        let shortestSide = min(size.width, size.height)
        guard shortestSide > 0 else {
            return CGFloat(ButtonSizing.joystickMinimumKnobDiameter)
        }

        let scaledDiameter = shortestSide * CGFloat(ButtonSizing.joystickKnobDiameterFraction)
        let boundedDiameter = min(
            max(CGFloat(ButtonSizing.joystickMinimumKnobDiameter), scaledDiameter),
            CGFloat(ButtonSizing.joystickMaximumKnobDiameter)
        )
        return min(boundedDiameter, max(6, shortestSide * 0.45))
    }

    private func drawResizeHandle(_ rect: CGRect) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
        NSColor.white.withAlphaComponent(0.85).setFill()
        path.fill()
        NSColor.black.withAlphaComponent(0.35).setStroke()
        path.lineWidth = 0.5
        path.stroke()
    }

    private func drawAlignmentGuide(_ guide: CanvasAlignmentGuide) {
        let path = NSBezierPath()
        path.lineWidth = 1

        switch guide.orientation {
        case .vertical:
            let x = canvasX(forModelX: guide.position)
            path.move(to: CGPoint(x: x, y: 0))
            path.line(to: CGPoint(x: x, y: bounds.height))
        case .horizontal:
            let y = canvasY(forModelY: guide.position)
            path.move(to: CGPoint(x: 0, y: y))
            path.line(to: CGPoint(x: bounds.width, y: y))
        }

        NSColor.systemYellow.withAlphaComponent(0.85).setStroke()
        path.stroke()
    }

    private func drawMarquee(from start: CGPoint, to current: CGPoint) {
        let rect = CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
        guard rect.width > 1, rect.height > 1 else {
            return
        }

        NSColor.white.withAlphaComponent(0.08).setFill()
        NSBezierPath(rect: rect).fill()
        NSColor.white.withAlphaComponent(0.45).setStroke()
        let path = NSBezierPath(rect: rect)
        path.lineWidth = 1
        path.stroke()
    }

    private func handleRect(for corner: ResizeCorner, objectFrame: CGRect) -> CGRect {
        let halfHandle = handleSize / 2
        let origin: CGPoint

        switch corner {
        case .topLeft:
            origin = CGPoint(x: objectFrame.minX - halfHandle, y: objectFrame.maxY - halfHandle)
        case .topRight:
            origin = CGPoint(x: objectFrame.maxX - halfHandle, y: objectFrame.maxY - halfHandle)
        case .bottomLeft:
            origin = CGPoint(x: objectFrame.minX - halfHandle, y: objectFrame.minY - halfHandle)
        case .bottomRight:
            origin = CGPoint(x: objectFrame.maxX - halfHandle, y: objectFrame.minY - halfHandle)
        }

        return CGRect(origin: origin, size: CGSize(width: handleSize, height: handleSize))
    }

    private func canvasFrame(for modelFrame: CGRect) -> CGRect {
        var canvasFrame = modelFrame.offsetBy(dx: workspaceOrigin.x, dy: workspaceOrigin.y)
        guard usesCenteredOrigin else {
            return canvasFrame
        }

        canvasFrame = modelFrame.offsetBy(
            dx: maximumWorkspaceSize.width / 2,
            dy: maximumWorkspaceSize.height / 2
        )
        return canvasFrame.offsetBy(dx: workspaceOrigin.x, dy: workspaceOrigin.y)
    }

    private func modelPoint(forCanvasPoint point: CGPoint) -> CGPoint {
        let workspacePoint = CGPoint(
            x: point.x - workspaceOrigin.x,
            y: point.y - workspaceOrigin.y
        )
        guard usesCenteredOrigin else {
            return workspacePoint
        }

        return CGPoint(
            x: workspacePoint.x - (maximumWorkspaceSize.width / 2),
            y: workspacePoint.y - (maximumWorkspaceSize.height / 2)
        )
    }

    private func canvasX(forModelX x: CGFloat) -> CGFloat {
        guard usesCenteredOrigin else {
            return x + workspaceOrigin.x
        }

        return x + (maximumWorkspaceSize.width / 2) + workspaceOrigin.x
    }

    private func canvasY(forModelY y: CGFloat) -> CGFloat {
        guard usesCenteredOrigin else {
            return y + workspaceOrigin.y
        }

        return y + (maximumWorkspaceSize.height / 2) + workspaceOrigin.y
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
