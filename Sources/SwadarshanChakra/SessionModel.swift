import AppKit
import Combine
import MeditationCore

@MainActor
final class SessionModel: NSObject, ObservableObject {
    @Published var cyclesText: String
    @Published var minutesText: String
    @Published var secondsText: String
    @Published private(set) var engine = SessionEngine()
    @Published private(set) var pauseReason = "Your practice is paused."

    var hideWindow: () -> Void = {}
    var quitApplication: () -> Void = {}
    private var timer: Timer?
    private let defaults: UserDefaults
    private let automaticTicks: Bool
    private let maximumUnobservedGap: TimeInterval = 2.5

    init(defaults: UserDefaults = .standard, automaticTicks: Bool = true, initialEngine: SessionEngine = SessionEngine()) {
        self.defaults = defaults
        self.automaticTicks = automaticTicks
        let saved = SessionPreferences.load(from: defaults)
        cyclesText = String(saved.cycles)
        minutesText = String(saved.minutesPerStep)
        secondsText = String(format: "%02d", saved.secondsComponent)
        engine = initialEngine
        if initialEngine.phase != .ready {
            cyclesText = String(initialEngine.configuration.cycles)
            minutesText = String(initialEngine.configuration.minutesPerStep)
            secondsText = String(format: "%02d", initialEngine.configuration.secondsComponent)
        }
        super.init()
    }

    static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }
    var configuration: SessionConfiguration? {
        guard let cycles = SessionConfiguration.integer(cyclesText, in: SessionConfiguration.cycleRange),
              let duration = stepDuration else { return nil }
        return try? SessionConfiguration(cycles: cycles, minutesPerStep: duration.minutesPerStep,
                                         secondsPerStep: duration.secondsComponent)
    }
    var cyclesValid: Bool { SessionConfiguration.integer(cyclesText, in: SessionConfiguration.cycleRange) != nil }
    var minutesValid: Bool { SessionConfiguration.integer(minutesText, in: SessionConfiguration.minuteRange) != nil }
    var secondsValid: Bool { SessionConfiguration.integer(secondsText, in: SessionConfiguration.secondRange) != nil }
    var durationValid: Bool { stepDuration != nil }

    private var stepDuration: SessionConfiguration? {
        guard let minutes = SessionConfiguration.integer(minutesText, in: SessionConfiguration.minuteRange),
              let seconds = SessionConfiguration.integer(secondsText, in: SessionConfiguration.secondRange) else { return nil }
        return try? SessionConfiguration(cycles: 1, minutesPerStep: minutes, secondsPerStep: seconds)
    }

    func begin() {
        guard let configuration else { return }
        SessionPreferences.save(configuration, to: defaults)
        engine.begin(configuration, at: Self.now)
        updateTimer()
        announce("Practice started. \(engine.currentStage.label)")
    }

    func nextStage(eventTime: TimeInterval? = nil, isRepeat: Bool = false) {
        let transitioned = engine.nextStage(at: Self.now, eventTime: eventTime, isRepeat: isRepeat,
                                            maximumGap: maximumUnobservedGap)
        updateTimer()
        if transitioned { announceStage() }
    }

    func pause(reason: String = "Your practice is paused.", away: Bool = false) {
        pauseReason = reason
        if away { engine.pauseAtLastSample() }
        else { engine.pause(at: Self.now) }
        updateTimer()
    }

    func resume() {
        engine.resume(at: Self.now)
        updateTimer()
    }

    func request(_ confirmation: SessionEngine.Confirmation) {
        engine.requestConfirmation(confirmation, at: Self.now)
        updateTimer()
    }

    func cancelConfirmation() {
        engine.cancelConfirmation(at: Self.now)
        updateTimer()
    }

    func confirm() {
        let action = engine.confirm(at: Self.now)
        updateTimer()
        if action == .quit { quitApplication() }
    }

    func practiceAgain() {
        engine.reset()
        updateTimer()
    }

    func escape() {
        switch engine.phase {
        case .running: pause()
        case .confirming: cancelConfirmation()
        case .ready, .complete: hideWindow()
        case .paused: break
        }
    }

    @objc private func pulse() {
        let changed = engine.tick(at: Self.now, maximumGap: maximumUnobservedGap)
        if engine.phase == .paused { pauseReason = "Paused while you were away." }
        updateTimer()
        if changed { announceStage() }
    }

    private func updateTimer() {
        if engine.phase == .running && automaticTicks {
            if timer == nil {
                let timer = Timer(timeInterval: 0.2, target: self, selector: #selector(pulse), userInfo: nil, repeats: true)
                timer.tolerance = 0.035
                RunLoop.main.add(timer, forMode: .common)
                self.timer = timer
            }
        } else {
            timer?.invalidate()
            timer = nil
        }
    }

    private func announceStage() {
        announce(engine.phase == .complete ? "Meditation complete." : engine.currentStage.label)
    }

    private func announce(_ text: String) {
        guard let window = NSApp.keyWindow else { return }
        NSAccessibility.post(element: window, notification: .announcementRequested, userInfo: [
            .announcement: text, .priority: NSAccessibilityPriorityLevel.medium.rawValue
        ])
    }
}
