import Cocoa

final class SidebarToggleButton: NSButton {

    enum Side {
        case left
        case right
    }

    var side: Side = .left {
        didSet { image = makeImage() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        bezelStyle = .texturedRounded
        setButtonType(.momentaryPushIn)
        isBordered = true
        imagePosition = .imageOnly
        image = makeImage()
        toolTip = "Toggle Sidebar"
        translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 26),
            heightAnchor.constraint(equalToConstant: 24),
        ])
    }

    private func makeImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.lockFocus()

        NSColor.controlTextColor.setStroke()

        let outerRect = NSRect(x: 2.5, y: 3.5, width: 13, height: 11)
        let path = NSBezierPath(roundedRect: outerRect, xRadius: 2.2, yRadius: 2.2)
        path.lineWidth = 1.8
        path.stroke()

        let dividerX: CGFloat = side == .left ? 6.5 : 11.5
        let divider = NSBezierPath()
        divider.move(to: CGPoint(x: dividerX, y: 4))
        divider.line(to: CGPoint(x: dividerX, y: 14))
        divider.lineWidth = 1.8
        divider.stroke()

        image.unlockFocus()
        image.isTemplate = true
        return image
    }
}
