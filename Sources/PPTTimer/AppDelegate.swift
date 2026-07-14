import AppKit
import Foundation

private enum TimerOrigin {
    case manual
    case automatic
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = ConfigurationStore()
    private let detector = FullscreenDetector()
    private let soundPlayer = SoundPlayer()

    private(set) var configuration: TimerConfiguration
    private var countdown: CountdownController
    private var overlay: OverlayController
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var settingsController: SettingsWindowController?
    private var hotKeyManager: HotKeyManager?
    private var detectionTimer: Timer?
    private var timerOrigin: TimerOrigin?
    private var suppressAutomaticStartUntilFullscreenEnds = false
    private var detectedWindow: DetectedFullscreenWindow?
    private var lastDisplay: CountdownDisplay

    private weak var startItem: NSMenuItem?
    private weak var stopItem: NSMenuItem?
    private weak var pauseItem: NSMenuItem?
    private weak var detectionItem: NSMenuItem?
    private weak var powerPointOnlyItem: NSMenuItem?
    private weak var allDisplaysItem: NSMenuItem?
    private weak var detectedApplicationItem: NSMenuItem?

    override init() {
        let initial = store.load()
        configuration = initial
        countdown = CountdownController(duration: initial.duration)
        overlay = OverlayController(configuration: initial)
        lastDisplay = CountdownDisplay(remaining: initial.duration, state: .stopped, blinkPhase: false)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        configureCallbacks()
        configureHotKeys()
        installDetectionTimer()
        overlay.render(lastDisplay)
    }

    func applicationWillTerminate(_ notification: Notification) {
        detectionTimer?.invalidate()
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateMenuState()
    }

    private func configureCallbacks() {
        overlay.onOverlayClick = { [weak self] in
            self?.overlay.lowerForControlMenu()
            self?.statusItem?.button?.performClick(nil)
        }
        countdown.onDisplayChange = { [weak self] display in
            guard let self else { return }
            self.lastDisplay = display
            self.overlay.render(display)
            self.updateStatusItem(display)
            self.updateMenuState()
        }
        countdown.onWarning = { [weak self] in
            guard let self, self.configuration.playWarningSound else { return }
            self.soundPlayer.play(resource: "beep")
        }
        countdown.onFinish = { [weak self] in
            guard let self, self.configuration.playFinishSound else { return }
            self.soundPlayer.play(resource: "applause")
        }
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "timer", accessibilityDescription: "PPT 计时器")
        item.button?.imagePosition = .imageLeading
        item.button?.title = " " + lastDisplay.formattedTime

        let menu = NSMenu(title: "PPT 计时器")
        menu.delegate = self

        let detectedItem = NSMenuItem(title: "等待全屏放映", action: nil, keyEquivalent: "")
        detectedItem.isEnabled = false
        menu.addItem(detectedItem)
        menu.addItem(.separator())
        detectedApplicationItem = detectedItem

        let start = menuItem("开始计时", shortcut: "F12", action: #selector(startManually))
        let stop = menuItem("停止计时", shortcut: "⌃F12", action: #selector(stopManually))
        let pause = menuItem("暂停/恢复", shortcut: "⌃F11", action: #selector(togglePause))
        let reset = menuItem("重置", shortcut: "⌃⌥F12", action: #selector(resetTimer))
        [start, stop, pause, reset].forEach(menu.addItem)
        startItem = start
        stopItem = stop
        pauseItem = pause
        menu.addItem(.separator())

        let presetMenu = NSMenu(title: "计时预设")
        for preset in TimerPreset.defaults {
            let item = NSMenuItem(
                title: "\(preset.name)\t⌃⌘F\(preset.id)",
                action: #selector(loadPreset(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = preset.id
            presetMenu.addItem(item)
        }
        let presetRoot = NSMenuItem(title: "计时预设", action: nil, keyEquivalent: "")
        presetRoot.submenu = presetMenu
        menu.addItem(presetRoot)

        let displayMenu = NSMenu(title: "显示器")
        let allDisplays = menuItem("在所有显示器显示", shortcut: "⌃⌘A", action: #selector(toggleAllDisplays))
        displayMenu.addItem(allDisplays)
        displayMenu.addItem(menuItem("移至下个显示器", shortcut: "⌃⌘M", action: #selector(moveToNextDisplay)))
        let displayRoot = NSMenuItem(title: "显示器", action: nil, keyEquivalent: "")
        displayRoot.submenu = displayMenu
        menu.addItem(displayRoot)
        allDisplaysItem = allDisplays

        let detection = menuItem("自动检测全屏放映", shortcut: "", action: #selector(toggleDetection))
        let powerPoint = menuItem("仅检测 PowerPoint / WPS", shortcut: "", action: #selector(togglePowerPointOnly))
        menu.addItem(detection)
        menu.addItem(powerPoint)
        detectionItem = detection
        powerPointOnlyItem = powerPoint
        menu.addItem(.separator())

        menu.addItem(menuItem("设置…", shortcut: "", action: #selector(showSettings)))
        menu.addItem(menuItem("关于 PPT 计时器", shortcut: "", action: #selector(showAbout)))
        menu.addItem(.separator())
        menu.addItem(menuItem("退出", shortcut: "⌘Esc", action: #selector(quit)))

        item.menu = menu
        statusItem = item
        statusMenu = menu
        updateMenuState()
    }

    private func menuItem(_ title: String, shortcut: String, action: Selector) -> NSMenuItem {
        let fullTitle = shortcut.isEmpty ? title : "\(title)\t\(shortcut)"
        let item = NSMenuItem(title: fullTitle, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func configureHotKeys() {
        hotKeyManager = HotKeyManager { [weak self] action in
            Task { @MainActor in self?.handleHotKey(action) }
        }
    }

    private func handleHotKey(_ action: HotKeyAction) {
        switch action {
        case .start: startManually()
        case .stop: stopManually()
        case .pause: togglePause()
        case .reset: resetTimer()
        case .nextDisplay: moveToNextDisplay()
        case .toggleAllDisplays: toggleAllDisplays()
        case .quit: quit()
        case .preset1, .preset2, .preset3, .preset4, .preset5, .preset6:
            let presetID = Int(action.rawValue - HotKeyAction.preset1.rawValue + 1)
            applyPreset(id: presetID)
        }
    }

    private func installDetectionTimer() {
        detectionTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkFullscreen() }
        }
        if let detectionTimer {
            RunLoop.main.add(detectionTimer, forMode: .common)
        }
    }

    private func checkFullscreen() {
        guard configuration.automaticDetection else {
            detectedWindow = nil
            return
        }
        if timerOrigin == .manual, configuration.manualModeSuppressesDetection,
           countdown.state != .stopped {
            return
        }

        let detected = detector.detect(powerPointOnly: configuration.powerPointOnly)
        detectedWindow = detected

        if detected == nil {
            suppressAutomaticStartUntilFullscreenEnds = false
            if timerOrigin == .automatic, countdown.state != .stopped {
                countdown.stop(reset: configuration.stopResetsTimer)
                timerOrigin = nil
            }
        } else if countdown.state == .stopped && !suppressAutomaticStartUntilFullscreenEnds {
            timerOrigin = .automatic
            countdown.start(duration: configuration.duration, warningTime: configuration.warningTime)
        }
    }

    @objc private func startManually() {
        timerOrigin = .manual
        countdown.start(duration: configuration.duration, warningTime: configuration.warningTime)
    }

    @objc private func stopManually() {
        suppressAutomaticStartUntilFullscreenEnds = configuration.automaticDetection
        timerOrigin = nil
        countdown.stop(reset: configuration.stopResetsTimer)
    }

    @objc private func togglePause() {
        countdown.togglePause()
    }

    @objc private func resetTimer() {
        suppressAutomaticStartUntilFullscreenEnds = configuration.automaticDetection
        timerOrigin = nil
        countdown.reset(duration: configuration.duration)
    }

    @objc private func loadPreset(_ sender: NSMenuItem) {
        applyPreset(id: sender.tag)
    }

    private func applyPreset(id: Int) {
        guard let preset = TimerPreset.defaults.first(where: { $0.id == id }) else { return }
        configuration.duration = preset.duration
        configuration.warningTime = preset.warningTime
        applyConfiguration(configuration)
        countdown.reset(duration: configuration.duration)
    }

    @objc private func toggleDetection() {
        configuration.automaticDetection.toggle()
        if !configuration.automaticDetection {
            detectedWindow = nil
        }
        applyConfiguration(configuration)
    }

    @objc private func togglePowerPointOnly() {
        configuration.powerPointOnly.toggle()
        detectedWindow = nil
        applyConfiguration(configuration)
    }

    @objc private func toggleAllDisplays() {
        configuration.showOnAllDisplays.toggle()
        applyConfiguration(configuration)
    }

    @objc private func moveToNextDisplay() {
        guard !configuration.showOnAllDisplays, !NSScreen.screens.isEmpty else { return }
        configuration.selectedDisplay = (configuration.selectedDisplay + 1) % NSScreen.screens.count
        applyConfiguration(configuration)
    }

    @objc private func showSettings() {
        if settingsController == nil {
            settingsController = SettingsWindowController(configuration: configuration) { [weak self] newConfiguration in
                self?.applyConfiguration(newConfiguration)
            }
        }
        settingsController?.show(configuration: configuration)
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "PPT 计时器 for macOS"
        alert.informativeText = "原生菜单栏倒计时工具。可自动检测 PowerPoint 或其他全屏放映，并在所有桌面空间显示计时浮层。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "好")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func applyConfiguration(_ newConfiguration: TimerConfiguration) {
        var normalized = newConfiguration
        normalized.normalize()
        let durationChanged = normalized.duration != configuration.duration
        configuration = normalized
        store.save(normalized)
        overlay.apply(configuration: normalized)
        if durationChanged {
            countdown.updateDurationWhileStopped(normalized.duration)
        }
        updateMenuState()
    }

    private func updateStatusItem(_ display: CountdownDisplay) {
        statusItem?.button?.title = " " + display.formattedTime
        statusItem?.button?.toolTip = "PPT 计时器：\(display.formattedTime)"
        UserDefaults.standard.set(display.remaining, forKey: "PPTTimer.diagnostics.remaining")
        UserDefaults.standard.set(
            display.state == .running ? "running" : display.state == .paused ? "paused" : "stopped",
            forKey: "PPTTimer.diagnostics.state"
        )
        if display.state == .running {
            UserDefaults.standard.set(
                Date().timeIntervalSince1970,
                forKey: "PPTTimer.diagnostics.lastRunningAt"
            )
            UserDefaults.standard.set(
                display.remaining,
                forKey: "PPTTimer.diagnostics.lastRunningRemaining"
            )
        }
        UserDefaults.standard.synchronize()
    }

    private func updateMenuState() {
        startItem?.isEnabled = countdown.state != .running
        stopItem?.isEnabled = countdown.state != .stopped
        pauseItem?.isEnabled = countdown.state != .stopped
        pauseItem?.title = countdown.state == .paused ? "继续计时\t⌃F11" : "暂停计时\t⌃F11"
        detectionItem?.state = configuration.automaticDetection ? .on : .off
        powerPointOnlyItem?.state = configuration.powerPointOnly ? .on : .off
        powerPointOnlyItem?.isEnabled = configuration.automaticDetection
        allDisplaysItem?.state = configuration.showOnAllDisplays ? .on : .off
        detectedApplicationItem?.title = detectedWindow.map { "已检测：\($0.applicationName)" }
            ?? (configuration.automaticDetection ? "等待全屏放映" : "自动检测已关闭")
    }
}
