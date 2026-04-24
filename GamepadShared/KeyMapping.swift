import Foundation

// GamepadButton identifies each button slot.
// Key codes and colors are now stored in ButtonConfig (inside a Profile).
// Edit profiles via the Configurator app or profiles.json in
// ~/Library/Application Support/OnScreenGamepad/

enum GamepadButton: String, CaseIterable, Codable {
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
    case shoulderL = "L"
    case shoulderR = "R"
    case triggerL  = "ZL"
    case triggerZR = "ZR"

    // Menu
    case start  = "START"
    case select = "SELECT"

    // Stick clicks
    case leftStick  = "LS"
    case rightStick = "RS"

    // User-added buttons
    case custom1 = "Custom 1"
    case custom2 = "Custom 2"
    case custom3 = "Custom 3"
    case custom4 = "Custom 4"
    case custom5 = "Custom 5"
    case custom6 = "Custom 6"
    case custom7 = "Custom 7"
    case custom8 = "Custom 8"

    static var customSlots: [GamepadButton] {
        [.custom1, .custom2, .custom3, .custom4, .custom5, .custom6, .custom7, .custom8]
    }
}
