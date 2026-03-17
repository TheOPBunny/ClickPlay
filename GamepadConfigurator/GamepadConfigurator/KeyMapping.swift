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
}
