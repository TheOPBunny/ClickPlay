import Carbon

// Maps gamepad buttons to macOS virtual key codes.
// Edit this file to remap any button to any key.
// Full list: https://eastmanreference.com/complete-list-of-applescript-key-codes

enum GamepadButton: String, CaseIterable {
    // D-Pad
    case dpadUp    = "D↑"
    case dpadDown  = "D↓"
    case dpadLeft  = "D←"
    case dpadRight = "D→"

    // Face buttons
    case faceA = "A"
    case faceB = "B"
    case faceX = "X"
    case faceY = "Y"

    // Shoulders
    case shoulderL  = "L"
    case shoulderR  = "R"
    case triggerL   = "ZL"
    case triggerZR  = "ZR"

    // Menu
    case start  = "START"
    case select = "SELECT"

    // Stick clicks
    case leftStick  = "LS"
    case rightStick = "RS"

    var keyCode: CGKeyCode {
        switch self {
        case .dpadUp:     return CGKeyCode(kVK_UpArrow)
        case .dpadDown:   return CGKeyCode(kVK_DownArrow)
        case .dpadLeft:   return CGKeyCode(kVK_LeftArrow)
        case .dpadRight:  return CGKeyCode(kVK_RightArrow)
        case .faceA:      return CGKeyCode(kVK_ANSI_Z)        // Z
        case .faceB:      return CGKeyCode(kVK_ANSI_X)        // X
        case .faceX:      return CGKeyCode(kVK_ANSI_A)        // A
        case .faceY:      return CGKeyCode(kVK_ANSI_S)        // S
        case .shoulderL:  return CGKeyCode(kVK_ANSI_Q)        // Q
        case .shoulderR:  return CGKeyCode(kVK_ANSI_W)        // W
        case .triggerL:   return CGKeyCode(kVK_ANSI_E)        // E
        case .triggerZR:  return CGKeyCode(kVK_ANSI_R)        // R
        case .start:      return CGKeyCode(kVK_Return)         // Return
        case .select:     return CGKeyCode(kVK_Space)          // Space
        case .leftStick:  return CGKeyCode(kVK_ANSI_C)        // C
        case .rightStick: return CGKeyCode(kVK_ANSI_V)        // V
        }
    }

    // Optional modifier flags for this button (e.g. .maskShift, .maskControl)
    var modifiers: CGEventFlags {
        return []
    }

    var displayLabel: String {
        return self.rawValue
    }

    var color: ButtonColor {
        switch self {
        case .faceA: return .green
        case .faceB: return .red
        case .faceX: return .blue
        case .faceY: return .yellow
        case .dpadUp, .dpadDown, .dpadLeft, .dpadRight: return .gray
        case .shoulderL, .shoulderR, .triggerL, .triggerZR: return .purple
        case .start, .select: return .dark
        case .leftStick, .rightStick: return .dark
        }
    }
}

enum ButtonColor {
    case red, green, blue, yellow, gray, purple, dark
}
