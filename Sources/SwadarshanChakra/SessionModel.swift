import AppKit
import Combine
import MeditationCore

@MainActor
final class SessionModel: NSObject, ObservableObject {
    @Published var cyclesText: String
    /// Per step or for the whole practice, as the minutes and seconds are entered, or freestyle, with no timer.
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
    /// Whether each step shows the countdown bar along its bottom edge. Freestyle has no countdown to show.
    @Published var showsCountdownBar: Bool {
        didSet { defaults.set(showsCountdownBar, forKey: "showsCountdownBar") }
    }
    /// Whether any of the meditation window is on screen. Decorative motion runs only while it is.
    @Published var windowVisible = false

    /// Puts the window away, leaving the app in the menu bar. Closing goes through close() instead.
    var hideWindow: () -> Void = {}
    var quitApplication: () -> Void = {}
    private var timer: Timer?
    private let defaults: UserDefaults
    private let automaticTicks: Bool
    private let maximumUnobservedGap: TimeInterval = 2.5
    /// How the minutes and seconds are entered: per step or in total. Freestyle leaves them as they
    /// are, so choosing a timer again brings the same time back.
    private var fieldTiming: TimingMode

    init(defaults: UserDefaults = .standard, automaticTicks: Bool = true, initialEngine: SessionEngine = SessionEngine()) {
        self.defaults = defaults
        self.automaticTicks = automaticTicks
        let saved = initialEngine.phase == .ready ? SessionPreferences.load(from: defaults) : initialEngine.configuration
        // With freestyle chosen, the time fields still hold the time last entered.
        let time = saved.isTimed ? saved : SessionPreferences.loadTimed(from: defaults)
        cyclesText = String(saved.cycles)
        timingMode = saved.timing
        fieldTiming = time.timing
        minutesText = String(time.enteredMinutes)
        secondsText = String(format: "%02d", time.enteredSecondsComponent)
        engine = initialEngine
        opensInFullScreen = defaults.object(forKey: "opensInFullScreen") as? Bool ?? true
        showsCountdownBar = defaults.object(forKey: "showsCountdownBar") as? Bool ?? true
        super.init()
    }

    static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }
    var cycles: Int? { SessionConfiguration.integer(cyclesText, in: SessionConfiguration.cycleRange) }
    var configuration: SessionConfiguration? {
        guard timingMode == .freestyle else { return enteredTime }
        return cycles.flatMap { try? SessionConfiguration(freestyleCycles: $0) }
    }
    /// The time as the fields hold it, per step or in total, even while freestyle is chosen.
    private var enteredTime: SessionConfiguration? {
        guard let cycles,
              let minutes = SessionConfiguration.integer(minutesText, in: SessionConfiguration.minuteRange(for: fieldTiming)),
              let seconds = SessionConfiguration.integer(secondsText, in: SessionConfiguration.secondRange) else { return nil }
        return try? SessionConfiguration(cycles: cycles, timing: fieldTiming, minutes: minutes, seconds: seconds)
    }
    var cyclesValid: Bool { cycles != nil }
    var secondsValid: Bool { SessionConfiguration.integer(secondsText, in: SessionConfiguration.secondRange) != nil }
    var durationValid: Bool { durationProblem == nil }

    /// Why the entered time cannot be used, or nil. An invalid cycle count is reported by its own field.
    var durationProblem: String? {
        guard timingMode != .freestyle else { return nil }
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
        case .freestyle:
            return nil
        }
    }

    /// Switching only changes how the time is entered: the fields are converted so the practice stays the
    /// same. Freestyle leaves them as they are, so choosing a timer again brings the same time back.
    func setTimingMode(_ mode: TimingMode) {
        guard mode != timingMode else { return }
        if mode != .freestyle {
            if mode != fieldTiming, let converted = enteredTime?.expressed(as: mode) {
                minutesText = String(converted.enteredMinutes)
                secondsText = String(format: "%02d", converted.enteredSecondsComponent)
            }
            fieldTiming = mode
        }
        timingMode = mode
    }

    func begin() {
        guard let configuration else { return }
        // Freestyle saves the time fields too, for when a timer is chosen again.
        if !configuration.isTimed, let enteredTime { SessionPreferences.save(enteredTime, to: defaults) }
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
        if away { engine.pauseAtLastSample(at: Self.now) }
        else { engine.pause(at: Self.now) }
        updateTimer()
    }

    /// Whether the practitioner is with the practice: the window is in front, and the Mac is awake and
    /// unlocked. Leaving pauses a running practice, and a pause counts as practice only while they're here.
    func setPresent(_ present: Bool) {
        let wasActive = engine.phase == .running || engine.phase == .confirming
        engine.setPresent(present, at: Self.now)
        if !present && wasActive { pauseReason = "Paused while you were away." }
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

    /// Every way of closing the window: the × buttons, Close on the completion screen, the red window
    /// button, ⌘W, and Esc on setup or completion. Any practice ends at once, without asking, and the app
    /// stays in the menu bar, which opens the setup screen again.
    func close() {
        engine.reset()
        updateTimer()
        hideWindow()
    }

    /// Esc pauses a running practice and, pressed again, resumes it with the same time left, so a step
    /// can be given longer. It also cancels a confirmation, and on setup or completion it closes.
    func escape() {
        switch engine.phase {
        case .running: pause()
        case .paused: resume()
        case .confirming: cancelConfirmation()
        case .ready, .complete: close()
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
