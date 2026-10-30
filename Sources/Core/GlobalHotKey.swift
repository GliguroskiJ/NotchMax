import Foundation
import Carbon.HIToolbox

/// Globální klávesová zkratka přes Carbon `RegisterEventHotKey` (nevyžaduje oprávnění).
final class GlobalHotKey {
    static let shared = GlobalHotKey()

    static let defaultKeyCode: UInt32 = UInt32(kVK_ANSI_N)
    static let defaultModifiers: UInt32 = UInt32(optionKey | cmdKey)

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var handler: (() -> Void)?

    private init() {}

    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) -> Bool {
        unregister()
        self.handler = handler

        if handlerRef == nil {
            var eventType = EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            )
            let callback: EventHandlerUPP = { _, _, userData in
                guard let userData else { return noErr }
                let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { hotKey.fire() }
                return noErr
            }
            let userData = Unmanaged.passUnretained(self).toOpaque()
            var ref: EventHandlerRef?
            let status = InstallEventHandler(GetApplicationEventTarget(), callback, 1, &eventType, userData, &ref)
            guard status == noErr else {
                self.handler = nil
                return false
            }
            handlerRef = ref
        }

        let hotKeyID = EventHotKeyID(signature: OSType(0x4E4D4158), id: 1) // 'NMAX'
        var newRef: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &newRef)
        guard status == noErr, newRef != nil else {
            self.handler = nil
            return false
        }
        hotKeyRef = newRef
        return true
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        handler = nil
    }

    fileprivate func fire() {
        handler?()
    }
}
