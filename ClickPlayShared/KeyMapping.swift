import Foundation

// GamepadButton identifies a profile button by stable profile storage key.
// Built-in constants exist only for legacy profile compatibility and starter
// templates; user-created buttons use generated raw values.
struct GamepadButton: RawRepresentable, Hashable, Codable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    // Legacy/template buttons
    static let dpadUp = GamepadButton("D↑")
    static let dpadDown = GamepadButton("D↓")
    static let dpadLeft = GamepadButton("D←")
    static let dpadRight = GamepadButton("D→")
    static let faceA = GamepadButton("A")
    static let faceB = GamepadButton("B")
    static let faceX = GamepadButton("X")
    static let faceY = GamepadButton("Y")
    static let shoulderL = GamepadButton("L")
    static let shoulderR = GamepadButton("R")
    static let triggerL = GamepadButton("ZL")
    static let triggerZR = GamepadButton("ZR")
    static let start = GamepadButton("START")
    static let select = GamepadButton("SELECT")
    static let leftStick = GamepadButton("LS")
    static let rightStick = GamepadButton("RS")

    static let legacyButtons: [GamepadButton] = [
        .triggerL, .shoulderL, .triggerZR, .shoulderR,
        .dpadUp, .dpadDown, .dpadLeft, .dpadRight,
        .select, .start,
        .faceY, .faceA, .faceX, .faceB,
        .leftStick, .rightStick,
    ]

    static func generated() -> GamepadButton {
        GamepadButton("button:\(UUID().uuidString)")
    }

    static func subProfileSwitch(targetID: UUID) -> GamepadButton {
        GamepadButton("subProfileSwitch:\(targetID.uuidString)")
    }

    var isGenerated: Bool {
        rawValue.hasPrefix("button:")
    }

    var isSubProfileSwitch: Bool {
        rawValue.hasPrefix("subProfileSwitch:")
    }

    var subProfileSwitchTargetID: UUID? {
        guard isSubProfileSwitch else {
            return nil
        }

        return UUID(uuidString: String(rawValue.dropFirst("subProfileSwitch:".count)))
    }
}
