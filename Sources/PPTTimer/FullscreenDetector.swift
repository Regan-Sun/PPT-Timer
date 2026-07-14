import AppKit
import CoreGraphics
import Foundation

struct DetectedFullscreenWindow: Equatable {
    let applicationName: String
    let bundleIdentifier: String?
    let title: String
}

final class FullscreenDetector {
    private let ownPID = ProcessInfo.processInfo.processIdentifier
    private let powerPointDetector = PowerPointSlideShowDetector()
    private let ignoredBundleIdentifiers: Set<String> = [
        "com.apple.finder",
        "com.apple.loginwindow",
        "com.apple.ScreenSaver.Engine",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui"
    ]

    func detect(powerPointOnly: Bool) -> DetectedFullscreenWindow? {
        let powerPointState = powerPointDetector.detect()
        if powerPointState == .running {
            return DetectedFullscreenWindow(
                applicationName: "Microsoft PowerPoint",
                bundleIdentifier: "com.microsoft.Powerpoint",
                title: "幻灯片放映"
            )
        }
        guard let windowInfo = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return nil }

        let screens = NSScreen.screens.compactMap { screen -> CGRect? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }
            return CGDisplayBounds(CGDirectDisplayID(number.uint32Value))
        }

        let runningApps = Dictionary(
            uniqueKeysWithValues: NSWorkspace.shared.runningApplications.map { ($0.processIdentifier, $0) }
        )

        if let wpsWindow = detectWPSPresentation(
            in: windowInfo,
            screens: screens,
            runningApps: runningApps
        ) {
            return wpsWindow
        }

        for window in windowInfo {
            guard let pidNumber = window[kCGWindowOwnerPID as String] as? NSNumber,
                  pidNumber.int32Value != ownPID,
                  let layer = window[kCGWindowLayer as String] as? NSNumber,
                  let boundsValue = window[kCGWindowBounds as String] else {
                continue
            }

            let pid = pid_t(pidNumber.int32Value)
            let application = runningApps[pid]
            let bundleIdentifier = application?.bundleIdentifier
            let ownerName = (window[kCGWindowOwnerName as String] as? String) ?? application?.localizedName ?? ""
            let title = (window[kCGWindowName as String] as? String) ?? ""
            let isPowerPoint = Self.isPowerPoint(
                bundleIdentifier: bundleIdentifier,
                applicationName: ownerName
            )
            let isWPS = Self.isWPS(
                bundleIdentifier: bundleIdentifier,
                applicationName: ownerName
            )
            let boundsDictionary = boundsValue as! CFDictionary
            guard layer.intValue == 0,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary),
                  screens.contains(where: { Self.rect(bounds, covers: $0) }) else { continue }

            if let bundleIdentifier, ignoredBundleIdentifiers.contains(bundleIdentifier) { continue }
            if ownerName.isEmpty { continue }
            if isWPS { continue }
            if powerPointOnly && !isPowerPoint && !isWPS {
                continue
            }
            if powerPointOnly && isPowerPoint && powerPointState == .notRunning { continue }

            return DetectedFullscreenWindow(
                applicationName: ownerName,
                bundleIdentifier: bundleIdentifier,
                title: title
            )
        }
        return nil
    }

    private func detectWPSPresentation(
        in windows: [[String: Any]],
        screens: [CGRect],
        runningApps: [pid_t: NSRunningApplication]
    ) -> DetectedFullscreenWindow? {
        var hasPresentationWindow = false
        var hasPresentationContent = false

        for window in windows {
            guard let pidNumber = window[kCGWindowOwnerPID as String] as? NSNumber else { continue }
            let application = runningApps[pid_t(pidNumber.int32Value)]
            guard Self.isNativeWPS(bundleIdentifier: application?.bundleIdentifier),
                  let layer = window[kCGWindowLayer as String] as? NSNumber,
                  let boundsValue = window[kCGWindowBounds as String] else { continue }

            let boundsDictionary = boundsValue as! CFDictionary
            guard let bounds = CGRect(dictionaryRepresentation: boundsDictionary) else { continue }
            let title = (window[kCGWindowName as String] as? String) ?? ""

            if Self.isWPSPresentationLayer(layer.intValue),
               screens.contains(where: { Self.rect(bounds, covers: $0) }) {
                hasPresentationWindow = true
            } else if layer.intValue == 0,
                      screens.contains(where: {
                          Self.isWPSPresentationContent(bounds: bounds, screen: $0, title: title)
                      }) {
                hasPresentationContent = true
            }
        }

        guard hasPresentationWindow && hasPresentationContent else { return nil }

        return DetectedFullscreenWindow(
            applicationName: "WPS Office",
            bundleIdentifier: "com.kingsoft.wpsoffice.mac",
            title: "幻灯片放映"
        )
    }

    static func rect(_ window: CGRect, covers screen: CGRect, tolerance: CGFloat = 4) -> Bool {
        abs(window.minX - screen.minX) <= tolerance &&
            abs(window.minY - screen.minY) <= tolerance &&
            abs(window.width - screen.width) <= tolerance &&
            abs(window.height - screen.height) <= tolerance
    }

    static func isPowerPoint(bundleIdentifier: String?, applicationName: String) -> Bool {
        bundleIdentifier?.caseInsensitiveCompare("com.microsoft.Powerpoint") == .orderedSame ||
            applicationName.localizedCaseInsensitiveContains("PowerPoint")
    }

    static func isWPS(bundleIdentifier: String?, applicationName: String) -> Bool {
        if let bundleIdentifier {
            return isNativeWPS(bundleIdentifier: bundleIdentifier)
        }
        return applicationName.localizedCaseInsensitiveContains("WPS Office")
    }

    static func isNativeWPS(bundleIdentifier: String?) -> Bool {
        bundleIdentifier?.caseInsensitiveCompare("com.kingsoft.wpsoffice.mac") == .orderedSame
    }

    static func isWPSPresentationLayer(_ layer: Int) -> Bool {
        layer == 2_147_483_630 || Int32(truncatingIfNeeded: layer) == -18
    }

    static func isWPSPresentationContent(
        bounds: CGRect,
        screen: CGRect,
        title: String,
        tolerance: CGFloat = 4
    ) -> Bool {
        guard title.isEmpty else { return false }
        let topInset = bounds.minY - screen.minY
        return topInset >= -tolerance && topInset <= 50 + tolerance &&
            abs(bounds.minX - screen.minX) <= tolerance &&
            abs(bounds.maxX - screen.maxX) <= tolerance &&
            abs(bounds.maxY - screen.maxY) <= tolerance &&
            bounds.height >= screen.height - 60
    }
}
