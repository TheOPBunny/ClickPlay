import Cocoa

final class ButtonEditorViewController: NSViewController {

    private final class PreviewCanvasView: NSView {
        let previewView: GamepadPreviewView
        var showsGrid = true {
            didSet { needsDisplay = true }
        }
        var previewSize = CGSize(width: 420, height: 300) {
            didSet {
                needsLayout = true
            }
        }

        private let canvasPadding: CGFloat = 100

        init(previewView: GamepadPreviewView) {
            self.previewView = previewView
            super.init(frame: .zero)
            wantsLayer = true
            addSubview(previewView)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)

            NSColor(white: 0.13, alpha: 1).setFill()
            dirtyRect.fill()

            guard showsGrid else { return }

            drawGrid(spacing: 10, color: NSColor.white.withAlphaComponent(0.05))
            drawGrid(spacing: 50, color: NSColor.white.withAlphaComponent(0.10))
        }

        override func layout() {
            super.layout()

            let previewFrame = CGRect(
                x: round((bounds.width - previewSize.width) / 2),
                y: round((bounds.height - previewSize.height) / 2),
                width: previewSize.width,
                height: previewSize.height
            )
            previewView.frame = previewFrame
        }

        func updateCanvasSize(visibleSize: CGSize) {
            let nextSize = CGSize(
                width: max(visibleSize.width, previewSize.width + canvasPadding * 2),
                height: max(visibleSize.height, previewSize.height + canvasPadding * 2)
            )

            if frame.size != nextSize {
                frame = CGRect(origin: .zero, size: nextSize)
            }

            needsLayout = true
            needsDisplay = true
        }

        private func drawGrid(spacing: CGFloat, color: NSColor) {
            let path = NSBezierPath()

            var x: CGFloat = 0
            while x <= bounds.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.line(to: CGPoint(x: x, y: bounds.height))
                x += spacing
            }

            var y: CGFloat = 0
            while y <= bounds.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.line(to: CGPoint(x: bounds.width, y: y))
                y += spacing
            }

            color.setStroke()
            path.lineWidth = 1
            path.stroke()
        }
    }

    var onProfileSaved: ((Profile) -> Void)?

    private static let minimumPadWidth = 260.0
    private static let minimumPadHeight = 180.0

    private var profile = ProfileStore.shared.activeProfile

    private let nameField = NSTextField()
    private let opacitySlider = NSSlider()
    private let opacityLabel = NSTextField(labelWithString: "90%")
    private let padWidthField = NSTextField()
    private let padHeightField = NSTextField()
    private let compatibilityModeCheckbox = NSButton(checkboxWithTitle: "Compatibility Mode", target: nil, action: nil)
    private let showGridCheckbox = NSButton(checkboxWithTitle: "Show Grid", target: nil, action: nil)
    private let previewView = GamepadPreviewView()
    private lazy var previewCanvasView = PreviewCanvasView(previewView: previewView)
    private let previewScrollView = NSScrollView()
    private let detailPanel = ButtonDetailPanel()
    private let leftColumn = NSStackView()
    private let hint = NSTextField(
        labelWithString: "Click a button to select it. Drag the button to move it or the corner handle to resize it."
    )

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 980, height: 700))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildLayout()
        load(profile: ProfileStore.shared.activeProfile)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        updatePreviewCanvasLayout()
    }

    func load(profile: Profile) {
        self.profile = profile
        nameField.stringValue = profile.name
        opacitySlider.doubleValue = profile.opacity
        opacityLabel.stringValue = "\(Int(profile.opacity * 100))%"
        padWidthField.stringValue = "\(Int(profile.padWidth))"
        padHeightField.stringValue = "\(Int(profile.padHeight))"
        compatibilityModeCheckbox.state = profile.compatibilityMode ? .on : .off
        updatePreviewCanvasLayout()
        previewView.reload(profile: profile, keepSelection: false)
        detailPanel.clear()
    }

    func refreshFromStoreIfNeeded() {
        if let updatedProfile = ProfileStore.shared.profiles.first(where: { $0.id == profile.id }) {
            load(profile: updatedProfile)
        } else {
            load(profile: ProfileStore.shared.activeProfile)
        }
    }

    private func buildLayout() {
        nameField.placeholderString = "Profile name"
        nameField.bezelStyle = .roundedBezel
        nameField.font = .systemFont(ofSize: 12)

        opacitySlider.minValue = 0.25
        opacitySlider.maxValue = 1.0
        opacitySlider.isContinuous = true
        opacitySlider.target = self
        opacitySlider.action = #selector(opacityMoved)

        padWidthField.bezelStyle = .roundedBezel
        padWidthField.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        padHeightField.bezelStyle = .roundedBezel
        padHeightField.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        compatibilityModeCheckbox.target = self
        compatibilityModeCheckbox.action = #selector(compatibilityModeChanged)
        showGridCheckbox.state = .on
        showGridCheckbox.target = self
        showGridCheckbox.action = #selector(showGridChanged)

        let saveButton = NSButton(title: "Save & Apply", target: self, action: #selector(saveProfile))
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"

        let topBar = NSStackView(views: [
            makeLabel("Name:"),
            nameField,
            makeLabel("  Opacity:"),
            opacitySlider,
            opacityLabel,
            makeLabel("  Size:"),
            padWidthField,
            makeLabel("×"),
            padHeightField,
            compatibilityModeCheckbox,
            showGridCheckbox,
            NSView(),
            saveButton,
        ])
        topBar.orientation = .horizontal
        topBar.alignment = .centerY
        topBar.spacing = 6
        topBar.translatesAutoresizingMaskIntoConstraints = false

        previewScrollView.translatesAutoresizingMaskIntoConstraints = false
        previewScrollView.hasVerticalScroller = true
        previewScrollView.hasHorizontalScroller = true
        previewScrollView.borderType = .bezelBorder
        previewScrollView.drawsBackground = false
        previewScrollView.documentView = previewCanvasView

        previewView.onButtonSelected = { [weak self] button in
            guard
                let self,
                let config = self.profile.buttons[button.rawValue]
            else {
                return
            }

            self.detailPanel.load(button: button, config: config)
        }
        previewView.onButtonMoved = { [weak self] button, x, y in
            guard let self else {
                return
            }

            self.profile.buttons[button.rawValue]?.x = x
            self.profile.buttons[button.rawValue]?.y = y

            if let config = self.profile.buttons[button.rawValue] {
                self.detailPanel.refreshPosition(x: x, y: y, config: config)
            }
        }
        previewView.onButtonResized = { [weak self] button, width, height in
            guard let self else {
                return
            }

            self.profile.buttons[button.rawValue]?.width = width
            self.profile.buttons[button.rawValue]?.height = height
            self.detailPanel.refreshSize(width: width, height: height)
        }

        detailPanel.translatesAutoresizingMaskIntoConstraints = false
        detailPanel.onChanged = { [weak self] button, config in
            guard let self else {
                return
            }

            self.profile.buttons[button.rawValue] = config
            self.previewView.reload(profile: self.profile, keepSelection: true)
        }

        hint.font = .systemFont(ofSize: 10)
        hint.textColor = .secondaryLabelColor
        hint.translatesAutoresizingMaskIntoConstraints = false

        leftColumn.orientation = .vertical
        leftColumn.alignment = .leading
        leftColumn.spacing = 6
        leftColumn.translatesAutoresizingMaskIntoConstraints = false
        leftColumn.addArrangedSubview(previewScrollView)
        leftColumn.addArrangedSubview(hint)

        let preferredPreviewWidthConstraint = leftColumn.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.60)
        preferredPreviewWidthConstraint.priority = .defaultHigh

        [topBar, leftColumn, detailPanel].forEach(view.addSubview(_:))

        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            topBar.heightAnchor.constraint(equalToConstant: 28),
            nameField.widthAnchor.constraint(equalToConstant: 130),
            opacitySlider.widthAnchor.constraint(equalToConstant: 90),
            opacityLabel.widthAnchor.constraint(equalToConstant: 36),
            padWidthField.widthAnchor.constraint(equalToConstant: 52),
            padHeightField.widthAnchor.constraint(equalToConstant: 52),
            leftColumn.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 14),
            leftColumn.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            leftColumn.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
            leftColumn.widthAnchor.constraint(greaterThanOrEqualToConstant: 520),
            leftColumn.widthAnchor.constraint(lessThanOrEqualToConstant: 900),
            preferredPreviewWidthConstraint,
            previewScrollView.widthAnchor.constraint(equalTo: leftColumn.widthAnchor),
            previewScrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 420),
            hint.widthAnchor.constraint(equalTo: leftColumn.widthAnchor),
            detailPanel.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 14),
            detailPanel.leadingAnchor.constraint(equalTo: leftColumn.trailingAnchor, constant: 20),
            detailPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            detailPanel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
            detailPanel.widthAnchor.constraint(greaterThanOrEqualToConstant: 300),
        ])
    }

    private func makeLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12)
        return label
    }

    @objc private func opacityMoved() {
        profile.opacity = opacitySlider.doubleValue
        opacityLabel.stringValue = "\(Int(profile.opacity * 100))%"
    }

    @objc private func compatibilityModeChanged() {
        profile.compatibilityMode = compatibilityModeCheckbox.state == .on
        previewView.reload(profile: profile, keepSelection: true)
    }

    @objc private func showGridChanged() {
        previewCanvasView.showsGrid = showGridCheckbox.state == .on
    }

    @objc private func saveProfile() {
        if !nameField.stringValue.isEmpty {
            profile.name = nameField.stringValue
        }

        profile.padWidth = clampedPadDimension(
            from: padWidthField.stringValue,
            fallback: profile.padWidth,
            minimum: Self.minimumPadWidth
        )
        profile.padHeight = clampedPadDimension(
            from: padHeightField.stringValue,
            fallback: profile.padHeight,
            minimum: Self.minimumPadHeight
        )
        padWidthField.stringValue = "\(Int(profile.padWidth))"
        padHeightField.stringValue = "\(Int(profile.padHeight))"
        profile.compatibilityMode = compatibilityModeCheckbox.state == .on
        updatePreviewCanvasLayout()
        previewView.reload(profile: profile, keepSelection: true)

        onProfileSaved?(profile)
        showSavedIndicator()
    }

    private func clampedPadDimension(from stringValue: String, fallback: Double, minimum: Double) -> Double {
        guard let parsedValue = Double(stringValue), parsedValue.isFinite else {
            return fallback
        }

        return max(minimum, parsedValue)
    }

    private func showSavedIndicator() {
        let savedLabel = NSTextField(labelWithString: "Saved")
        savedLabel.font = .boldSystemFont(ofSize: 12)
        savedLabel.textColor = .systemGreen
        savedLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(savedLabel)

        NSLayoutConstraint.activate([
            savedLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            savedLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
        ])

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            savedLabel.removeFromSuperview()
        }
    }

    private func updatePreviewCanvasLayout() {
        let previewSize = CGSize(width: profile.padWidth, height: profile.padHeight)
        previewCanvasView.previewSize = previewSize
        previewCanvasView.showsGrid = showGridCheckbox.state == .on
        previewCanvasView.updateCanvasSize(visibleSize: previewScrollView.contentView.bounds.size)
        previewCanvasView.layoutSubtreeIfNeeded()
    }
}
