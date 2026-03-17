import Cocoa

/// The full gamepad UI — lays out all buttons in a controller-like arrangement.
final class GamepadContentView: NSView {

    // Sizing constants
    private let faceSize  = CGSize(width: 44, height: 44)
    private let dpadSize  = CGSize(width: 40, height: 40)
    private let shldSize  = CGSize(width: 52, height: 32)
    private let menuSize  = CGSize(width: 52, height: 28)
    private let stickSize = CGSize(width: 40, height: 40)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Layout

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        layer?.cornerRadius = 20
        layer?.masksToBounds = true

        // Add a subtle backdrop blur via NSVisualEffectView underneath
        let blur = NSVisualEffectView(frame: bounds)
        blur.autoresizingMask = [.width, .height]
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        addSubview(blur, positioned: .below, relativeTo: nil)

        layoutButtons()
    }

    private func layoutButtons() {
        let W = bounds.width
        let H = bounds.height
        let mid = W / 2

        // ── Shoulder / Trigger row ──────────────────────────────────────────
        addButton(.triggerL,  frame: CGRect(x: 12,        y: H - 40, width: shldSize.width, height: shldSize.height))
        addButton(.shoulderL, frame: CGRect(x: 12,        y: H - 76, width: shldSize.width, height: shldSize.height))
        addButton(.triggerZR, frame: CGRect(x: W - 64,   y: H - 40, width: shldSize.width, height: shldSize.height))
        addButton(.shoulderR, frame: CGRect(x: W - 64,   y: H - 76, width: shldSize.width, height: shldSize.height))

        // ── D-Pad ───────────────────────────────────────────────────────────
        let dpadCX: CGFloat = 82
        let dpadCY: CGFloat = H - 155
        addButton(.dpadUp,    frame: centeredRect(cx: dpadCX,          cy: dpadCY + 44, size: dpadSize))
        addButton(.dpadDown,  frame: centeredRect(cx: dpadCX,          cy: dpadCY - 44, size: dpadSize))
        addButton(.dpadLeft,  frame: centeredRect(cx: dpadCX - 44,     cy: dpadCY,      size: dpadSize))
        addButton(.dpadRight, frame: centeredRect(cx: dpadCX + 44,     cy: dpadCY,      size: dpadSize))

        // ── Center buttons ──────────────────────────────────────────────────
        addButton(.select, frame: centeredRect(cx: mid - 36, cy: H - 105, size: menuSize))
        addButton(.start,  frame: centeredRect(cx: mid + 36, cy: H - 105, size: menuSize))

        // ── Face buttons ────────────────────────────────────────────────────
        let faceCX: CGFloat = W - 82
        let faceCY: CGFloat = H - 155
        addButton(.faceY, frame: centeredRect(cx: faceCX,          cy: faceCY + 44, size: faceSize))
        addButton(.faceA, frame: centeredRect(cx: faceCX,          cy: faceCY - 44, size: faceSize))
        addButton(.faceX, frame: centeredRect(cx: faceCX - 44,     cy: faceCY,      size: faceSize))
        addButton(.faceB, frame: centeredRect(cx: faceCX + 44,     cy: faceCY,      size: faceSize))

        // ── Stick clicks ────────────────────────────────────────────────────
        addButton(.leftStick,  frame: centeredRect(cx: 82,      cy: H - 240, size: stickSize))
        addButton(.rightStick, frame: centeredRect(cx: W - 82,  cy: H - 240, size: stickSize))
    }

    @discardableResult
    private func addButton(_ button: GamepadButton, frame: CGRect) -> GamepadButtonView {
        let v = GamepadButtonView(button: button)
        v.frame = frame
        addSubview(v)
        return v
    }

    private func centeredRect(cx: CGFloat, cy: CGFloat, size: CGSize) -> CGRect {
        CGRect(x: cx - size.width / 2, y: cy - size.height / 2,
               width: size.width, height: size.height)
    }
}
