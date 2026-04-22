import Cocoa

final class ButtonEditorViewController: NSViewController {

    var onProfileSaved: ((Profile) -> Void)?

    private static let minimumPadWidth = 260.0
    private static let minimumPadHeight = 180.0

    private var profile = ProfileStore.shared.activeProfile

    private let nameField = NSTextField()
    private let opacitySlider = NSSlider()
    private let opacityLabel = NSTextField(labelWithString: "90%")
    private let padWidthField = NSTextField()
    private let padHeightField = NSTextField()
    private let previewView = GamepadPreviewView()
    private let detailPanel = ButtonDetailPanel()

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 780, height: 580))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildLayout()
        load(profile: ProfileStore.shared.activeProfile)
    }

    func load(profile: Profile) {
        self.profile = profile
        nameField.stringValue = profile.name
        opacitySlider.doubleValue = profile.opacity
        opacityLabel.stringValue = "\(Int(profile.opacity * 100))%"
        padWidthField.stringValue = "\(Int(profile.padWidth))"
        padHeightField.stringValue = "\(Int(profile.padHeight))"
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
            NSView(),
            saveButton,
        ])
        topBar.orientation = .horizontal
        topBar.alignment = .centerY
        topBar.spacing = 6
        topBar.translatesAutoresizingMaskIntoConstraints = false

        previewView.translatesAutoresizingMaskIntoConstraints = false
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

        let hint = NSTextField(
            labelWithString: "Click a button to select it. Drag the button to move it or the corner handle to resize it."
        )
        hint.font = .systemFont(ofSize: 10)
        hint.textColor = .secondaryLabelColor
        hint.translatesAutoresizingMaskIntoConstraints = false

        [topBar, previewView, detailPanel, hint].forEach(view.addSubview(_:))

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
            previewView.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 14),
            previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            previewView.widthAnchor.constraint(equalToConstant: 420),
            previewView.heightAnchor.constraint(equalToConstant: 300),
            hint.topAnchor.constraint(equalTo: previewView.bottomAnchor, constant: 6),
            hint.leadingAnchor.constraint(equalTo: previewView.leadingAnchor),
            detailPanel.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 14),
            detailPanel.leadingAnchor.constraint(equalTo: previewView.trailingAnchor, constant: 20),
            detailPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            detailPanel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
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
}
