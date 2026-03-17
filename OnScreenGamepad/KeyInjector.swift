import Cocoa

final class KeyInjector {

    static let shared = KeyInjector()
    private init() {}

    private var heldKeys = Set<CGKeyCode>()
    private let queue = DispatchQueue(label: "com.gamepad.keyinjector", qos: .userInteractive)

    func pressRaw(_ keyCode: CGKeyCode) {
        queue.async { [self] in
            guard !heldKeys.contains(keyCode) else {
                NSLog("[KeyInjector] pressRaw \(keyCode) — already held, skipping")
                return
            }
            heldKeys.insert(keyCode)
            let ok = postEvent(keyCode: keyCode, keyDown: true)
            NSLog("[KeyInjector] pressRaw \(keyCode) posted=\(ok)")
        }
    }

    func releaseRaw(_ keyCode: CGKeyCode) {
        queue.async { [self] in
            heldKeys.remove(keyCode)
            let ok = postEvent(keyCode: keyCode, keyDown: false)
            NSLog("[KeyInjector] releaseRaw \(keyCode) posted=\(ok)")
        }
    }

    @discardableResult
    private func postEvent(keyCode: CGKeyCode, keyDown: Bool) -> Bool {
        guard let src = CGEventSource(stateID: .hidSystemState) else {
            NSLog("[KeyInjector] ERROR: CGEventSource returned nil")
            return false
        }
        guard let evt = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: keyDown) else {
            NSLog("[KeyInjector] ERROR: CGEvent creation failed for keyCode \(keyCode)")
            return false
        }
        evt.post(tap: .cgAnnotatedSessionEventTap)
        return true
    }
}
