import AppKit
import Foundation

enum OverlayGeometry {
    static let dragThreshold: CGFloat = 4

    static func isDrag(delta: CGSize) -> Bool {
        hypot(delta.width, delta.height) > dragThreshold
    }

    static func clampedOrigin(
        _ proposed: CGPoint,
        panelSize: CGSize,
        visibleFrame: CGRect
    ) -> CGPoint {
        let maxX = max(visibleFrame.minX, visibleFrame.maxX - panelSize.width)
        let maxY = max(visibleFrame.minY, visibleFrame.maxY - panelSize.height)
        return CGPoint(
            x: min(max(proposed.x, visibleFrame.minX), maxX),
            y: min(max(proposed.y, visibleFrame.minY), maxY)
        )
    }

    static func placement(
        for origin: CGPoint,
        panelSize: CGSize,
        visibleFrame: CGRect
    ) -> OverlayPlacement {
        let clamped = clampedOrigin(origin, panelSize: panelSize, visibleFrame: visibleFrame)
        let horizontalTravel = max(visibleFrame.width - panelSize.width, 0)
        let verticalTravel = max(visibleFrame.height - panelSize.height, 0)
        return OverlayPlacement(
            xFraction: horizontalTravel > 0
                ? Double((clamped.x - visibleFrame.minX) / horizontalTravel)
                : 0,
            yFraction: verticalTravel > 0
                ? Double((clamped.y - visibleFrame.minY) / verticalTravel)
                : 0
        )
    }

    static func origin(
        for placement: OverlayPlacement,
        panelSize: CGSize,
        visibleFrame: CGRect
    ) -> CGPoint {
        var normalized = placement
        normalized.normalize()
        let horizontalTravel = max(visibleFrame.width - panelSize.width, 0)
        let verticalTravel = max(visibleFrame.height - panelSize.height, 0)
        return CGPoint(
            x: visibleFrame.minX + CGFloat(normalized.xFraction) * horizontalTravel,
            y: visibleFrame.minY + CGFloat(normalized.yFraction) * verticalTravel
        )
    }
}

private final class TimerPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class TimerOverlayView: NSView {
    let timeLabel = NSTextField(labelWithString: "20:00")
    let stateLabel = NSTextField(labelWithString: "")
    var onClick: (() -> Void)?
    var onDragEnd: ((CGPoint) -> Void)?
    private var dragStartMouseLocation: CGPoint?
    private var dragStartWindowOrigin: CGPoint?
    private var didDrag = false

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
        dragStartMouseLocation = NSEvent.mouseLocation
        dragStartWindowOrigin = window?.frame.origin
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window,
              let startMouse = dragStartMouseLocation,
              let startOrigin = dragStartWindowOrigin,
              let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame else { return }
        let currentMouse = NSEvent.mouseLocation
        let delta = CGSize(
            width: currentMouse.x - startMouse.x,
            height: currentMouse.y - startMouse.y
        )
        if !didDrag && !OverlayGeometry.isDrag(delta: delta) { return }
        didDrag = true
        let proposed = CGPoint(
            x: startOrigin.x + delta.width,
            y: startOrigin.y + delta.height
        )
        window.setFrameOrigin(OverlayGeometry.clampedOrigin(
            proposed,
            panelSize: window.frame.size,
            visibleFrame: visibleFrame
        ))
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            dragStartMouseLocation = nil
            dragStartWindowOrigin = nil
            didDrag = false
        }
        if didDrag, let origin = window?.frame.origin {
            onDragEnd?(origin)
        } else {
            onClick?()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        onClick?()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }
}

private struct OverlayWindow {
    let panel: NSPanel
    let view: TimerOverlayView
    let screen: NSScreen
}

@MainActor
final class OverlayController: NSObject {
    var onOverlayClick: (() -> Void)?
    var onPositionChange: ((OverlayPlacement) -> Void)?
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
            view.onDragEnd = { [weak self, weak panel] origin in
                guard let self, let panel else { return }
                self.persistDraggedOrigin(origin, panelSize: panel.frame.size, screen: screen)
            }
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
            overlays.append(OverlayWindow(panel: panel, view: view, screen: screen))
        }
    }

    private func panelFrame(on screen: NSScreen) -> NSRect {
        let availableFrame = screen.visibleFrame
        let width = min(configuration.width, availableFrame.width)
        let height = min(configuration.height, availableFrame.height)
        if let placement = configuration.customPosition {
            return NSRect(
                origin: OverlayGeometry.origin(
                    for: placement,
                    panelSize: CGSize(width: width, height: height),
                    visibleFrame: availableFrame
                ),
                size: CGSize(width: width, height: height)
            )
        }
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

    private func persistDraggedOrigin(_ origin: CGPoint, panelSize: CGSize, screen: NSScreen) {
        let placement = OverlayGeometry.placement(
            for: origin,
            panelSize: panelSize,
            visibleFrame: screen.visibleFrame
        )
        configuration.customPosition = placement
        for overlay in overlays {
            overlay.panel.setFrameOrigin(OverlayGeometry.origin(
                for: placement,
                panelSize: overlay.panel.frame.size,
                visibleFrame: overlay.screen.visibleFrame
            ))
        }
        onPositionChange?(placement)
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
