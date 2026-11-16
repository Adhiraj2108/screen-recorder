import Carbon.HIToolbox

/// A system-wide shortcut that works while another app (Figma, a browser) is in front.
///
/// Uses the Carbon hot key API, which needs no Accessibility permission.
@MainActor
final class GlobalShortcut {
    /// ⌥⇧⌘R: rarely used by other apps, unlike ⌘⇧R (browser hard reload).
    static let label = "⌥⇧⌘R"

    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: @MainActor () -> Void

    /// False when another app already owns the key combination.
    private(set) var isRegistered = false

    init(action: @escaping @MainActor () -> Void) {
        self.action = action
        register()
    }

    private func register() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let shortcut = Unmanaged<GlobalShortcut>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated { shortcut.action() }
            return noErr
        }, 1, &eventType, context, &handler)
        guard installed == noErr else { return }

        let id = EventHotKeyID(signature: OSType(0x5352_4543), id: 1) // "SREC"
        let modifiers = UInt32(cmdKey | shiftKey | optionKey)
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_R), modifiers, id, GetApplicationEventTarget(), 0, &hotKey)
        isRegistered = status == noErr
    }
}
