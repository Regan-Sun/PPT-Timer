import AppKit
import SwiftUI

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var configuration: TimerConfiguration
    var onSave: ((TimerConfiguration) -> Void)?
    var onClose: (() -> Void)?

    init(configuration: TimerConfiguration) {
        self.configuration = configuration
    }

    func save() {
        configuration.normalize()
        onSave?(configuration)
        onClose?()
    }

    func cancel() { onClose?() }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsViewModel

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                Form {
                    Section("计时") {
                        LabeledContent("倒计时（秒）") {
                            TextField("1200", value: $model.configuration.duration, format: .number)
                                .frame(width: 110)
                        }
                        LabeledContent("提前提醒（秒）") {
                            TextField("120", value: $model.configuration.warningTime, format: .number)
                                .frame(width: 110)
                        }
                        Toggle("播放提前提醒音", isOn: $model.configuration.playWarningSound)
                        Toggle("播放结束提示音", isOn: $model.configuration.playFinishSound)
                        Toggle("停止时重置计时", isOn: $model.configuration.stopResetsTimer)
                    }
                }
                .padding(20)
                .tabItem { Label("计时", systemImage: "timer") }

                Form {
                    Section("自动开始") {
                        Toggle("检测全屏放映", isOn: $model.configuration.automaticDetection)
                        Toggle("仅检测 PowerPoint / WPS", isOn: $model.configuration.powerPointOnly)
                            .disabled(!model.configuration.automaticDetection)
                        Toggle("手动开始后暂停自动检测", isOn: $model.configuration.manualModeSuppressesDetection)
                            .disabled(!model.configuration.automaticDetection)
                    }
                }
                .padding(20)
                .tabItem { Label("检测", systemImage: "rectangle.inset.filled") }

                Form {
                    Section("浮层") {
                        Picker("位置", selection: $model.configuration.position) {
                            ForEach(OverlayPosition.allCases) { position in
                                Text(position.displayName).tag(position)
                            }
                        }
                        LabeledContent("宽度") {
                            TextField("200", value: $model.configuration.width, format: .number)
                                .frame(width: 90)
                        }
                        LabeledContent("高度") {
                            TextField("60", value: $model.configuration.height, format: .number)
                                .frame(width: 90)
                        }
                        LabeledContent("屏幕边距") {
                            TextField("8", value: $model.configuration.margin, format: .number)
                                .frame(width: 90)
                        }
                        Toggle("在所有显示器显示", isOn: $model.configuration.showOnAllDisplays)
                    }
                }
                .padding(20)
                .tabItem { Label("显示", systemImage: "display.2") }

                Form {
                    Section("文字") {
                        LabeledContent("字体") {
                            TextField("PingFang SC", text: $model.configuration.fontName)
                                .frame(width: 180)
                        }
                        LabeledContent("字号") {
                            TextField("36", value: $model.configuration.fontSize, format: .number)
                                .frame(width: 90)
                        }
                        Toggle("粗体", isOn: $model.configuration.boldFont)
                    }
                    Section("颜色（HEX）") {
                        colorField("背景", value: $model.configuration.backgroundColor)
                        colorField("普通文字", value: $model.configuration.textColor)
                        colorField("提前提醒", value: $model.configuration.warningColor)
                        colorField("超时", value: $model.configuration.timeoutColor)
                        LabeledContent("不透明度") {
                            Slider(value: $model.configuration.opacity, in: 0.05...1)
                                .frame(width: 180)
                            Text("\(Int(model.configuration.opacity * 100))%")
                                .monospacedDigit()
                                .frame(width: 38, alignment: .trailing)
                        }
                    }
                }
                .padding(20)
                .tabItem { Label("外观", systemImage: "paintpalette") }
            }

            Divider()
            HStack {
                Spacer()
                Button("取消") { model.cancel() }
                    .keyboardShortcut(.cancelAction)
                Button("应用") {
                    model.save()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(14)
        }
        .frame(width: 540, height: 470)
    }

    @ViewBuilder
    private func colorField(_ title: String, value: Binding<String>) -> some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                ColorPicker("", selection: colorBinding(value), supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 28)
                TextField("RRGGBB", text: value)
                    .frame(width: 100)
            }
        }
    }

    private func colorBinding(_ value: Binding<String>) -> Binding<Color> {
        Binding(
            get: { Color(nsColor: NSColor(hex: value.wrappedValue)) },
            set: { value.wrappedValue = NSColor($0).hexRGBString }
        )
    }
}

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let model: SettingsViewModel

    init(configuration: TimerConfiguration, onSave: @escaping (TimerConfiguration) -> Void) {
        model = SettingsViewModel(configuration: configuration)
        model.onSave = onSave
        let hostingController = NSHostingController(rootView: SettingsView(model: model))
        let window = NSWindow(contentViewController: hostingController)
        window.title = "PPT 计时器设置"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
        model.onClose = { [weak window] in window?.close() }
    }

    required init?(coder: NSCoder) { nil }

    func show(configuration: TimerConfiguration) {
        model.configuration = configuration
        showWindow(nil)
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
