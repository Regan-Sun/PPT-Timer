import AppKit
import Carbon
import Foundation

enum CustomHotKeyAction: String, Codable, CaseIterable, Equatable {
    case start
    case stop
    case pause
    case reset

    var displayName: String {
        switch self {
        case .start: return "开始计时"
        case .stop: return "停止计时"
        case .pause: return "暂停/恢复"
        case .reset: return "重置"
        }
    }
}

struct HotKeyIdentity: Hashable {
    let keyCode: UInt32
    let modifiers: UInt32
}

enum HotKeyCaptureError: Error, Equatable {
    case ordinaryKeyNeedsModifier
    case unsupportedKey

    var message: String {
        switch self {
        case .ordinaryKeyNeedsModifier:
            return "字母、数字等普通按键必须搭配 Control、Option 或 Command。"
        case .unsupportedKey:
            return "这个按键暂不支持，请换一个组合。"
        }
    }
}

struct HotKeyBinding: Codable, Equatable {
    static let supportedModifierMask = UInt32(controlKey | optionKey | shiftKey | cmdKey)

    var keyCode: UInt32
    var modifiers: UInt32
    var keyLabel: String

    var identity: HotKeyIdentity {
        HotKeyIdentity(keyCode: keyCode, modifiers: modifiers & Self.supportedModifierMask)
    }

    var displayString: String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + keyLabel
    }

    mutating func normalize() {
        modifiers &= Self.supportedModifierMask
        keyLabel = keyLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if keyLabel.count == 1 { keyLabel = keyLabel.uppercased() }
    }

    static func capture(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        characters: String?
    ) -> Result<HotKeyBinding, HotKeyCaptureError> {
        let code = UInt32(keyCode)
        let modifiers = carbonModifiers(from: modifierFlags)
        guard let label = keyLabel(for: code, characters: characters) else {
            return .failure(.unsupportedKey)
        }
        if functionKeyLabels[code] == nil,
           modifiers & UInt32(controlKey | optionKey | cmdKey) == 0 {
            return .failure(.ordinaryKeyNeedsModifier)
        }
        return .success(HotKeyBinding(keyCode: code, modifiers: modifiers, keyLabel: label))
    }

    private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        return modifiers
    }

    private static func keyLabel(for keyCode: UInt32, characters: String?) -> String? {
        if let function = functionKeyLabels[keyCode] { return function }
        if let special = specialKeyLabels[keyCode] { return special }
        guard let characters = characters?.trimmingCharacters(in: .whitespacesAndNewlines),
              characters.count == 1 else { return nil }
        return characters.uppercased()
    }

    private static let functionKeyLabels: [UInt32: String] = [
        UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3",
        UInt32(kVK_F4): "F4", UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6",
        UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8", UInt32(kVK_F9): "F9",
        UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12",
        UInt32(kVK_F13): "F13", UInt32(kVK_F14): "F14", UInt32(kVK_F15): "F15",
        UInt32(kVK_F16): "F16", UInt32(kVK_F17): "F17", UInt32(kVK_F18): "F18",
        UInt32(kVK_F19): "F19"
    ]

    private static let specialKeyLabels: [UInt32: String] = [
        UInt32(kVK_Return): "Return",
        UInt32(kVK_Tab): "Tab",
        UInt32(kVK_Space): "Space",
        UInt32(kVK_Delete): "Delete",
        UInt32(kVK_ForwardDelete): "⌦",
        UInt32(kVK_LeftArrow): "←",
        UInt32(kVK_RightArrow): "→",
        UInt32(kVK_UpArrow): "↑",
        UInt32(kVK_DownArrow): "↓"
    ]
}

struct TimerShortcutBindings: Codable, Equatable {
    var start: HotKeyBinding
    var stop: HotKeyBinding
    var pause: HotKeyBinding
    var reset: HotKeyBinding

    static let defaults = TimerShortcutBindings(
        start: HotKeyBinding(keyCode: UInt32(kVK_F12), modifiers: 0, keyLabel: "F12"),
        stop: HotKeyBinding(keyCode: UInt32(kVK_F12), modifiers: UInt32(controlKey), keyLabel: "F12"),
        pause: HotKeyBinding(keyCode: UInt32(kVK_F11), modifiers: UInt32(controlKey), keyLabel: "F11"),
        reset: HotKeyBinding(
            keyCode: UInt32(kVK_F12),
            modifiers: UInt32(controlKey | optionKey),
            keyLabel: "F12"
        )
    )

    mutating func normalize() {
        start.normalize()
        stop.normalize()
        pause.normalize()
        reset.normalize()
    }

    func binding(for action: CustomHotKeyAction) -> HotKeyBinding {
        switch action {
        case .start: return start
        case .stop: return stop
        case .pause: return pause
        case .reset: return reset
        }
    }

    mutating func set(_ binding: HotKeyBinding, for action: CustomHotKeyAction) {
        switch action {
        case .start: start = binding
        case .stop: stop = binding
        case .pause: pause = binding
        case .reset: reset = binding
        }
    }
}

enum TimerShortcutValidationError: Equatable {
    case duplicate(first: CustomHotKeyAction, second: CustomHotKeyAction)
    case reserved(action: CustomHotKeyAction, reservedName: String)

    var message: String {
        switch self {
        case .duplicate(let first, let second):
            return "“\(first.displayName)”和“\(second.displayName)”不能使用同一个快捷键。"
        case .reserved(let action, let reservedName):
            return "“\(action.displayName)”与固定快捷键“\(reservedName)”冲突。"
        }
    }
}

enum TimerShortcutValidator {
    static func validationError(for shortcuts: TimerShortcutBindings) -> TimerShortcutValidationError? {
        var seen: [HotKeyIdentity: CustomHotKeyAction] = [:]
        for action in CustomHotKeyAction.allCases {
            let identity = shortcuts.binding(for: action).identity
            if let first = seen[identity] {
                return .duplicate(first: first, second: action)
            }
            if let reservedName = reservedShortcuts[identity] {
                return .reserved(action: action, reservedName: reservedName)
            }
            seen[identity] = action
        }
        return nil
    }

    private static let reservedShortcuts: [HotKeyIdentity: String] = {
        var shortcuts: [HotKeyIdentity: String] = [
            HotKeyIdentity(keyCode: UInt32(kVK_ANSI_M), modifiers: UInt32(controlKey | cmdKey)): "移至下个显示器",
            HotKeyIdentity(keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(controlKey | cmdKey)): "在所有显示器显示",
            HotKeyIdentity(keyCode: UInt32(kVK_Escape), modifiers: UInt32(cmdKey)): "退出"
        ]
        for (index, keyCode) in [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6].enumerated() {
            shortcuts[HotKeyIdentity(
                keyCode: UInt32(keyCode),
                modifiers: UInt32(controlKey | cmdKey)
            )] = "计时预设 \(index + 1)"
        }
        return shortcuts
    }()
}
