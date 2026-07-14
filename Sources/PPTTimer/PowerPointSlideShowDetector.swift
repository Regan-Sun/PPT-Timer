import AppKit
import Foundation

enum PowerPointSlideShowState: Equatable {
    case notRunning
    case running
    case unavailable
}

final class PowerPointSlideShowDetector {
    private let bundleIdentifier = "com.microsoft.Powerpoint"

    func detect() -> PowerPointSlideShowState {
        guard NSWorkspace.shared.runningApplications.contains(where: {
            $0.bundleIdentifier?.caseInsensitiveCompare(bundleIdentifier) == .orderedSame
        }) else {
            return .notRunning
        }

        let source = """
        tell application "Microsoft PowerPoint"
            try
                return (count of slide show windows) > 0
            on error
                return false
            end try
        end tell
        """
        guard let script = NSAppleScript(source: source) else { return .unavailable }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        guard error == nil else { return .unavailable }
        return result.booleanValue ? .running : .notRunning
    }
}
