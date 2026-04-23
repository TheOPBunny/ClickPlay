import Foundation

enum ButtonInteractionMode: String, Codable {
    case momentary
    case toggleHold
}

// MARK: - ButtonConfig
// Per-button layout and appearance settings stored in a profile.

struct ButtonConfig: Codable {
    var x: Double           // center X, as fraction of pad width  (0.0–1.0)
    var y: Double           // center Y, as fraction of pad height (0.0–1.0)
    var width: Double       // as fraction of pad width
    var height: Double      // as fraction of pad height
    var colorHex: String    // "#RRGGBB"
    var keyCode: Int        // CGKeyCode raw value
    var keyModifiers: Int   // NSEvent.ModifierFlags raw value
    var label: String       // display label (can differ from button name)
    var labelFontSize: Double
    var labelBold: Bool
    var labelItalic: Bool
    var enabled: Bool
    var interactionMode: ButtonInteractionMode

    private enum CodingKeys: String, CodingKey {
        case x
        case y
        case width
        case height
        case colorHex
        case keyCode
        case keyModifiers
        case label
        case labelFontSize
        case labelBold
        case labelItalic
        case enabled
        case interactionMode
    }

    init(
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        colorHex: String,
        keyCode: Int,
        keyModifiers: Int = 0,
        label: String,
        labelFontSize: Double = 11,
        labelBold: Bool = true,
        labelItalic: Bool = false,
        enabled: Bool,
        interactionMode: ButtonInteractionMode = .momentary
    ) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.colorHex = colorHex
        self.keyCode = keyCode
        self.keyModifiers = keyModifiers
        self.label = label
        self.labelFontSize = labelFontSize
        self.labelBold = labelBold
        self.labelItalic = labelItalic
        self.enabled = enabled
        self.interactionMode = interactionMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        x = try container.decode(Double.self, forKey: .x)
        y = try container.decode(Double.self, forKey: .y)
        width = try container.decode(Double.self, forKey: .width)
        height = try container.decode(Double.self, forKey: .height)
        colorHex = try container.decode(String.self, forKey: .colorHex)
        keyCode = try container.decode(Int.self, forKey: .keyCode)
        keyModifiers = try container.decodeIfPresent(Int.self, forKey: .keyModifiers) ?? 0
        label = try container.decode(String.self, forKey: .label)
        labelFontSize = try container.decodeIfPresent(Double.self, forKey: .labelFontSize) ?? 11
        labelBold = try container.decodeIfPresent(Bool.self, forKey: .labelBold) ?? true
        labelItalic = try container.decodeIfPresent(Bool.self, forKey: .labelItalic) ?? false
        enabled = try container.decode(Bool.self, forKey: .enabled)
        interactionMode = try container.decodeIfPresent(ButtonInteractionMode.self, forKey: .interactionMode) ?? .momentary
    }
}

// MARK: - Profile

struct Profile: Codable, Identifiable {
    var id: UUID
    var name: String
    var opacity: Double                              // 0.25–1.0
    var compatibilityMode: Bool
    var padWidth: Double                             // absolute pts
    var padHeight: Double
    var buttons: [String: ButtonConfig]              // keyed by GamepadButton.rawValue

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case opacity
        case compatibilityMode
        case padWidth
        case padHeight
        case buttons
    }

    init(
        id: UUID,
        name: String,
        opacity: Double,
        compatibilityMode: Bool = false,
        padWidth: Double,
        padHeight: Double,
        buttons: [String: ButtonConfig]
    ) {
        self.id = id
        self.name = name
        self.opacity = opacity
        self.compatibilityMode = compatibilityMode
        self.padWidth = padWidth
        self.padHeight = padHeight
        self.buttons = buttons
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        opacity = try container.decode(Double.self, forKey: .opacity)
        compatibilityMode = try container.decodeIfPresent(Bool.self, forKey: .compatibilityMode) ?? false
        padWidth = try container.decode(Double.self, forKey: .padWidth)
        padHeight = try container.decode(Double.self, forKey: .padHeight)
        buttons = try container.decode([String: ButtonConfig].self, forKey: .buttons)
    }

    // Default profile matching the original hardcoded layout
    static func makeDefault(name: String = "Default") -> Profile {
        let W: Double = 420
        let H: Double = 300

        func cx(_ abs: Double) -> Double { abs / W }
        func cy(_ abs: Double) -> Double { abs / H }
        func bw(_ abs: Double) -> Double { abs / W }
        func bh(_ abs: Double) -> Double { abs / H }

        var btns: [String: ButtonConfig] = [:]

        func add(_ btn: GamepadButton, x: Double, y: Double,
                 w: Double, h: Double, hex: String, key: Int) {
            btns[btn.rawValue] = ButtonConfig(
                x: cx(x), y: cy(y),
                width: bw(w), height: bh(h),
                colorHex: hex,
                keyCode: key,
                keyModifiers: 0,
                label: btn.rawValue,
                enabled: true
            )
        }

        // Shoulders / triggers
        add(.triggerL,  x: 38,    y: H - 24,  w: 52, h: 32, hex: "#8844DD", key: 14)  // E
        add(.shoulderL, x: 38,    y: H - 60,  w: 52, h: 32, hex: "#8844DD", key: 12)  // Q
        add(.triggerZR, x: W - 38, y: H - 24, w: 52, h: 32, hex: "#8844DD", key: 15)  // R
        add(.shoulderR, x: W - 38, y: H - 60, w: 52, h: 32, hex: "#8844DD", key: 13)  // W

        // D-pad
        add(.dpadUp,    x: 82,    y: H - 111, w: 40, h: 40, hex: "#666666", key: 126)
        add(.dpadDown,  x: 82,    y: H - 199, w: 40, h: 40, hex: "#666666", key: 125)
        add(.dpadLeft,  x: 38,    y: H - 155, w: 40, h: 40, hex: "#666666", key: 123)
        add(.dpadRight, x: 126,   y: H - 155, w: 40, h: 40, hex: "#666666", key: 124)

        // Start / Select
        add(.select,    x: W / 2 - 36, y: H - 91, w: 52, h: 28, hex: "#333333", key: 49)  // Space
        add(.start,     x: W / 2 + 36, y: H - 91, w: 52, h: 28, hex: "#333333", key: 36)  // Return

        // Face buttons
        add(.faceY,     x: W - 82,  y: H - 111, w: 44, h: 44, hex: "#CCAA00", key: 1)   // S
        add(.faceA,     x: W - 82,  y: H - 199, w: 44, h: 44, hex: "#229933", key: 6)   // Z
        add(.faceX,     x: W - 126, y: H - 155, w: 44, h: 44, hex: "#2255CC", key: 0)   // A
        add(.faceB,     x: W - 38,  y: H - 155, w: 44, h: 44, hex: "#CC2222", key: 7)   // X

        // Stick clicks
        add(.leftStick,  x: 82,    y: H - 240, w: 40, h: 40, hex: "#2a2a2a", key: 8)   // C
        add(.rightStick, x: W - 82, y: H - 240, w: 40, h: 40, hex: "#2a2a2a", key: 9)  // V

        return Profile(
            id: UUID(),
            name: name,
            opacity: 0.90,
            compatibilityMode: false,
            padWidth: W,
            padHeight: H,
            buttons: btns
        )
    }
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

        return Self.keyDisplayName(code: keyCode, modifiers: NSEvent.ModifierFlags(rawValue: UInt(keyModifiers)))
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
