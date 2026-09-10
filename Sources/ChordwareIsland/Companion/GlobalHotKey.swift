import AppKit
import Carbon.HIToolbox

/// A system-wide keyboard shortcut.
///
/// Uses Carbon's RegisterEventHotKey rather than an NSEvent global monitor,
/// because monitoring keystrokes needs the accessibility permission and
/// registering a hot key does not. A music app should not have to ask for the
/// right to watch everything you type.
///
/// This is also the only reliable way to reach Chordware on a notched MacBook:
/// with a busy menu bar the status item ends up behind the notch, where it
/// cannot be clicked at all.
@MainActor
public final class GlobalHotKey {
    /// Carbon handlers are C function pointers and cannot capture context, so
    /// live instances are looked up by id.
    private static var registry: [UInt32: GlobalHotKey] = [:]
    private static var nextID: UInt32 = 1
    private static var handlerInstalled = false

    private let id: UInt32
    private let action: () -> Void
    private var reference: EventHotKeyRef?

    public init(action: @escaping () -> Void) {
        self.action = action
        id = Self.nextID
        Self.nextID += 1
    }

    /// `keyCode` is a virtual key code (`kVK_ANSI_C` and friends); `modifiers`
    /// are Carbon masks such as `cmdKey | optionKey | controlKey`.
    @discardableResult
    public func register(keyCode: UInt32, modifiers: UInt32) -> Bool {
        Self.installHandlerIfNeeded()
        let hotKeyID = EventHotKeyID(signature: OSType(0x43485744), id: id) // 'CHWD'
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        reference = ref
        Self.registry[id] = self
        return true
    }

    public func unregister() {
        if let reference { UnregisterEventHotKey(reference) }
        reference = nil
        Self.registry.removeValue(forKey: id)
    }

    private static func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard status == noErr else { return status }
            let id = hotKeyID.id
            Task { @MainActor in GlobalHotKey.registry[id]?.action() }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
