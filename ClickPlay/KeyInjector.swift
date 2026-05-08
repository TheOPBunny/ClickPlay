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
        evt.flags = cgEventFlags(from: modifiers, keyCode: keyCode, keyDown: keyDown)
        evt.post(tap: .cgAnnotatedSessionEventTap)
        return true
    }

    private func supportedModifiers(from modifiers: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        modifiers.intersection([.command, .option, .control, .shift])
    }

    private func cgEventFlags(from modifiers: NSEvent.ModifierFlags, keyCode: CGKeyCode, keyDown: Bool) -> CGEventFlags {
        var flags = heldModifierFlags()

        if modifiers.contains(.command) { flags.insert(.maskCommand) }
        if modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if modifiers.contains(.control) { flags.insert(.maskControl) }
        if modifiers.contains(.shift) { flags.insert(.maskShift) }
        if keyDown, let modifierFlag = cgEventFlag(forModifierKeyCode: keyCode) {
            flags.insert(modifierFlag)
        }

        return flags
    }

    private func heldModifierFlags() -> CGEventFlags {
        heldKeyCounts.keys.reduce(into: CGEventFlags()) { flags, binding in
            if let modifierFlag = cgEventFlag(forModifierKeyCode: binding.keyCode) {
                flags.insert(modifierFlag)
            }
        }
    }

    private func cgEventFlag(forModifierKeyCode keyCode: CGKeyCode) -> CGEventFlags? {
        switch keyCode {
        case 54, 55:
            return .maskCommand
        case 56, 60:
            return .maskShift
        case 57:
            return .maskAlphaShift
        case 58, 61:
            return .maskAlternate
        case 59, 62:
            return .maskControl
        default:
            return nil
        }
    }
}

final class SystemEventInjector {

    static let shared = SystemEventInjector()
    private init() {}

    func trigger(_ event: SystemEvent) {
        switch event {
        case .missionControl:
            KeyInjector.shared.pressRaw(126, modifiers: .control)
            KeyInjector.shared.releaseRaw(126, modifiers: .control)
        case .brightnessDown:
            postSystemKeyTap(type: 3)
        case .brightnessUp:
            postSystemKeyTap(type: 2)
        case .volumeDown:
            postSystemKeyTap(type: 1)
        case .volumeUp:
            postSystemKeyTap(type: 0)
        case .mute:
            postSystemKeyTap(type: 7)
        case .playPause:
            postSystemKeyTap(type: 16)
        case .nextTrack:
            postSystemKeyTap(type: 17)
        case .previousTrack:
            postSystemKeyTap(type: 18)
        case .launchpad:
            postSystemKeyTap(type: 13)
        }
    }

    private func postSystemKeyTap(type: Int) {
        postSystemKey(type: type, isDown: true)
        postSystemKey(type: type, isDown: false)
    }

    private func postSystemKey(type: Int, isDown: Bool) {
        let keyState = isDown ? 0xA : 0xB
        let data1 = (type << 16) | (keyState << 8)
        guard let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(keyState << 8)),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: data1,
            data2: -1
        )?.cgEvent else {
            errorLog("[SystemEventInjector] ERROR: system event creation failed for type \(type)")
            return
        }

        event.post(tap: .cghidEventTap)
    }
}
