import Cocoa

final class KeyInjector {

    static let shared = KeyInjector()
    private init() {
        queue.setSpecific(key: queueSpecificKey, value: ())
    }

    private struct KeyBinding: Hashable {
        let keyCode: CGKeyCode
        let modifiersRawValue: UInt
    }

    private var heldKeyCounts: [KeyBinding: Int] = [:]
    private let queue = DispatchQueue(label: "com.gamepad.keyinjector", qos: .userInteractive)
    private let queueSpecificKey = DispatchSpecificKey<Void>()

    func pressRaw(_ keyCode: CGKeyCode, modifiers: NSEvent.ModifierFlags = []) {
        queue.async { [self] in
            let supportedModifiers = supportedModifiers(from: modifiers)
            let binding = KeyBinding(keyCode: keyCode, modifiersRawValue: supportedModifiers.rawValue)
            if let heldCount = heldKeyCounts[binding], heldCount > 0 {
                heldKeyCounts[binding] = heldCount + 1
                debugLog("[KeyInjector] pressRaw \(keyCode) modifiers=\(binding.modifiersRawValue) - already held, owners=\(heldCount + 1), skipping")
                return
            }
            let ok = postEvent(keyCode: keyCode, modifiers: supportedModifiers, keyDown: true)
            if ok {
                heldKeyCounts[binding] = 1
            }
            debugLog("[KeyInjector] pressRaw \(keyCode) modifiers=\(binding.modifiersRawValue) posted=\(ok)")
        }
    }

    func releaseRaw(_ keyCode: CGKeyCode, modifiers: NSEvent.ModifierFlags = []) {
        queue.async { [self] in
            let supportedModifiers = supportedModifiers(from: modifiers)
            let binding = KeyBinding(keyCode: keyCode, modifiersRawValue: supportedModifiers.rawValue)
            guard let heldCount = heldKeyCounts[binding], heldCount > 0 else {
                debugLog("[KeyInjector] releaseRaw \(keyCode) modifiers=\(binding.modifiersRawValue) - not held, skipping")
                return
            }

            if heldCount > 1 {
                heldKeyCounts[binding] = heldCount - 1
                debugLog("[KeyInjector] releaseRaw \(keyCode) modifiers=\(binding.modifiersRawValue) owners=\(heldCount - 1), keeping held")
                return
            }

            heldKeyCounts.removeValue(forKey: binding)
            let ok = postEvent(keyCode: keyCode, modifiers: supportedModifiers, keyDown: false)
            debugLog("[KeyInjector] releaseRaw \(keyCode) modifiers=\(binding.modifiersRawValue) posted=\(ok)")
        }
    }

    func releaseAllHeldKeys() {
        if DispatchQueue.getSpecific(key: queueSpecificKey) != nil {
            releaseAllHeldKeysOnQueue()
            return
        }

        queue.sync {
            releaseAllHeldKeysOnQueue()
        }
    }

    private func releaseAllHeldKeysOnQueue() {
        let bindingsToRelease = heldKeyCounts.keys.sorted { lhs, rhs in
            if lhs.modifiersRawValue != rhs.modifiersRawValue {
                return lhs.modifiersRawValue < rhs.modifiersRawValue
            }

            return lhs.keyCode < rhs.keyCode
        }
        heldKeyCounts.removeAll()

        for binding in bindingsToRelease {
            let modifiers = NSEvent.ModifierFlags(rawValue: binding.modifiersRawValue)
            let ok = postEvent(keyCode: binding.keyCode, modifiers: modifiers, keyDown: false)
            debugLog("[KeyInjector] releaseAllHeldKeys \(binding.keyCode) modifiers=\(binding.modifiersRawValue) posted=\(ok)")
        }
    }

    @discardableResult
    private func postEvent(keyCode: CGKeyCode, modifiers: NSEvent.ModifierFlags, keyDown: Bool) -> Bool {
        guard let src = CGEventSource(stateID: .hidSystemState) else {
            errorLog("[KeyInjector] ERROR: CGEventSource returned nil")
            return false
        }
        guard let evt = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: keyDown) else {
            errorLog("[KeyInjector] ERROR: CGEvent creation failed for keyCode \(keyCode)")
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
