import Cocoa

/// Sends low-level CGEvent key presses to whatever process currently owns focus.
/// Because we post to .cgAnnotatedSessionEventTap (system-wide) the target app
/// never needs to be frontmost — the event is delivered to the focused process.
final class KeyInjector {

    static let shared = KeyInjector()
    private init() {}

    // Track held keys so we don't double-post keyDown for held buttons
    private var heldKeys = Set<CGKeyCode>()
    private let queue = DispatchQueue(label: "com.gamepad.keyinjector", qos: .userInteractive)

    func press(_ button: GamepadButton) {
        queue.async { [self] in
            let code = button.keyCode
            guard !heldKeys.contains(code) else { return }
            heldKeys.insert(code)
            postEvent(keyCode: code, keyDown: true, modifiers: button.modifiers)
        }
    }

    func release(_ button: GamepadButton) {
        queue.async { [self] in
            let code = button.keyCode
            heldKeys.remove(code)
            postEvent(keyCode: code, keyDown: false, modifiers: button.modifiers)
        }
    }

    // MARK: - Private

    private func postEvent(keyCode: CGKeyCode, keyDown: Bool, modifiers: CGEventFlags) {
        guard let src = CGEventSource(stateID: .hidSystemState) else { return }
        guard let evt = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: keyDown) else { return }

        if !modifiers.isEmpty {
            evt.flags = modifiers
        }

        // Post to the session event tap — delivered to the currently focused app
        evt.post(tap: .cgAnnotatedSessionEventTap)
    }
}
