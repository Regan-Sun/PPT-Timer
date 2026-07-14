import Carbon
import Foundation

enum HotKeyAction: UInt32, CaseIterable {
    case start = 1
    case stop
    case pause
    case reset
    case nextDisplay
    case toggleAllDisplays
    case quit
    case preset1 = 101
    case preset2
    case preset3
    case preset4
    case preset5
    case preset6
}

final class HotKeyManager {
    private let signature: OSType = 0x50505454 // PPTT
    private var handlerRef: EventHandlerRef?
    private var hotKeyRefs: [EventHotKeyRef] = []
    private let actionHandler: (HotKeyAction) -> Void

    init(actionHandler: @escaping (HotKeyAction) -> Void) {
        self.actionHandler = actionHandler
        installHandler()
        registerDefaults()
    }

    deinit {
        hotKeyRefs.forEach { _ = UnregisterEventHotKey($0) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }

    private func installHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let event, let userData else { return noErr }
                var identifier = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &identifier
                )
                guard status == noErr else { return status }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                if identifier.signature == manager.signature,
                   let action = HotKeyAction(rawValue: identifier.id) {
                    manager.actionHandler(action)
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
    }

    private func registerDefaults() {
        register(.start, keyCode: UInt32(kVK_F12), modifiers: 0)
        register(.stop, keyCode: UInt32(kVK_F12), modifiers: UInt32(controlKey))
        register(.pause, keyCode: UInt32(kVK_F11), modifiers: UInt32(controlKey))
        register(.reset, keyCode: UInt32(kVK_F12), modifiers: UInt32(controlKey | optionKey))
        register(.nextDisplay, keyCode: UInt32(kVK_ANSI_M), modifiers: UInt32(controlKey | cmdKey))
        register(.toggleAllDisplays, keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(controlKey | cmdKey))
        register(.quit, keyCode: UInt32(kVK_Escape), modifiers: UInt32(cmdKey))

        let functionKeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6]
        let presetActions: [HotKeyAction] = [.preset1, .preset2, .preset3, .preset4, .preset5, .preset6]
        for (key, action) in zip(functionKeys, presetActions) {
            register(action, keyCode: UInt32(key), modifiers: UInt32(controlKey | cmdKey))
        }
    }

    private func register(_ action: HotKeyAction, keyCode: UInt32, modifiers: UInt32) {
        var hotKeyRef: EventHotKeyRef?
        let identifier = EventHotKeyID(signature: signature, id: action.rawValue)
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if status == noErr, let hotKeyRef {
            hotKeyRefs.append(hotKeyRef)
        }
    }
}
