import Carbon.HIToolbox

/// Global shortcut via Carbon RegisterEventHotKey: no Input Monitoring / event tap needed (DECISIONS D5).
/// ponytail: single hotkey only; a recorder UI + multiple bindings when shortcuts become configurable.
final class HotKey {
    static let keyD = UInt32(kVK_ANSI_D)
    static let optionShift = UInt32(optionKey | shiftKey)

    struct RegistrationError: Error, CustomStringConvertible {
        let status: OSStatus
        var description: String { status == eventHotKeyExistsErr ? "already in use" : "OSStatus \(status)" }
    }

    nonisolated(unsafe) private var ref: EventHotKeyRef? // only touched in init + deinit
    nonisolated(unsafe) private var handler: EventHandlerRef?
    private let action: () -> Void

    init(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) throws {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated { hotKey.action() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)

        let id = EventHotKeyID(signature: OSType(0x4453_5259) /* "DSRY" */, id: 1)
        let status = RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr else {
            if let handler { RemoveEventHandler(handler) }
            throw RegistrationError(status: status)
        }
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
    }
}
