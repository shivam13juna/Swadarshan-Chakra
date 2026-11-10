import AppKit
import Combine
import MeditationCore

@MainActor
final class SessionModel: NSObject, ObservableObject {
    @Published var cyclesText: String
    /// The minutes and seconds below are per step or for the whole practice, as this says.
    @Published private(set) var timingMode: TimingMode
    @Published var minutesText: String
    @Published var secondsText: String
    @Published private(set) var engine = SessionEngine()
    @Published private(set) var pauseReason = "Your practice is paused."
    /// How meditation opens: in its own full-screen Space (the default) or as an ordinary window.
    /// The green window button and ⌃⌘F still switch at any time without changing this.
    @Published var opensInFullScreen: Bool {
        didSet { defaults.set(opensInFullScreen, forKey: "opensInFullScreen") }
    }
    /// Whether any of the meditation window is on screen. Decorative motion runs only while it is.
    @Published var windowVisible = false

    var hideWindow: () -> Void = {}
    var quitApplication: () -> Void = {}
    private var timer: Timer?
    private let defaults: UserDefaults
    private let automaticTicks: Bool
    private let maximumUnobservedGap: TimeInterval = 2.5

    init(defaults: UserDefaults = .standard, automaticTicks: Bool = true, initialEngine: SessionEngine = SessionEngine()) {
        self.defaults = defaults
        self.automaticTicks = automaticTicks
        let saved = initialEngine.phase == .ready ? SessionPreferences.load(from: defaults) : initialEngine.configuration
        cyclesText = String(saved.cycles)
        timingMode = saved.timing
        minutesText = String(saved.enteredMinutes)
        secondsText = String(format: "%02d", saved.enteredSecondsComponent)
        engine = initialEngine
        opensInFullScreen = defaults.object(forKey: "opensInFullScreen") as? Bool ?? true
        super.init()
    }

    static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }
    var cycles: Int? { SessionConfiguration.integer(cyclesText, in: SessionConfiguration.cycleRange) }
    var configuration: SessionConfiguration? {
        guard let cycles,
              let minutes = SessionConfiguration.integer(minutesText, in: SessionConfiguration.minuteRange(for: timingMode)),
              let seconds = SessionConfiguration.integer(secondsText, in: SessionConfiguration.secondRange) else { return nil }
        return try? SessionConfiguration(cycles: cycles, timing: timingMode, minutes: minutes, seconds: seconds)
    }
    var cyclesValid: Bool { cycles != nil }
    var secondsValid: Bool { SessionConfiguration.integer(secondsText, in: SessionConfiguration.secondRange) != nil }
    var durationValid: Bool { durationProblem == nil }

    /// Why the entered time cannot be used, or nil. An invalid cycle count is reported by its own field.
    var durationProblem: String? {
        let minuteRange = SessionConfiguration.minuteRange(for: timingMode)
        guard let minutes = SessionConfiguration.integer(minutesText, in: minuteRange) else {
            return "Enter whole minutes from 0 to \(minuteRange.upperBound)."
        }
        guard let seconds = SessionConfiguration.integer(secondsText, in: SessionConfiguration.secondRange) else {
            return "Enter whole seconds from 0 to 59."
        }
        let entered = minutes * 60 + seconds
        switch timingMode {
        case .perStep:
            return SessionConfiguration.durationRange.contains(entered) ? nil : "Choose 1 second to 120 minutes per step."
        case .total:
            if entered > SessionConfiguration.maximumTotalSeconds { return "Choose up to 600 minutes in total." }
            guard let cycles else { return entered == 0 ? "Allow at least 1 second for each step." : nil }
            let minimum = cycles * Stage.all.count
            guard entered < minimum else { return nil }
            return "For \(cycles) \(cycles == 1 ? "cycle" : "cycles"), allow at least \(TimeText.duration(Double(minimum))) (1 sec per step)."
        }
    }

    /// Switching only changes how the time is entered: the fields are converted so the practice stays the same.
    func setTimingMode(_ mode: TimingMode) {
        guard mode != timingMode else { return }
        if let converted = configuration?.expressed(as: mode) {
            minutesText = String(converted.enteredMinutes)
            secondsText = String(format: "%02d", converted.enteredSecondsComponent)
        }
        timingMode = mode
    }

    func begin() {
        guard let configuration else { return }
        SessionPreferences.save(configuration, to: defaults)
        engine.begin(configuration, at: Self.now)
        updateTimer()
        announce("Practice started. \(cycleTitle)")
    }

    var cycleTitle: String { "Cycle \(engine.currentCycle) of \(engine.configuration.cycles)" }

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
        if engine.phase == .complete { announce("Meditation complete.") }
        else if engine.isIntroducingCycle { announce(cycleTitle) }
        else { announce(engine.currentStage.label) }
    }

    private func announce(_ text: String) {
        guard let window = NSApp.keyWindow else { return }
        NSAccessibility.post(element: window, notification: .announcementRequested, userInfo: [
            .announcement: text, .priority: NSAccessibilityPriorityLevel.medium.rawValue
        ])
    }
}
