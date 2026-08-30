import AppKit
import Carbon
import SwiftUI

final class HotKeyRecorderButton: NSButton {
    var binding = TimerShortcutBindings.defaults.start {
        didSet { refreshTitle() }
    }
    var onCapture: ((HotKeyBinding) -> Void)?
    var onError: ((String) -> Void)?
    private var isRecording = false

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        alignment = .center
        focusRingType = .default
        target = self
        action = #selector(beginRecording)
        setAccessibilityLabel("录入快捷键")
        refreshTitle()
    }

    required init?(coder: NSCoder) { nil }

    @objc private func beginRecording() {
        isRecording = true
        title = "请按快捷键…"
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording, !event.isARepeat else {
            super.keyDown(with: event)
            return
        }
        if event.keyCode == UInt16(kVK_Escape) {
            stopRecording()
            return
        }
        switch HotKeyBinding.capture(
            keyCode: event.keyCode,
            modifierFlags: event.modifierFlags,
            characters: event.charactersIgnoringModifiers
        ) {
        case .success(let captured):
            binding = captured
            onCapture?(captured)
            stopRecording()
        case .failure(let error):
            NSSound.beep()
            onError?(error.message)
            title = "请按快捷键…"
        }
    }

    override func resignFirstResponder() -> Bool {
        stopRecording()
        return super.resignFirstResponder()
    }

    private func stopRecording() {
        isRecording = false
        refreshTitle()
    }

    private func refreshTitle() {
        if !isRecording { title = binding.displayString }
    }
}

struct HotKeyRecorder: NSViewRepresentable {
    @Binding var binding: HotKeyBinding
    var onError: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> HotKeyRecorderButton {
        let button = HotKeyRecorderButton(frame: .zero)
        button.binding = binding
        button.onCapture = { [weak coordinator = context.coordinator] captured in
            coordinator?.parent.binding = captured
        }
        button.onError = { [weak coordinator = context.coordinator] message in
            coordinator?.parent.onError(message)
        }
        return button
    }

    func updateNSView(_ nsView: HotKeyRecorderButton, context: Context) {
        context.coordinator.parent = self
        nsView.binding = binding
    }

    final class Coordinator {
        var parent: HotKeyRecorder

        init(parent: HotKeyRecorder) {
            self.parent = parent
        }
    }
}
