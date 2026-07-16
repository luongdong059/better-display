import Carbon.HIToolbox
import Foundation

/// Phím tắt toàn cục bằng Carbon RegisterEventHotKey — không cần quyền
/// Accessibility. Đăng ký ⌥⌘0–⌥⌘9; callback nhận id 0–9.
final class HotKeyManager {
    var onHotKey: ((Int) -> Void)?

    private var hotKeyRefs: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?
    private static let signature: OSType = 0x4244_4B59 // 'BDKY'

    // kVK_ANSI_0..9 theo thứ tự id 0..9
    private static let keyCodes: [Int] = [
        kVK_ANSI_0, kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4,
        kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9,
    ]

    var isRegistered: Bool { !hotKeyRefs.isEmpty }

    func register() {
        guard !isRegistered else { return }

        if eventHandler == nil {
            var eventType = EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(
                GetApplicationEventTarget(),
                { _, event, userData -> OSStatus in
                    guard let event, let userData else { return noErr }
                    var hotKeyID = EventHotKeyID()
                    let err = GetEventParameter(
                        event, EventParamName(kEventParamDirectObject),
                        EventParamType(typeEventHotKeyID), nil,
                        MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
                    guard err == noErr, hotKeyID.signature == HotKeyManager.signature else { return noErr }
                    let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                    DispatchQueue.main.async {
                        manager.onHotKey?(Int(hotKeyID.id))
                    }
                    return noErr
                },
                1, &eventType,
                Unmanaged.passUnretained(self).toOpaque(),
                &eventHandler)
        }

        for (id, keyCode) in Self.keyCodes.enumerated() {
            var ref: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: Self.signature, id: UInt32(id))
            let status = RegisterEventHotKey(
                UInt32(keyCode), UInt32(optionKey | cmdKey),
                hotKeyID, GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                hotKeyRefs.append(ref)
            }
        }
    }

    func unregister() {
        for ref in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
    }

    deinit {
        unregister()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }
}
