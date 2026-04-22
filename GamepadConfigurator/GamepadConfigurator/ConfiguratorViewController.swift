import Cocoa

// MARK: - Root split view

class ConfiguratorViewController: NSSplitViewController {

    private let profileListVC = ProfileListViewController()
    private let editorVC      = ButtonEditorViewController()

    override func viewDidLoad() {
        super.viewDidLoad()

        let leftItem = NSSplitViewItem(sidebarWithViewController: profileListVC)
        leftItem.minimumThickness = 180
        leftItem.maximumThickness = 220
        addSplitViewItem(leftItem)
        addSplitViewItem(NSSplitViewItem(viewController: editorVC))

        profileListVC.onProfileSelected = { [weak self] p in self?.editorVC.load(profile: p) }
        editorVC.onProfileSaved = { [weak self] p in
            ProfileStore.shared.upsert(p)
            self?.profileListVC.reload()
        }
        editorVC.load(profile: ProfileStore.shared.activeProfile)
    }
}

// MARK: - Profile list

class ProfileListViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {

    var onProfileSelected: ((Profile) -> Void)?
    private let tableView  = NSTableView()
    private let scrollView = NSScrollView()
    private var profiles: [Profile] { ProfileStore.shared.profiles }

    override func loadView() { view = NSView(frame: NSRect(x:0,y:0,width:200,height:400)) }

    override func viewDidLoad() {
        super.viewDidLoad()
        let col = NSTableColumn(identifier: .init("name"))
        col.title = "Profiles"
        tableView.addTableColumn(col)
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate   = self
        tableView.rowHeight  = 28
        tableView.usesAlternatingRowBackgroundColors = true

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        func mkBtn(_ t: String, _ sel: Selector) -> NSButton {
            let b = NSButton(title: t, target: self, action: sel); b.bezelStyle = .smallSquare; return b
        }
        let bar = NSStackView(views: [mkBtn("+", #selector(addProfile)),
                                      mkBtn("⎘", #selector(dupProfile)),
                                      mkBtn("−", #selector(delProfile)), NSView()])
        bar.orientation = .horizontal; bar.spacing = 4
        bar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView); view.addSubview(bar)
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
            bar.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -4),
            bar.heightAnchor.constraint(equalToConstant: 26),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bar.topAnchor, constant: -4),
        ])
        reload()
    }

    func reload() {
        tableView.reloadData()
        if let i = profiles.firstIndex(where: { $0.id == ProfileStore.shared.activeProfileID }) {
            tableView.selectRowIndexes(IndexSet(integer: i), byExtendingSelection: false)
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { profiles.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let c = NSTextField(labelWithString: profiles[row].name)
        c.font = NSFont.systemFont(ofSize: 13); return c
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        let r = tableView.selectedRow; guard r >= 0 else { return }
        ProfileStore.shared.setActive(profiles[r].id)
        onProfileSelected?(profiles[r])
    }

    @objc private func addProfile() {
        let p = Profile.makeDefault(name: "Profile \(profiles.count+1)")
        ProfileStore.shared.upsert(p); ProfileStore.shared.setActive(p.id)
        reload(); onProfileSelected?(p)
    }
    @objc private func dupProfile() {
        let r = tableView.selectedRow; guard r >= 0 else { return }
        ProfileStore.shared.duplicate(profiles[r].id); reload()
    }
    @objc private func delProfile() {
        let r = tableView.selectedRow; guard r >= 0 else { return }
        ProfileStore.shared.delete(profiles[r].id); reload()
        onProfileSelected?(ProfileStore.shared.activeProfile)
    }
}

// MARK: - Editor

class ButtonEditorViewController: NSViewController {

    var onProfileSaved: ((Profile) -> Void)?
    private var profile = ProfileStore.shared.activeProfile

    private let nameField       = NSTextField()
    private let opacitySlider   = NSSlider()
    private let opacityLbl      = NSTextField(labelWithString: "90%")
    private let padWField       = NSTextField()
    private let padHField       = NSTextField()
    private let previewView     = GamepadPreviewView()
    private let detailPanel     = ButtonDetailPanel()

    override func loadView() { view = NSView(frame: NSRect(x:0,y:0,width:780,height:580)) }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildLayout()
        load(profile: ProfileStore.shared.activeProfile)
    }

    private func buildLayout() {
        nameField.placeholderString = "Profile name"
        nameField.bezelStyle = .roundedBezel
        nameField.font = NSFont.systemFont(ofSize: 12)

        opacitySlider.minValue = 0.25; opacitySlider.maxValue = 1.0
        opacitySlider.isContinuous = true
        opacitySlider.target = self; opacitySlider.action = #selector(opacityMoved)

        padWField.bezelStyle = .roundedBezel
        padWField.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        padHField.bezelStyle = .roundedBezel
        padHField.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)

        let saveBtn = NSButton(title: "💾  Save & Apply", target: self, action: #selector(saveProfile))
        saveBtn.bezelStyle = .rounded; saveBtn.keyEquivalent = "\r"

        func lbl(_ s: String) -> NSTextField { let t = NSTextField(labelWithString: s); t.font = NSFont.systemFont(ofSize: 12); return t }

        let topBar = NSStackView(views: [lbl("Name:"), nameField,
                                         lbl("  Opacity:"), opacitySlider, opacityLbl,
                                         lbl("  Size:"), padWField, lbl("×"), padHField,
                                         NSView(), saveBtn])
        topBar.orientation = .horizontal; topBar.alignment = .centerY; topBar.spacing = 6
        topBar.translatesAutoresizingMaskIntoConstraints = false

        previewView.translatesAutoresizingMaskIntoConstraints = false
        previewView.onButtonSelected = { [weak self] btn in
            guard let self, let cfg = self.profile.buttons[btn.rawValue] else { return }
            self.detailPanel.load(button: btn, config: cfg)
        }
        previewView.onButtonMoved = { [weak self] btn, nx, ny in
            guard let self else { return }
            self.profile.buttons[btn.rawValue]?.x = nx
            self.profile.buttons[btn.rawValue]?.y = ny
            if let cfg = self.profile.buttons[btn.rawValue] { self.detailPanel.refreshPosition(x: nx, y: ny, cfg: cfg) }
        }
        previewView.onButtonResized = { [weak self] btn, nw, nh in
            guard let self else { return }
            self.profile.buttons[btn.rawValue]?.width  = nw
            self.profile.buttons[btn.rawValue]?.height = nh
            self.detailPanel.refreshSize(w: nw, h: nh)
        }

        detailPanel.translatesAutoresizingMaskIntoConstraints = false
        detailPanel.onChanged = { [weak self] btn, cfg in
            guard let self else { return }
            self.profile.buttons[btn.rawValue] = cfg
            self.previewView.reload(profile: self.profile, keepSelection: true)
        }

        let hint = NSTextField(labelWithString: "Click button to select · Drag center to move · Drag corner to resize")
        hint.isEditable = false; hint.isBordered = false; hint.backgroundColor = .clear
        hint.font = NSFont.systemFont(ofSize: 10); hint.textColor = .secondaryLabelColor
        hint.translatesAutoresizingMaskIntoConstraints = false

        [topBar, previewView, detailPanel, hint].forEach { view.addSubview($0) }

        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            topBar.heightAnchor.constraint(equalToConstant: 28),
            nameField.widthAnchor.constraint(equalToConstant: 130),
            opacitySlider.widthAnchor.constraint(equalToConstant: 90),
            opacityLbl.widthAnchor.constraint(equalToConstant: 36),
            padWField.widthAnchor.constraint(equalToConstant: 52),
            padHField.widthAnchor.constraint(equalToConstant: 52),
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

    func load(profile: Profile) {
        self.profile = profile
        nameField.stringValue     = profile.name
        opacitySlider.doubleValue = profile.opacity
        opacityLbl.stringValue    = "\(Int(profile.opacity * 100))%"
        padWField.stringValue     = "\(Int(profile.padWidth))"
        padHField.stringValue     = "\(Int(profile.padHeight))"
        previewView.reload(profile: profile, keepSelection: false)
        detailPanel.clear()
    }

    @objc private func opacityMoved() {
        profile.opacity = opacitySlider.doubleValue
        opacityLbl.stringValue = "\(Int(profile.opacity * 100))%"
    }

    @objc private func saveProfile() {
        if !nameField.stringValue.isEmpty { profile.name = nameField.stringValue }
        profile.padWidth  = Double(padWField.stringValue) ?? profile.padWidth
        profile.padHeight = Double(padHField.stringValue) ?? profile.padHeight
        onProfileSaved?(profile)
        let saved = NSTextField(labelWithString: "✓ Saved")
        saved.font = NSFont.boldSystemFont(ofSize: 12); saved.textColor = .systemGreen
        saved.isBordered = false; saved.backgroundColor = .clear
        saved.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(saved)
        NSLayoutConstraint.activate([
            saved.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            saved.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
        ])
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { saved.removeFromSuperview() }
    }
}

// MARK: - Preview view (move + resize)

class GamepadPreviewView: NSView {

    var onButtonSelected: ((GamepadButton) -> Void)?
    var onButtonMoved:    ((GamepadButton, Double, Double) -> Void)?
    var onButtonResized:  ((GamepadButton, Double, Double) -> Void)?

    private var buttonLayers:  [GamepadButton: CALayer] = [:]
    private var handleLayers:  [GamepadButton: [CALayer]] = [:]
    private var selectedButton: GamepadButton?
    private var profile = ProfileStore.shared.activeProfile

    // Drag state
    private enum DragMode { case move, resizeBR }
    private var dragMode: DragMode = .move
    private var dragButton: GamepadButton?
    private var dragStartMouse: CGPoint = .zero
    private var dragStartBtnCenter: CGPoint = .zero
    private var dragStartBtnSize: CGSize = .zero

    private let handleSize: CGFloat = 8

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.10, alpha: 1).cgColor
        layer?.cornerRadius = 14
        layer?.borderWidth  = 1
        layer?.borderColor  = NSColor.white.withAlphaComponent(0.08).cgColor
    }
    required init?(coder: NSCoder) { fatalError() }

    func reload(profile: Profile, keepSelection: Bool) {
        let was = keepSelection ? selectedButton : nil
        self.profile = profile
        buttonLayers.values.forEach { $0.removeFromSuperlayer() }
        handleLayers.values.flatMap { $0 }.forEach { $0.removeFromSuperlayer() }
        buttonLayers.removeAll(); handleLayers.removeAll()

        let W = bounds.width, H = bounds.height
        for btn in GamepadButton.allCases {
            guard let cfg = profile.buttons[btn.rawValue], cfg.enabled else { continue }
            let cx = CGFloat(cfg.x)*W, cy = CGFloat(cfg.y)*H
            let bw = CGFloat(cfg.width)*W, bh = CGFloat(cfg.height)*H

            let l = CALayer()
            l.frame           = CGRect(x: cx-bw/2, y: cy-bh/2, width: bw, height: bh)
            l.backgroundColor = NSColor(hex: cfg.colorHex).withAlphaComponent(0.85).cgColor
            l.cornerRadius    = 6
            let txt = CATextLayer()
            txt.string = cfg.label; txt.fontSize = 10; txt.alignmentMode = .center
            txt.foregroundColor = NSColor.white.cgColor
            txt.contentsScale = window?.backingScaleFactor ?? 2
            txt.frame = l.bounds
            l.addSublayer(txt)
            self.layer?.addSublayer(l)
            buttonLayers[btn] = l

            // Resize handle (bottom-right corner)
            let h = CALayer()
            h.frame = CGRect(x: l.frame.maxX - handleSize, y: l.frame.minY,
                             width: handleSize, height: handleSize)
            h.backgroundColor = NSColor.white.withAlphaComponent(0.7).cgColor
            h.cornerRadius    = 2
            h.isHidden        = true
            self.layer?.addSublayer(h)
            handleLayers[btn] = [h]
        }
        if let sel = was { highlight(sel) }
    }

    private func highlight(_ btn: GamepadButton?) {
        buttonLayers.values.forEach { $0.borderWidth = 0; $0.shadowOpacity = 0 }
        handleLayers.values.flatMap { $0 }.forEach { $0.isHidden = true }
        guard let btn, let l = buttonLayers[btn] else { selectedButton = nil; return }
        l.borderWidth = 2; l.borderColor = NSColor.white.cgColor
        l.shadowOpacity = 0.6; l.shadowColor = NSColor.white.cgColor
        l.shadowRadius = 4; l.shadowOffset = .zero
        handleLayers[btn]?.forEach { $0.isHidden = false }
        selectedButton = btn
    }

    private func buttonAt(_ pt: CGPoint) -> GamepadButton? {
        let W = bounds.width, H = bounds.height
        for btn in GamepadButton.allCases {
            guard let cfg = profile.buttons[btn.rawValue], cfg.enabled else { continue }
            let cx = CGFloat(cfg.x)*W, cy = CGFloat(cfg.y)*H
            let bw = CGFloat(cfg.width)*W, bh = CGFloat(cfg.height)*H
            if CGRect(x: cx-bw/2, y: cy-bh/2, width: bw, height: bh).contains(pt) { return btn }
        }
        return nil
    }

    private func isOnHandle(_ pt: CGPoint, for btn: GamepadButton) -> Bool {
        guard let handles = handleLayers[btn] else { return false }
        return handles.contains { !$0.isHidden && $0.frame.contains(pt) }
    }

    override func mouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        guard let btn = buttonAt(pt), let cfg = profile.buttons[btn.rawValue] else {
            highlight(nil); return
        }
        highlight(btn); onButtonSelected?(btn)
        dragButton = btn
        dragStartMouse = pt
        let W = bounds.width, H = bounds.height
        dragStartBtnCenter = CGPoint(x: CGFloat(cfg.x)*W, y: CGFloat(cfg.y)*H)
        dragStartBtnSize   = CGSize(width: CGFloat(cfg.width)*W, height: CGFloat(cfg.height)*H)
        dragMode = isOnHandle(pt, for: btn) ? .resizeBR : .move
    }

    override func mouseDragged(with event: NSEvent) {
        guard let btn = dragButton else { return }
        let pt = convert(event.locationInWindow, from: nil)
        let dx = pt.x - dragStartMouse.x
        let dy = pt.y - dragStartMouse.y
        let W  = bounds.width, H = bounds.height

        CATransaction.begin(); CATransaction.setDisableActions(true)

        switch dragMode {
        case .move:
            let nx = (dragStartBtnCenter.x + dx).clamped(to: 0...W)
            let ny = (dragStartBtnCenter.y + dy).clamped(to: 0...H)
            if let l = buttonLayers[btn] { l.position = CGPoint(x: nx, y: ny) }
            // Move handle too
            if let h = handleLayers[btn]?.first, let l = buttonLayers[btn] {
                h.frame = CGRect(x: l.frame.maxX - handleSize, y: l.frame.minY,
                                 width: handleSize, height: handleSize)
            }
            onButtonMoved?(btn, nx/W, ny/H)

        case .resizeBR:
            let newW = max(20, dragStartBtnSize.width + dx)
            let newH = max(14, dragStartBtnSize.height - dy)  // y-flipped
            if let l = buttonLayers[btn] {
                let cx = l.position.x, cy = l.position.y
                l.bounds = CGRect(origin: .zero, size: CGSize(width: newW, height: newH))
                l.position = CGPoint(x: cx, y: cy)
                // update text sublayer
                if let txt = l.sublayers?.first { txt.frame = l.bounds }
                // update handle
                if let h = handleLayers[btn]?.first {
                    h.frame = CGRect(x: l.frame.maxX - handleSize, y: l.frame.minY,
                                     width: handleSize, height: handleSize)
                }
            }
            onButtonResized?(btn, newW/W, newH/H)
        }

        CATransaction.commit()
    }

    override func mouseUp(with event: NSEvent) { dragButton = nil }
    override var isFlipped: Bool { false }
}

// MARK: - Key recorder button
// A button that toggles recording mode. Click once → starts listening.
// Press any key/combo → records it and stops. Click again to cancel.

class KeyRecorderButton: NSView {

    var onKeyRecorded: ((Int, NSEvent.ModifierFlags) -> Void)?

    private(set) var recordedCode: Int = 49
    private(set) var recordedMods: NSEvent.ModifierFlags = []

    private var isRecording = false {
        didSet { updateAppearance() }
    }

    private let button  = NSButton()
    private var monitor: Any?

    override init(frame: NSRect) {
        super.init(frame: frame)
        button.bezelStyle    = .rounded
        button.target        = self
        button.action        = #selector(toggleRecording)
        button.translatesAutoresizingMaskIntoConstraints = false
        addSubview(button)
        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: topAnchor),
            button.bottomAnchor.constraint(equalTo: bottomAnchor),
            button.leadingAnchor.constraint(equalTo: leadingAnchor),
            button.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        updateAppearance()
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func toggleRecording() {
        isRecording ? stopRecording(cancelled: true) : startRecording()
    }

    private func startRecording() {
        isRecording = true
        // Local monitor catches key events regardless of focus
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKey(event)
            return nil  // consume the event
        }
    }

    private func handleKey(_ event: NSEvent) {
        // Ignore bare modifier-only keypresses
        let modifierOnly: Set<UInt16> = [54,55,56,57,58,59,60,61,62,63]
        guard !modifierOnly.contains(event.keyCode) else { return }

        recordedCode = Int(event.keyCode)
        recordedMods = event.modifierFlags.intersection([.command,.option,.control,.shift])
        stopRecording(cancelled: false)
        onKeyRecorded?(recordedCode, recordedMods)
    }

    private func stopRecording(cancelled: Bool) {
        isRecording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }

    private func updateAppearance() {
        if isRecording {
            button.title           = "● Press a key…"
            button.contentTintColor = .systemOrange
        } else {
            button.title           = keyDisplayName(code: recordedCode, mods: recordedMods)
            button.contentTintColor = .labelColor
        }
    }

    func setKey(code: Int, mods: NSEvent.ModifierFlags = []) {
        recordedCode = code
        recordedMods = mods
        updateAppearance()
    }

    private func keyDisplayName(code: Int, mods: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []
        if mods.contains(.control) { parts.append("⌃") }
        if mods.contains(.option)  { parts.append("⌥") }
        if mods.contains(.shift)   { parts.append("⇧") }
        if mods.contains(.command) { parts.append("⌘") }
        parts.append(keyName(code))
        return parts.joined()
    }

    static func keyName(_ code: Int) -> String {
        let map: [Int:String] = [
            0:"A",1:"S",2:"D",3:"F",4:"H",5:"G",6:"Z",7:"X",8:"C",9:"V",
            11:"B",12:"Q",13:"W",14:"E",15:"R",16:"Y",17:"T",31:"O",32:"U",
            34:"I",35:"P",37:"L",38:"J",40:"K",45:"N",46:"M",
            36:"↩",48:"⇥",49:"Space",51:"⌫",53:"⎋",
            123:"←",124:"→",125:"↓",126:"↑",
            96:"F5",97:"F6",98:"F7",99:"F3",100:"F8",101:"F9",
            103:"F11",109:"F10",111:"F12",
            115:"Home",116:"PgUp",117:"Del",119:"End",121:"PgDn"
        ]
        return map[code] ?? "key(\(code))"
    }

    private func keyName(_ code: Int) -> String { KeyRecorderButton.keyName(code) }

    deinit { if let m = monitor { NSEvent.removeMonitor(m) } }
}

// MARK: - Button detail panel

class ButtonDetailPanel: NSView {

    var onChanged: ((GamepadButton, ButtonConfig) -> Void)?

    private var config: ButtonConfig?
    private var button: GamepadButton?

    private let titleLabel   = NSTextField(labelWithString: "Select a button")
    private let labelField   = NSTextField()
    private let keyRecorder  = KeyRecorderButton()
    private let colorWell    = NSColorWell()
    private let xField       = NSTextField()
    private let yField       = NSTextField()
    private let wLabel       = NSTextField(labelWithString: "–")
    private let hLabel       = NSTextField(labelWithString: "–")
    private let enabledBox   = NSButton(checkboxWithTitle: "Enabled", target: nil, action: nil)
    private let applyBtn     = NSButton(title: "Apply Changes", target: nil, action: nil)

    override init(frame: NSRect) { super.init(frame: frame); setup() }
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        titleLabel.font = NSFont.boldSystemFont(ofSize: 14)
        titleLabel.isBordered = false; titleLabel.isEditable = false
        titleLabel.backgroundColor = .clear

        keyRecorder.translatesAutoresizingMaskIntoConstraints = false
        keyRecorder.widthAnchor.constraint(equalToConstant: 150).isActive = true
        keyRecorder.heightAnchor.constraint(equalToConstant: 28).isActive = true
        keyRecorder.onKeyRecorded = { [weak self] code, _ in
            self?.config?.keyCode = code
            self?.emitChange()
        }

        applyBtn.bezelStyle = .rounded
        applyBtn.target     = self
        applyBtn.action     = #selector(applyPressed)
        applyBtn.isEnabled  = false

        wLabel.textColor = .secondaryLabelColor
        wLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        hLabel.textColor = .secondaryLabelColor
        hLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)

        func makeLbl(_ s: String) -> NSTextField {
            let l = NSTextField(labelWithString: s)
            l.font = NSFont.systemFont(ofSize: 12)
            l.widthAnchor.constraint(equalToConstant: 60).isActive = true
            return l
        }
        func makeField() -> NSTextField {
            let f = NSTextField(); f.bezelStyle = .roundedBezel
            f.widthAnchor.constraint(equalToConstant: 115).isActive = true
            f.target = self; f.action = #selector(applyPressed)
            return f
        }

        let stack = NSStackView(); stack.orientation = .vertical
        stack.alignment = .leading; stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(titleLabel)

        // Label row
        let labelRow = NSStackView(views: [makeLbl("Label:"), labelField])
        labelRow.orientation = .horizontal; labelRow.spacing = 8
        labelField.bezelStyle = .roundedBezel
        labelField.widthAnchor.constraint(equalToConstant: 115).isActive = true
        labelField.target = self; labelField.action = #selector(applyPressed)
        stack.addArrangedSubview(labelRow)

        // Key row
        let keyRow = NSStackView(views: [makeLbl("Key:"), keyRecorder])
        keyRow.orientation = .horizontal; keyRow.spacing = 8
        stack.addArrangedSubview(keyRow)

        // Color row
        let colorRow = NSStackView(views: [makeLbl("Color:"), colorWell])
        colorRow.orientation = .horizontal; colorRow.spacing = 8
        stack.addArrangedSubview(colorRow)

        // X row
        let xRow = NSStackView(views: [makeLbl("X (0–1):"), xField])
        xRow.orientation = .horizontal; xRow.spacing = 8
        xField.bezelStyle = .roundedBezel
        xField.widthAnchor.constraint(equalToConstant: 115).isActive = true
        xField.target = self; xField.action = #selector(applyPressed)
        stack.addArrangedSubview(xRow)

        // Y row
        let yRow = NSStackView(views: [makeLbl("Y (0–1):"), yField])
        yRow.orientation = .horizontal; yRow.spacing = 8
        yField.bezelStyle = .roundedBezel
        yField.widthAnchor.constraint(equalToConstant: 115).isActive = true
        yField.target = self; yField.action = #selector(applyPressed)
        stack.addArrangedSubview(yRow)

        // Enabled
        stack.addArrangedSubview(enabledBox)

        // Size (read-only)
        let sizeRow = NSStackView(); sizeRow.orientation = .horizontal; sizeRow.spacing = 4
        sizeRow.addArrangedSubview(makeLbl("Size:"))
        sizeRow.addArrangedSubview(wLabel)
        let xLbl = NSTextField(labelWithString: "×"); xLbl.font = NSFont.systemFont(ofSize: 12)
        sizeRow.addArrangedSubview(xLbl)
        sizeRow.addArrangedSubview(hLabel)
        let note = NSTextField(labelWithString: "(drag corner in preview)")
        note.font = NSFont.systemFont(ofSize: 10); note.textColor = .tertiaryLabelColor
        note.isBordered = false; note.isEditable = false; note.backgroundColor = .clear
        sizeRow.addArrangedSubview(note)
        stack.addArrangedSubview(sizeRow)
        stack.addArrangedSubview(applyBtn)

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
        ])

        colorWell.target  = self; colorWell.action  = #selector(applyPressed)
        enabledBox.target = self; enabledBox.action = #selector(applyPressed)
        clear()
    }

    func clear() {
        titleLabel.stringValue = "Select a button to edit"
        config = nil; button = nil
        [labelField, xField, yField].forEach { $0.stringValue = "" }
        keyRecorder.setKey(code: 49)
        wLabel.stringValue = "–"; hLabel.stringValue = "–"
        applyBtn.isEnabled = false
    }

    func load(button: GamepadButton, config: ButtonConfig) {
        self.button = button; self.config = config
        applyBtn.isEnabled     = true
        titleLabel.stringValue = "Editing: \(button.rawValue)"
        labelField.stringValue = config.label
        colorWell.color        = NSColor(hex: config.colorHex)
        xField.stringValue     = String(format: "%.4f", config.x)
        yField.stringValue     = String(format: "%.4f", config.y)
        enabledBox.state       = config.enabled ? .on : .off
        keyRecorder.setKey(code: config.keyCode)
        wLabel.stringValue     = String(format: "%.3f", config.width)
        hLabel.stringValue     = String(format: "%.3f", config.height)
    }

    func refreshPosition(x: Double, y: Double, cfg: ButtonConfig) {
        guard config != nil else { return }
        config?.x = x; config?.y = y
        xField.stringValue = String(format: "%.4f", x)
        yField.stringValue = String(format: "%.4f", y)
    }

    func refreshSize(w: Double, h: Double) {
        guard config != nil else { return }
        config?.width = w; config?.height = h
        wLabel.stringValue = String(format: "%.3f", w)
        hLabel.stringValue = String(format: "%.3f", h)
    }

    @objc private func applyPressed() { emitChange() }

    private func emitChange() {
        guard var cfg = config, let btn = button else { return }
        if !labelField.stringValue.isEmpty { cfg.label = labelField.stringValue }
        cfg.colorHex = colorWell.color.hexString
        cfg.x        = Double(xField.stringValue) ?? cfg.x
        cfg.y        = Double(yField.stringValue) ?? cfg.y
        cfg.enabled  = enabledBox.state == .on
        config = cfg; onChanged?(btn, cfg)
    }
}

// MARK: - Clamping helper

extension Comparable {
    func clamped(to r: ClosedRange<Self>) -> Self { min(max(self, r.lowerBound), r.upperBound) }
}
