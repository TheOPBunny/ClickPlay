import Cocoa

final class KeyInjector {

    static let shared = KeyInjector()
    private init() {}

    private struct KeyBinding: Hashable {
        let keyCode: CGKeyCode
        let modifiersRawValue: UInt
    }

    private var heldKeys = Set<KeyBinding>()
    private let queue = DispatchQueue(label: "com.gamepad.keyinjector", qos: .userInteractive)

    func pressRaw(_ keyCode: CGKeyCode, modifiers: NSEvent.ModifierFlags = []) {
        queue.async { [self] in
            let supportedModifiers = supportedModifiers(from: modifiers)
            let binding = KeyBinding(keyCode: keyCode, modifiersRawValue: supportedModifiers.rawValue)
            guard !heldKeys.contains(binding) else {
                NSLog("[KeyInjector] pressRaw \(keyCode) modifiers=\(binding.modifiersRawValue) — already held, skipping")
                return
            }
            let ok = postEvent(keyCode: keyCode, modifiers: supportedModifiers, keyDown: true)
            if ok {
                heldKeys.insert(binding)
            }
            NSLog("[KeyInjector] pressRaw \(keyCode) modifiers=\(binding.modifiersRawValue) posted=\(ok)")
        }
    }

    func releaseRaw(_ keyCode: CGKeyCode, modifiers: NSEvent.ModifierFlags = []) {
        queue.async { [self] in
            let supportedModifiers = supportedModifiers(from: modifiers)
            let binding = KeyBinding(keyCode: keyCode, modifiersRawValue: supportedModifiers.rawValue)
            heldKeys.remove(binding)
            let ok = postEvent(keyCode: keyCode, modifiers: supportedModifiers, keyDown: false)
            NSLog("[KeyInjector] releaseRaw \(keyCode) modifiers=\(binding.modifiersRawValue) posted=\(ok)")
        }
    }

    @discardableResult
    private func postEvent(keyCode: CGKeyCode, modifiers: NSEvent.ModifierFlags, keyDown: Bool) -> Bool {
        guard let src = CGEventSource(stateID: .hidSystemState) else {
            NSLog("[KeyInjector] ERROR: CGEventSource returned nil")
            return false
        }
        guard let evt = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: keyDown) else {
            NSLog("[KeyInjector] ERROR: CGEvent creation failed for keyCode \(keyCode)")
            return false
        }
        evt.flags = cgEventFlags(from: modifiers)
        evt.post(tap: .cgAnnotatedSessionEventTap)
        return true
    }

    private func supportedModifiers(from modifiers: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        modifiers.intersection([.command, .option, .control, .shift])
    }

    private func cgEventFlags(from modifiers: NSEvent.ModifierFlags) -> CGEventFlags {
        var flags: CGEventFlags = []

        if modifiers.contains(.command) { flags.insert(.maskCommand) }
        if modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if modifiers.contains(.control) { flags.insert(.maskControl) }
        if modifiers.contains(.shift) { flags.insert(.maskShift) }

        return flags
    }
}
