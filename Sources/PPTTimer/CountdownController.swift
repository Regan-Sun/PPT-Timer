import Foundation

enum CountdownRunState: Equatable {
    case stopped
    case running
    case paused
}

struct CountdownDisplay: Equatable {
    let remaining: Int
    let state: CountdownRunState
    let blinkPhase: Bool

    var formattedTime: String {
        CountdownMath.format(seconds: remaining)
    }
}

enum CountdownMath {
    static func remaining(duration: Int, elapsed: TimeInterval) -> Int {
        duration - Int(floor(max(0, elapsed)))
    }

    static func format(seconds: Int) -> String {
        let prefix = seconds < 0 ? "+" : ""
        let absolute = abs(seconds)
        let hours = absolute / 3_600
        let minutes = (absolute % 3_600) / 60
        let secs = absolute % 60
        if hours > 0 {
            return String(format: "%@%d:%02d:%02d", prefix, hours, minutes, secs)
        }
        return String(format: "%@%02d:%02d", prefix, minutes, secs)
    }
}

@MainActor
final class CountdownController {
    var onDisplayChange: ((CountdownDisplay) -> Void)?
    var onWarning: (() -> Void)?
    var onFinish: (() -> Void)?

    private(set) var state: CountdownRunState = .stopped
    private(set) var remaining: Int
    private var duration: Int
    private var warningTime: Int
    private var startedAt: Date?
    private var pausedAt: Date?
    private var timer: Timer?
    private var warningTriggered = false
    private var finishTriggered = false
    private var blinkPhase = false

    init(duration: Int) {
        self.duration = duration
        self.warningTime = 0
        self.remaining = duration
    }

    func start(duration: Int, warningTime: Int) {
        invalidateTimer()
        self.duration = duration
        self.warningTime = warningTime
        remaining = duration
        state = .running
        startedAt = Date()
        pausedAt = nil
        warningTriggered = false
        finishTriggered = false
        blinkPhase = false
        publish()
        installTimer()
    }

    func stop(reset: Bool) {
        invalidateTimer()
        state = .stopped
        startedAt = nil
        pausedAt = nil
        if reset {
            remaining = duration
            warningTriggered = false
            finishTriggered = false
            blinkPhase = false
        }
        publish()
    }

    func reset(duration: Int) {
        invalidateTimer()
        self.duration = duration
        remaining = duration
        state = .stopped
        startedAt = nil
        pausedAt = nil
        warningTriggered = false
        finishTriggered = false
        blinkPhase = false
        publish()
    }

    func togglePause() {
        switch state {
        case .running:
            pausedAt = Date()
            state = .paused
            invalidateTimer()
            publish()
        case .paused:
            guard let pausedAt, let startedAt else { return }
            self.startedAt = startedAt.addingTimeInterval(Date().timeIntervalSince(pausedAt))
            self.pausedAt = nil
            state = .running
            publish()
            installTimer()
        case .stopped:
            return
        }
    }

    func updateDurationWhileStopped(_ duration: Int) {
        guard state == .stopped else { return }
        self.duration = duration
        remaining = duration
        publish()
    }

    private func installTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func invalidateTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard state == .running, let startedAt else { return }
        let previous = remaining
        remaining = CountdownMath.remaining(duration: duration, elapsed: Date().timeIntervalSince(startedAt))
        if remaining < 0 { blinkPhase.toggle() }

        if !warningTriggered, previous >= warningTime, remaining <= warningTime {
            warningTriggered = true
            onWarning?()
        }
        if !finishTriggered, previous > 0, remaining <= 0 {
            finishTriggered = true
            onFinish?()
        }
        if previous != remaining || remaining < 0 {
            publish()
        }
    }

    private func publish() {
        onDisplayChange?(CountdownDisplay(remaining: remaining, state: state, blinkPhase: blinkPhase))
    }
}
