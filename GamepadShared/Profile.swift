import Foundation

enum ButtonInteractionMode: String, Codable {
    case momentary
    case toggleHold
    case turbo
}

enum ButtonShape: String, Codable {
    case roundedRectangle
    case oval
}

enum EditorCoordinateMode: String, Codable {
    case legacyTopLeft
    case centered
}

enum MultiKeyActivationMode: String, Codable {
    case sequential
    case simultaneous
}

struct ButtonKeyBinding: Codable, Hashable {
    var keyCode: Int
    var keyModifiers: Int
}

// MARK: - ButtonConfig
// Per-button layout and appearance settings stored in a profile.

struct ButtonConfig: Codable {
    var x: Double           // center X, as fraction of pad width  (0.0–1.0)
    var y: Double           // center Y, as fraction of pad height (0.0–1.0)
    var width: Double       // as fraction of pad width
    var height: Double      // as fraction of pad height
    var editorWidth: Double
    var editorHeight: Double
    var colorHex: String    // "#RRGGBB"
    var keyCode: Int        // CGKeyCode raw value
    var keyModifiers: Int   // NSEvent.ModifierFlags raw value
    var keyBindings: [ButtonKeyBinding]
    var multiKeyActivationMode: MultiKeyActivationMode
    var label: String       // display label (can differ from button name)
    var labelFontSize: Double
    var labelBold: Bool
    var labelItalic: Bool
    var shape: ButtonShape
    var enabled: Bool
    var interactionMode: ButtonInteractionMode

    private enum CodingKeys: String, CodingKey {
        case x
        case y
        case width
        case height
        case editorWidth
        case editorHeight
        case colorHex
        case keyCode
        case keyModifiers
        case keyBindings
        case multiKeyActivationMode
        case label
        case labelFontSize
        case labelBold
        case labelItalic
        case shape
        case enabled
        case interactionMode
    }

    init(
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        editorWidth: Double = 0,
        editorHeight: Double = 0,
        colorHex: String,
        keyCode: Int,
        keyModifiers: Int = 0,
        keyBindings: [ButtonKeyBinding]? = nil,
        multiKeyActivationMode: MultiKeyActivationMode = .sequential,
        label: String,
        labelFontSize: Double = 11,
        labelBold: Bool = true,
        labelItalic: Bool = false,
        shape: ButtonShape = .roundedRectangle,
        enabled: Bool,
        interactionMode: ButtonInteractionMode = .momentary
    ) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.editorWidth = editorWidth
        self.editorHeight = editorHeight
        self.colorHex = colorHex
        self.keyCode = keyCode
        self.keyModifiers = keyModifiers
        self.keyBindings = Self.normalizedKeyBindings(
            keyBindings ?? [ButtonKeyBinding(keyCode: keyCode, keyModifiers: keyModifiers)],
            fallbackKeyCode: keyCode,
            fallbackKeyModifiers: keyModifiers
        )
        self.multiKeyActivationMode = multiKeyActivationMode
        self.keyCode = self.keyBindings[0].keyCode
        self.keyModifiers = self.keyBindings[0].keyModifiers
        self.label = label
        self.labelFontSize = labelFontSize
        self.labelBold = labelBold
        self.labelItalic = labelItalic
        self.shape = shape
        self.enabled = enabled
        self.interactionMode = interactionMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        x = try container.decode(Double.self, forKey: .x)
        y = try container.decode(Double.self, forKey: .y)
        width = try container.decode(Double.self, forKey: .width)
        height = try container.decode(Double.self, forKey: .height)
        editorWidth = try container.decodeIfPresent(Double.self, forKey: .editorWidth) ?? 0
        editorHeight = try container.decodeIfPresent(Double.self, forKey: .editorHeight) ?? 0
        colorHex = try container.decode(String.self, forKey: .colorHex)
        let decodedKeyCode = try container.decodeIfPresent(Int.self, forKey: .keyCode) ?? 49
        let decodedKeyModifiers = try container.decodeIfPresent(Int.self, forKey: .keyModifiers) ?? 0
        keyBindings = Self.normalizedKeyBindings(
            try container.decodeIfPresent([ButtonKeyBinding].self, forKey: .keyBindings),
            fallbackKeyCode: decodedKeyCode,
            fallbackKeyModifiers: decodedKeyModifiers
        )
        keyCode = keyBindings[0].keyCode
        keyModifiers = keyBindings[0].keyModifiers
        multiKeyActivationMode = try container.decodeIfPresent(MultiKeyActivationMode.self, forKey: .multiKeyActivationMode) ?? .sequential
        label = try container.decode(String.self, forKey: .label)
        labelFontSize = try container.decodeIfPresent(Double.self, forKey: .labelFontSize) ?? 11
        labelBold = try container.decodeIfPresent(Bool.self, forKey: .labelBold) ?? true
        labelItalic = try container.decodeIfPresent(Bool.self, forKey: .labelItalic) ?? false
        shape = try container.decodeIfPresent(ButtonShape.self, forKey: .shape) ?? .roundedRectangle
        enabled = try container.decode(Bool.self, forKey: .enabled)
        interactionMode = try container.decodeIfPresent(ButtonInteractionMode.self, forKey: .interactionMode) ?? .momentary
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let normalizedBindings = Self.normalizedKeyBindings(
            keyBindings,
            fallbackKeyCode: keyCode,
            fallbackKeyModifiers: keyModifiers
        )
        let firstBinding = normalizedBindings[0]

        try container.encode(x, forKey: .x)
        try container.encode(y, forKey: .y)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
        try container.encode(editorWidth, forKey: .editorWidth)
        try container.encode(editorHeight, forKey: .editorHeight)
        try container.encode(colorHex, forKey: .colorHex)
        try container.encode(firstBinding.keyCode, forKey: .keyCode)
        try container.encode(firstBinding.keyModifiers, forKey: .keyModifiers)
        try container.encode(normalizedBindings, forKey: .keyBindings)
        try container.encode(multiKeyActivationMode, forKey: .multiKeyActivationMode)
        try container.encode(label, forKey: .label)
        try container.encode(labelFontSize, forKey: .labelFontSize)
        try container.encode(labelBold, forKey: .labelBold)
        try container.encode(labelItalic, forKey: .labelItalic)
        try container.encode(shape, forKey: .shape)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(interactionMode, forKey: .interactionMode)
    }

    private static func normalizedKeyBindings(
        _ bindings: [ButtonKeyBinding]?,
        fallbackKeyCode: Int,
        fallbackKeyModifiers: Int
    ) -> [ButtonKeyBinding] {
        guard let bindings, !bindings.isEmpty else {
            return [ButtonKeyBinding(keyCode: fallbackKeyCode, keyModifiers: fallbackKeyModifiers)]
        }

        return bindings
    }
}

// MARK: - Profile

struct Profile: Codable, Identifiable {
    var id: UUID
    var name: String
    var opacity: Double                              // 0.25–1.0
    var compatibilityMode: Bool
    var editorCoordinateMode: EditorCoordinateMode
    var padWidth: Double                             // absolute pts
    var padHeight: Double
    var displayPadWidth: Double
    var displayPadHeight: Double
    var buttons: [String: ButtonConfig]              // keyed by GamepadButton.rawValue
    var subProfiles: [Profile]
    var activeSubProfileID: UUID?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case opacity
        case compatibilityMode
        case editorCoordinateMode
        case padWidth
        case padHeight
        case displayPadWidth
        case displayPadHeight
        case buttons
        case subProfiles
        case activeSubProfileID
    }

    init(
        id: UUID,
        name: String,
        opacity: Double,
        compatibilityMode: Bool = false,
        editorCoordinateMode: EditorCoordinateMode = .legacyTopLeft,
        padWidth: Double,
        padHeight: Double,
        displayPadWidth: Double? = nil,
        displayPadHeight: Double? = nil,
        buttons: [String: ButtonConfig],
        subProfiles: [Profile] = [],
        activeSubProfileID: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.opacity = opacity
        self.compatibilityMode = compatibilityMode
        self.editorCoordinateMode = editorCoordinateMode
        self.padWidth = padWidth
        self.padHeight = padHeight
        self.displayPadWidth = displayPadWidth ?? padWidth
        self.displayPadHeight = displayPadHeight ?? padHeight
        self.buttons = buttons
        self.subProfiles = subProfiles
        self.activeSubProfileID = activeSubProfileID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        opacity = try container.decode(Double.self, forKey: .opacity)
        compatibilityMode = try container.decodeIfPresent(Bool.self, forKey: .compatibilityMode) ?? false
        editorCoordinateMode = try container.decodeIfPresent(EditorCoordinateMode.self, forKey: .editorCoordinateMode) ?? .legacyTopLeft
        padWidth = try container.decode(Double.self, forKey: .padWidth)
        padHeight = try container.decode(Double.self, forKey: .padHeight)
        displayPadWidth = try container.decodeIfPresent(Double.self, forKey: .displayPadWidth) ?? padWidth
        displayPadHeight = try container.decodeIfPresent(Double.self, forKey: .displayPadHeight) ?? padHeight
        buttons = try container.decode([String: ButtonConfig].self, forKey: .buttons)
        subProfiles = try container.decodeIfPresent([Profile].self, forKey: .subProfiles) ?? []
        activeSubProfileID = try container.decodeIfPresent(UUID.self, forKey: .activeSubProfileID)
    }

    var orderedButtonIDs: [GamepadButton] {
        buttons.keys
            .map { GamepadButton($0) }
            .sorted { lhs, rhs in
                let lhsLegacyIndex = Self.legacyButtonOrder[lhs.rawValue]
                let rhsLegacyIndex = Self.legacyButtonOrder[rhs.rawValue]

                switch (lhsLegacyIndex, rhsLegacyIndex) {
                case let (lhsIndex?, rhsIndex?):
                    return lhsIndex < rhsIndex
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    let lhsLabel = buttons[lhs.rawValue]?.resolvedSortLabel ?? lhs.rawValue
                    let rhsLabel = buttons[rhs.rawValue]?.resolvedSortLabel ?? rhs.rawValue
                    let labelOrder = lhsLabel.localizedStandardCompare(rhsLabel)
                    if labelOrder != .orderedSame {
                        return labelOrder == .orderedAscending
                    }

                    return lhs.rawValue < rhs.rawValue
                }
            }
    }

    func normalizedForSaving() -> Profile {
        var normalizedProfile = self
        var normalizedButtons: [String: ButtonConfig] = [:]

        for button in orderedButtonIDs {
            guard let config = buttons[button.rawValue] else {
                continue
            }

            let key = button.isGenerated ? button.rawValue : GamepadButton.generated().rawValue
            normalizedButtons[key] = config
        }

        normalizedProfile.buttons = normalizedButtons
        normalizedProfile.subProfiles = subProfiles.map { $0.normalizedForSaving() }
        return normalizedProfile
    }

    func asTopLevelContainer(baseLayerName: String = "Base") -> Profile {
        if !subProfiles.isEmpty {
            return normalizedActiveSubProfileSelection()
        }

        var baseLayer = self
        baseLayer.id = UUID()
        baseLayer.name = baseLayerName
        baseLayer.subProfiles = []
        baseLayer.activeSubProfileID = nil

        var container = self
        container.buttons = [:]
        container.subProfiles = [baseLayer]
        container.activeSubProfileID = baseLayer.id
        return container
    }

    func normalizedActiveSubProfileSelection() -> Profile {
        var normalizedProfile = self
        if normalizedProfile.subProfiles.isEmpty {
            normalizedProfile.activeSubProfileID = nil
            return normalizedProfile
        }

        if let activeSubProfileID,
           normalizedProfile.subProfiles.contains(where: { $0.id == activeSubProfileID }) {
            normalizedProfile.activeSubProfileID = activeSubProfileID
        } else {
            normalizedProfile.activeSubProfileID = normalizedProfile.subProfiles[0].id
        }

        return normalizedProfile
    }

    func copyWithNewIDs(nameSuffix: String = " Copy") -> Profile {
        var copiedProfile = self
        copiedProfile.id = UUID()
        copiedProfile.name += nameSuffix
        copiedProfile.subProfiles = subProfiles.map { $0.copyWithNewIDs(nameSuffix: "") }

        if let activeSubProfileID,
           let sourceIndex = subProfiles.firstIndex(where: { $0.id == activeSubProfileID }),
           copiedProfile.subProfiles.indices.contains(sourceIndex) {
            copiedProfile.activeSubProfileID = copiedProfile.subProfiles[sourceIndex].id
        } else {
            copiedProfile.activeSubProfileID = copiedProfile.subProfiles.first?.id
        }

        return copiedProfile
    }

    static func makeBlank(name: String = "Blank Profile") -> Profile {
        Profile(
            id: UUID(),
            name: name,
            opacity: 0.90,
            compatibilityMode: false,
            editorCoordinateMode: .centered,
            padWidth: 420,
            padHeight: 300,
            displayPadWidth: 420,
            displayPadHeight: 300,
            buttons: [:]
        )
    }

    static func makeDefault(name: String = "Default") -> Profile {
        makeStarterTemplate(name: name)
    }

    // Starter template matching the original hardcoded layout.
    static func makeStarterTemplate(name: String = "Default") -> Profile {
        let W: Double = 420
        let H: Double = 300

        func cx(_ abs: Double) -> Double { abs / W }
        func cy(_ abs: Double) -> Double { abs / H }
        func bw(_ abs: Double) -> Double { abs / W }
        func bh(_ abs: Double) -> Double { abs / H }

        var btns: [String: ButtonConfig] = [:]

        func add(label: String, x: Double, y: Double,
                 w: Double, h: Double, hex: String, key: Int) {
            btns[GamepadButton.generated().rawValue] = ButtonConfig(
                x: cx(x), y: cy(y),
                width: bw(w), height: bh(h),
                editorWidth: w,
                editorHeight: h,
                colorHex: hex,
                keyCode: key,
                keyModifiers: 0,
                label: label,
                enabled: true
            )
        }

        // Shoulders / triggers
        add(label: "ZL", x: 38,    y: H - 24,  w: 52, h: 32, hex: "#8844DD", key: 14)  // E
        add(label: "L",  x: 38,    y: H - 60,  w: 52, h: 32, hex: "#8844DD", key: 12)  // Q
        add(label: "ZR", x: W - 38, y: H - 24, w: 52, h: 32, hex: "#8844DD", key: 15)  // R
        add(label: "R",  x: W - 38, y: H - 60, w: 52, h: 32, hex: "#8844DD", key: 13)  // W

        // D-pad
        add(label: "D↑", x: 82,  y: H - 111, w: 40, h: 40, hex: "#666666", key: 126)
        add(label: "D↓", x: 82,  y: H - 199, w: 40, h: 40, hex: "#666666", key: 125)
        add(label: "D←", x: 38,  y: H - 155, w: 40, h: 40, hex: "#666666", key: 123)
        add(label: "D→", x: 126, y: H - 155, w: 40, h: 40, hex: "#666666", key: 124)

        // Start / Select
        add(label: "SELECT", x: W / 2 - 36, y: H - 91, w: 52, h: 28, hex: "#333333", key: 49)  // Space
        add(label: "START",  x: W / 2 + 36, y: H - 91, w: 52, h: 28, hex: "#333333", key: 36)  // Return

        // Face buttons
        add(label: "Y", x: W - 82,  y: H - 111, w: 44, h: 44, hex: "#CCAA00", key: 1)   // S
        add(label: "A", x: W - 82,  y: H - 199, w: 44, h: 44, hex: "#229933", key: 6)   // Z
        add(label: "X", x: W - 126, y: H - 155, w: 44, h: 44, hex: "#2255CC", key: 0)   // A
        add(label: "B", x: W - 38,  y: H - 155, w: 44, h: 44, hex: "#CC2222", key: 7)   // X

        // Stick clicks
        add(label: "LS", x: 82,     y: H - 240, w: 40, h: 40, hex: "#2a2a2a", key: 8)   // C
        add(label: "RS", x: W - 82, y: H - 240, w: 40, h: 40, hex: "#2a2a2a", key: 9)  // V

        return Profile(
            id: UUID(),
            name: name,
            opacity: 0.90,
            compatibilityMode: false,
            editorCoordinateMode: .centered,
            padWidth: W,
            padHeight: H,
            displayPadWidth: W,
            displayPadHeight: H,
            buttons: btns
        )
    }

    private static let legacyButtonOrder: [String: Int] = Dictionary(
        uniqueKeysWithValues: GamepadButton.legacyButtons.enumerated().map { index, button in
            (button.rawValue, index)
        }
    )
}

// MARK: - Hex color helpers

import AppKit

extension NSColor {
    convenience init(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h.removeFirst() }
        var rgb: UInt64 = 0
        Scanner(string: h).scanHexInt64(&rgb)
        let r = CGFloat((rgb >> 16) & 0xFF) / 255
        let g = CGFloat((rgb >> 8)  & 0xFF) / 255
        let b = CGFloat(rgb         & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: 1)
    }

    var hexString: String {
        guard let c = usingColorSpace(.sRGB) else { return "#888888" }
        return String(
            format: "#%02X%02X%02X",
            Int(c.redComponent * 255),
            Int(c.greenComponent * 255),
            Int(c.blueComponent * 255)
        )
    }
}

extension ButtonConfig {
    var resolvedSortLabel: String {
        let displayLabel = resolvedDisplayLabel
        return displayLabel.isEmpty ? keyBindingsDisplayName : displayLabel
    }

    var resolvedLabelFont: NSFont {
        var symbolicTraits: NSFontDescriptor.SymbolicTraits = []
        if labelBold { symbolicTraits.insert(.bold) }
        if labelItalic { symbolicTraits.insert(.italic) }

        let clampedSize = CGFloat(min(max(labelFontSize, 6), 36))
        let descriptor = NSFont.systemFont(ofSize: clampedSize).fontDescriptor.withSymbolicTraits(symbolicTraits)
        return NSFont(descriptor: descriptor, size: clampedSize) ?? NSFont.systemFont(
            ofSize: clampedSize,
            weight: labelBold ? .bold : .regular
        )
    }

    var resolvedLabelAttributes: [NSAttributedString.Key: Any] {
        [
            .font: resolvedLabelFont,
            .foregroundColor: NSColor.white,
        ]
    }

    var resolvedDisplayLabel: String {
        guard label.isEmpty else {
            return label
        }

        return keyBindingsDisplayName
    }

    var keyBindingsDisplayName: String {
        guard keyBindings.count > 1 else {
            let binding = keyBindings.first ?? ButtonKeyBinding(keyCode: keyCode, keyModifiers: keyModifiers)
            return Self.keyDisplayName(
                code: binding.keyCode,
                modifiers: NSEvent.ModifierFlags(rawValue: UInt(binding.keyModifiers))
            )
        }

        return "[" + keyBindings.map { binding in
            Self.keyDisplayName(
                code: binding.keyCode,
                modifiers: NSEvent.ModifierFlags(rawValue: UInt(binding.keyModifiers))
            )
        }.joined() + "]"
    }

    static func keyDisplayName(code: Int, modifiers: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []

        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }

        parts.append(keyName(code))
        return parts.joined()
    }

    private static func keyName(_ code: Int) -> String {
        let keyNames: [Int: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
            11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 31: "O", 32: "U",
            34: "I", 35: "P", 37: "L", 38: "J", 40: "K", 45: "N", 46: "M",
            36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋",
            123: "←", 124: "→", 125: "↓", 126: "↑",
            96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9",
            103: "F11", 109: "F10", 111: "F12",
            115: "Home", 116: "PgUp", 117: "Del", 119: "End", 121: "PgDn",
        ]

        return keyNames[code] ?? "key(\(code))"
    }
}
