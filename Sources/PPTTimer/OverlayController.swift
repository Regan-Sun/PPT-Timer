import AppKit
import Foundation

private final class TimerPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class TimerOverlayView: NSView {
    let timeLabel = NSTextField(labelWithString: "20:00")
    let stateLabel = NSTextField(labelWithString: "")
    var onClick: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        timeLabel.alignment = .center
        timeLabel.maximumNumberOfLines = 1
        timeLabel.lineBreakMode = .byClipping
        timeLabel.translatesAutoresizingMaskIntoConstraints = false

        stateLabel.alignment = .left
        stateLabel.font = .systemFont(ofSize: 11, weight: .bold)
        stateLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(timeLabel)
        addSubview(stateLabel)
        NSLayoutConstraint.activate([
            timeLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            timeLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            timeLabel.topAnchor.constraint(equalTo: topAnchor),
            timeLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
            stateLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            stateLabel.topAnchor.constraint(equalTo: topAnchor, constant: 3)
        ])
    }

    required init?(coder: NSCoder) { nil }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func rightMouseDown(with event: NSEvent) {
        onClick?()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

private struct OverlayWindow {
    let panel: NSPanel
    let view: TimerOverlayView
}

@MainActor
final class OverlayController: NSObject {
    var onOverlayClick: (() -> Void)?
    private var overlays: [OverlayWindow] = []
    private var configuration: TimerConfiguration
    private var lastDisplay: CountdownDisplay

    init(configuration: TimerConfiguration) {
        self.configuration = configuration
        self.lastDisplay = CountdownDisplay(
            remaining: configuration.duration,
            state: .stopped,
            blinkPhase: false
        )
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        rebuildWindows()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func apply(configuration: TimerConfiguration) {
        self.configuration = configuration
        rebuildWindows()
        render(lastDisplay)
    }

    func render(_ display: CountdownDisplay) {
        lastDisplay = display
        let colors = colors(for: display)
        for overlay in overlays {
            overlay.panel.level = windowLevel(for: display.state)
            overlay.view.timeLabel.stringValue = display.formattedTime
            overlay.view.timeLabel.textColor = colors.foreground
            overlay.view.layer?.backgroundColor = colors.background.cgColor
            overlay.view.stateLabel.stringValue = stateIndicator(for: display.state)
            overlay.view.stateLabel.textColor = colors.foreground.withAlphaComponent(0.7)
            overlay.panel.orderFrontRegardless()
        }
    }

    func lowerForControlMenu() {
        overlays.forEach { $0.panel.level = .floating }
    }

    @objc private func screensChanged() {
        rebuildWindows()
        render(lastDisplay)
    }

    private func rebuildWindows() {
        overlays.forEach { $0.panel.orderOut(nil) }
        overlays.removeAll()

        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        let selectedIndex = min(configuration.selectedDisplay, screens.count - 1)

        for (index, screen) in screens.enumerated() {
            guard configuration.showOnAllDisplays || index == selectedIndex else { continue }

            let frame = panelFrame(on: screen)
            let panel = TimerPanel(
                contentRect: frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            let view = TimerOverlayView(frame: NSRect(origin: .zero, size: frame.size))
            view.onClick = { [weak self] in self?.onOverlayClick?() }
            panel.contentView = view
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.ignoresMouseEvents = false
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

            let font = NSFont(name: configuration.fontName, size: configuration.fontSize)
                ?? NSFont.systemFont(ofSize: configuration.fontSize)
            view.timeLabel.font = configuration.boldFont
                ? NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
                : font
            view.layer?.cornerRadius = 6
            view.layer?.masksToBounds = true

            panel.orderFrontRegardless()
            overlays.append(OverlayWindow(panel: panel, view: view))
        }
    }

    private func panelFrame(on screen: NSScreen) -> NSRect {
        let availableFrame = screen.visibleFrame
        let width = min(configuration.width, availableFrame.width)
        let height = min(configuration.height, availableFrame.height)
        let margin = configuration.margin
        let x: CGFloat
        let y: CGFloat

        switch configuration.position {
        case .topLeft, .bottomLeft:
            x = availableFrame.minX + margin
        case .topCenter, .bottomCenter:
            x = availableFrame.midX - width / 2
        case .topRight, .bottomRight:
            x = availableFrame.maxX - width - margin
        }

        switch configuration.position {
        case .topLeft, .topCenter, .topRight:
            y = availableFrame.maxY - height - margin
        case .bottomLeft, .bottomCenter, .bottomRight:
            y = availableFrame.minY + margin
        }
        return NSRect(x: x, y: y, width: width, height: height)
    }

    private func stateIndicator(for state: CountdownRunState) -> String {
        switch state {
        case .stopped: return "■"
        case .running: return ""
        case .paused: return "Ⅱ"
        }
    }

    private func windowLevel(for state: CountdownRunState) -> NSWindow.Level {
        guard state != .stopped else { return .floating }
        return NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) - 1)
    }

    private func colors(for display: CountdownDisplay) -> (foreground: NSColor, background: NSColor) {
        let baseBackground = NSColor(hex: configuration.backgroundColor)
            .withAlphaComponent(configuration.opacity)
        if display.remaining < 0 {
            let timeout = NSColor(hex: configuration.timeoutColor)
            return display.blinkPhase
                ? (timeout, baseBackground)
                : (baseBackground.withAlphaComponent(1), timeout.withAlphaComponent(configuration.opacity))
        }
        if display.remaining <= configuration.warningTime {
            return (NSColor(hex: configuration.warningColor), baseBackground)
        }
        return (NSColor(hex: configuration.textColor), baseBackground)
    }
}
