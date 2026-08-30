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
    private var hotKeyRefs: [HotKeyAction: EventHotKeyRef] = [:]
    private let actionHandler: (HotKeyAction) -> Void
    private(set) var activeCustomShortcuts: TimerShortcutBindings

    init(shortcuts: TimerShortcutBindings, actionHandler: @escaping (HotKeyAction) -> Void) {
        activeCustomShortcuts = shortcuts
        self.actionHandler = actionHandler
        installHandler()
        registerFixedShortcuts()
        if registerCustomShortcuts(shortcuts) != nil {
            unregisterCustomShortcuts()
            activeCustomShortcuts = .defaults
            _ = registerCustomShortcuts(.defaults)
        }
    }

    deinit {
        hotKeyRefs.values.forEach { _ = UnregisterEventHotKey($0) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }

    func updateCustomShortcuts(_ shortcuts: TimerShortcutBindings) -> HotKeyUpdateError? {
        if let validationError = TimerShortcutValidator.validationError(for: shortcuts) {
            return .validation(validationError)
        }

        let previous = activeCustomShortcuts
        unregisterCustomShortcuts()
        if let failure = registerCustomShortcuts(shortcuts) {
            unregisterCustomShortcuts()
            _ = registerCustomShortcuts(previous)
            return .registration(action: failure.action, status: failure.status)
        }
        activeCustomShortcuts = shortcuts
        return nil
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

    private func registerFixedShortcuts() {
        _ = register(.nextDisplay, keyCode: UInt32(kVK_ANSI_M), modifiers: UInt32(controlKey | cmdKey))
        _ = register(.toggleAllDisplays, keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(controlKey | cmdKey))
        _ = register(.quit, keyCode: UInt32(kVK_Escape), modifiers: UInt32(cmdKey))

        let functionKeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6]
        let presetActions: [HotKeyAction] = [.preset1, .preset2, .preset3, .preset4, .preset5, .preset6]
        for (key, action) in zip(functionKeys, presetActions) {
            _ = register(action, keyCode: UInt32(key), modifiers: UInt32(controlKey | cmdKey))
        }
    }

    private func registerCustomShortcuts(_ shortcuts: TimerShortcutBindings) -> RegistrationFailure? {
        for action in CustomHotKeyAction.allCases {
            let binding = shortcuts.binding(for: action)
            let hotKeyAction = action.hotKeyAction
            let status = register(hotKeyAction, keyCode: binding.keyCode, modifiers: binding.modifiers)
            if status != noErr {
                return RegistrationFailure(action: action, status: status)
            }
        }
        return nil
    }

    private func unregisterCustomShortcuts() {
        for action in CustomHotKeyAction.allCases {
            let hotKeyAction = action.hotKeyAction
            if let reference = hotKeyRefs.removeValue(forKey: hotKeyAction) {
                _ = UnregisterEventHotKey(reference)
            }
        }
    }

    private func register(_ action: HotKeyAction, keyCode: UInt32, modifiers: UInt32) -> OSStatus {
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
            hotKeyRefs[action] = hotKeyRef
        }
        return status
    }
}

private struct RegistrationFailure {
    let action: CustomHotKeyAction
    let status: OSStatus
}

enum HotKeyUpdateError {
    case validation(TimerShortcutValidationError)
    case registration(action: CustomHotKeyAction, status: OSStatus)

    var message: String {
        switch self {
        case .validation(let error):
            return error.message
        case .registration(let action, let status):
            return "macOS 无法注册“\(action.displayName)”的快捷键（错误码 \(status)）。已继续使用原快捷键。"
        }
    }
}

private extension CustomHotKeyAction {
    var hotKeyAction: HotKeyAction {
        switch self {
        case .start: return .start
        case .stop: return .stop
        case .pause: return .pause
        case .reset: return .reset
        }
    }
}
