import AppKit
import Foundation

enum OverlayPosition: String, Codable, CaseIterable, Identifiable {
    case topLeft
    case topCenter
    case topRight
    case bottomLeft
    case bottomCenter
    case bottomRight

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .topLeft: return "左上"
        case .topCenter: return "中上"
        case .topRight: return "右上"
        case .bottomLeft: return "左下"
        case .bottomCenter: return "中下"
        case .bottomRight: return "右下"
        }
    }
}

struct OverlayPlacement: Codable, Equatable {
    var xFraction: Double
    var yFraction: Double

    mutating func normalize() {
        xFraction = min(max(xFraction, 0), 1)
        yFraction = min(max(yFraction, 0), 1)
    }
}

struct TimerConfiguration: Codable, Equatable {
    var duration: Int = 1_200
    var warningTime: Int = 120
    var automaticDetection = true
    var powerPointOnly = true
    var manualModeSuppressesDetection = true
    var stopResetsTimer = false

    var playWarningSound = true
    var playFinishSound = true

    var opacity = 0.71
    var backgroundColor = "FFFFAA"
    var textColor = "000000"
    var warningColor = "9D1000"
    var timeoutColor = "FF0000"
    var fontName = "PingFang SC"
    var fontSize = 36.0
    var boldFont = true
    var width = 200.0
    var height = 60.0
    var position = OverlayPosition.topRight
    var margin = 8.0
    var customPosition: OverlayPlacement?

    var showOnAllDisplays = false
    var selectedDisplay = 0
    var shortcuts: TimerShortcutBindings?

    var effectiveShortcuts: TimerShortcutBindings {
        shortcuts ?? .defaults
    }

    mutating func normalize() {
        duration = min(max(duration, 1), 359_999)
        warningTime = min(max(warningTime, 0), duration)
        opacity = min(max(opacity, 0.05), 1.0)
        fontSize = min(max(fontSize, 12), 160)
        width = min(max(width, 100), 1_200)
        height = min(max(height, 36), 400)
        margin = min(max(margin, 0), 400)
        selectedDisplay = max(selectedDisplay, 0)
        customPosition?.normalize()
        var normalizedShortcuts = effectiveShortcuts
        normalizedShortcuts.normalize()
        shortcuts = TimerShortcutValidator.validationError(for: normalizedShortcuts) == nil
            ? normalizedShortcuts
            : .defaults

        backgroundColor = Self.validHex(backgroundColor, fallback: "FFFFAA")
        textColor = Self.validHex(textColor, fallback: "000000")
        warningColor = Self.validHex(warningColor, fallback: "9D1000")
        timeoutColor = Self.validHex(timeoutColor, fallback: "FF0000")
        if fontName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fontName = "PingFang SC"
        }
    }

    private static func validHex(_ value: String, fallback: String) -> String {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
            .uppercased()
        guard normalized.count == 6,
              UInt64(normalized, radix: 16) != nil else { return fallback }
        return normalized
    }
}

struct TimerPreset: Identifiable {
    let id: Int
    let name: String
    let duration: Int
    let warningTime: Int

    static let defaults = [
        TimerPreset(id: 1, name: "10 分钟", duration: 600, warningTime: 60),
        TimerPreset(id: 2, name: "20 分钟", duration: 1_200, warningTime: 120),
        TimerPreset(id: 3, name: "30 分钟", duration: 1_800, warningTime: 180),
        TimerPreset(id: 4, name: "45 分钟", duration: 2_700, warningTime: 300),
        TimerPreset(id: 5, name: "1 小时", duration: 3_600, warningTime: 300),
        TimerPreset(id: 6, name: "5 秒测试", duration: 5, warningTime: 3)
    ]
}

final class ConfigurationStore {
    private let defaults: UserDefaults
    private let key = "PPTTimer.configuration.v2"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> TimerConfiguration {
        guard let data = defaults.data(forKey: key),
              var configuration = try? JSONDecoder().decode(TimerConfiguration.self, from: data) else {
            return TimerConfiguration()
        }
        configuration.normalize()
        return configuration
    }

    func save(_ configuration: TimerConfiguration) {
        var normalized = configuration
        normalized.normalize()
        guard let data = try? JSONEncoder().encode(normalized) else { return }
        defaults.set(data, forKey: key)
    }
}

extension NSColor {
    convenience init(hex: String, fallback: NSColor = .black) {
        let clean = hex.replacingOccurrences(of: "#", with: "")
        guard clean.count == 6, let value = UInt64(clean, radix: 16) else {
            self.init(cgColor: fallback.cgColor)!
            return
        }
        self.init(
            calibratedRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    var hexRGBString: String {
        guard let rgb = usingColorSpace(.sRGB) else { return "000000" }
        return String(
            format: "%02X%02X%02X",
            Int(round(rgb.redComponent * 255)),
            Int(round(rgb.greenComponent * 255)),
            Int(round(rgb.blueComponent * 255))
        )
    }
}
