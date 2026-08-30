import AppKit
import Carbon
import CoreGraphics
import Foundation
import Testing
@testable import PPTTimer

struct PPTTimerTests {
    @Test func formatsCountdownAndOvertime() {
        #expect(CountdownMath.format(seconds: 1_200) == "20:00")
        #expect(CountdownMath.format(seconds: 3_661) == "1:01:01")
        #expect(CountdownMath.format(seconds: -9) == "+00:09")
    }

    @Test func remainingUsesWholeElapsedSeconds() {
        #expect(CountdownMath.remaining(duration: 10, elapsed: 0.99) == 10)
        #expect(CountdownMath.remaining(duration: 10, elapsed: 1.0) == 9)
        #expect(CountdownMath.remaining(duration: 10, elapsed: 11.2) == -1)
    }

    @Test func configurationNormalization() {
        var configuration = TimerConfiguration()
        configuration.duration = 0
        configuration.warningTime = 999
        configuration.opacity = 4
        configuration.backgroundColor = "not-a-color"
        configuration.fontName = "  "
        configuration.normalize()

        #expect(configuration.duration == 1)
        #expect(configuration.warningTime == 1)
        #expect(configuration.opacity == 1)
        #expect(configuration.backgroundColor == "FFFFAA")
        #expect(configuration.fontName == "PingFang SC")
    }

    @Test func fullscreenRectangleMatchingAllowsSmallRoundingDifference() {
        let screen = CGRect(x: 0, y: 0, width: 1_920, height: 1_080)
        #expect(FullscreenDetector.rect(CGRect(x: 1, y: -1, width: 1_918, height: 1_082), covers: screen))
        #expect(!FullscreenDetector.rect(CGRect(x: 0, y: 0, width: 1_200, height: 800), covers: screen))
    }

    @Test func powerPointIdentification() {
        #expect(FullscreenDetector.isPowerPoint(bundleIdentifier: "com.microsoft.Powerpoint", applicationName: "Microsoft PowerPoint"))
        #expect(FullscreenDetector.isPowerPoint(bundleIdentifier: nil, applicationName: "POWERPOINT Slide Show"))
        #expect(!FullscreenDetector.isPowerPoint(bundleIdentifier: "com.apple.Keynote", applicationName: "Keynote"))
    }

    @Test func wpsPresentationIdentification() {
        #expect(FullscreenDetector.isWPS(bundleIdentifier: "com.kingsoft.wpsoffice.mac", applicationName: "WPS Office"))
        #expect(FullscreenDetector.isNativeWPS(bundleIdentifier: "com.kingsoft.wpsoffice.mac"))
        #expect(FullscreenDetector.isWPSPresentationLayer(2_147_483_630))
        #expect(!FullscreenDetector.isWPSPresentationLayer(0))
        #expect(FullscreenDetector.isWPSPresentationContent(
            bounds: CGRect(x: 0, y: 33, width: 1_470, height: 923),
            screen: CGRect(x: 0, y: 0, width: 1_470, height: 956),
            title: ""
        ))
        #expect(!FullscreenDetector.isWPSPresentationContent(
            bounds: CGRect(x: 75, y: 33, width: 1_362, height: 822),
            screen: CGRect(x: 0, y: 0, width: 1_470, height: 956),
            title: "presentation.pptx"
        ))
        #expect(!FullscreenDetector.isWPS(bundleIdentifier: "com.apple.Keynote", applicationName: "Keynote"))
        #expect(!FullscreenDetector.isWPS(bundleIdentifier: "com.parallels.winapp.wps", applicationName: "WPS Office"))
    }

    @Test func overlayDragThresholdKeepsSmallMovementAsClick() {
        #expect(!OverlayGeometry.isDrag(delta: CGSize(width: 4, height: 0)))
        #expect(OverlayGeometry.isDrag(delta: CGSize(width: 4.01, height: 0)))
    }

    @Test func overlayOriginIsClampedInsideVisibleFrame() {
        let visibleFrame = CGRect(x: 100, y: 200, width: 1_000, height: 800)
        let panelSize = CGSize(width: 200, height: 60)

        #expect(OverlayGeometry.clampedOrigin(
            CGPoint(x: -500, y: 2_000),
            panelSize: panelSize,
            visibleFrame: visibleFrame
        ) == CGPoint(x: 100, y: 940))
    }

    @Test func overlayPlacementRestoresSameRelativePositionOnAnotherDisplay() {
        let placement = OverlayGeometry.placement(
            for: CGPoint(x: 400, y: 350),
            panelSize: CGSize(width: 200, height: 100),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_000, height: 800)
        )

        #expect(abs(placement.xFraction - 0.5) < 0.000_001)
        #expect(abs(placement.yFraction - 0.5) < 0.000_001)
        #expect(OverlayGeometry.origin(
            for: placement,
            panelSize: CGSize(width: 200, height: 100),
            visibleFrame: CGRect(x: 100, y: 50, width: 2_000, height: 1_000)
        ) == CGPoint(x: 1_000, y: 500))
    }

    @Test func customOverlayPlacementIsNormalizedAndPersisted() {
        let suiteName = "PPTTimerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ConfigurationStore(defaults: defaults)
        var configuration = TimerConfiguration()
        configuration.customPosition = OverlayPlacement(xFraction: -0.25, yFraction: 1.25)

        store.save(configuration)
        let loaded = store.load()

        #expect(loaded.customPosition == OverlayPlacement(xFraction: 0, yFraction: 1))
    }

    @Test func functionKeyCanBeCapturedWithoutModifiers() throws {
        let binding = try HotKeyBinding.capture(
            keyCode: UInt16(kVK_F12),
            modifierFlags: [],
            characters: nil
        ).get()

        #expect(binding == HotKeyBinding(keyCode: UInt32(kVK_F12), modifiers: 0, keyLabel: "F12"))
        #expect(binding.displayString == "F12")
    }

    @Test func ordinaryKeyWithoutCommandControlOrOptionIsRejected() {
        let result = HotKeyBinding.capture(
            keyCode: UInt16(kVK_ANSI_A),
            modifierFlags: [.shift],
            characters: "A"
        )

        switch result {
        case .success:
            Issue.record("Shift-only ordinary key unexpectedly accepted")
        case .failure(let error):
            #expect(error == .ordinaryKeyNeedsModifier)
        }
    }

    @Test func shortcutDisplayUsesMacModifierOrder() throws {
        let binding = try HotKeyBinding.capture(
            keyCode: UInt16(kVK_ANSI_A),
            modifierFlags: [.control, .option, .shift, .command],
            characters: "a"
        ).get()

        #expect(binding.displayString == "⌃⌥⇧⌘A")
    }

    @Test func duplicateCustomShortcutsAreRejected() {
        var shortcuts = TimerShortcutBindings.defaults
        shortcuts.stop = shortcuts.start

        #expect(TimerShortcutValidator.validationError(for: shortcuts) == .duplicate(
            first: .start,
            second: .stop
        ))
    }

    @Test func conflictWithFixedShortcutIsRejected() {
        var shortcuts = TimerShortcutBindings.defaults
        shortcuts.start = HotKeyBinding(
            keyCode: UInt32(kVK_ANSI_M),
            modifiers: UInt32(controlKey | cmdKey),
            keyLabel: "M"
        )

        #expect(TimerShortcutValidator.validationError(for: shortcuts) == .reserved(
            action: .start,
            reservedName: "移至下个显示器"
        ))
    }

    @Test func customShortcutsPersistWithConfiguration() {
        let suiteName = "PPTTimerShortcutTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ConfigurationStore(defaults: defaults)
        var configuration = TimerConfiguration()
        var shortcuts = TimerShortcutBindings.defaults
        shortcuts.pause = HotKeyBinding(
            keyCode: UInt32(kVK_ANSI_P),
            modifiers: UInt32(controlKey | optionKey),
            keyLabel: "P"
        )
        configuration.shortcuts = shortcuts

        store.save(configuration)

        #expect(store.load().effectiveShortcuts == shortcuts)
    }
}
