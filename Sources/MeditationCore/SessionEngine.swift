import Foundation

/// A deterministic state machine. All timestamps are seconds from the same monotonic clock.
/// The AppKit adapter serializes keyboard, lifecycle, and timer events on the main actor.
public struct SessionEngine: Sendable {
    public enum Phase: Equatable, Sendable { case ready, running, paused, confirming, complete }
    public enum Confirmation: Equatable, Sendable { case restart, end, quit }

    public private(set) var phase: Phase = .ready
    public private(set) var configuration: SessionConfiguration = .standard
    public private(set) var stageIndex = 0
    public private(set) var completedCycles = 0
    public private(set) var remainingSeconds: TimeInterval = 60
    public private(set) var activeSeconds: TimeInterval = 0
    public private(set) var pendingConfirmation: Confirmation?
    public private(set) var transitionCount = 0

    private var lastSample: TimeInterval = 0
    private var stageStartedAt: TimeInterval = 0
    private var lastAutomaticTransition: TimeInterval?
    private var resumeOnCancel = false

    /// Coalesce a physical key press and a timer expiration delivered at the same boundary.
    public static let boundaryTolerance: TimeInterval = 0.15

    public init() {}
    public var currentStage: Stage { Stage.all[stageIndex] }
    public var progress: Double {
        min(1, max(0, 1 - remainingSeconds / configuration.secondsPerStage))
    }

    public mutating func begin(_ configuration: SessionConfiguration, at now: TimeInterval) {
        self = SessionEngine()
        self.configuration = configuration
        remainingSeconds = configuration.secondsPerStage
        lastSample = now
        stageStartedAt = now
        phase = .running
    }

    /// One callback can leave at most one stage; a new stage always starts with its full time.
    /// A long unobserved gap is treated as absence, not permission to race through the artwork.
    @discardableResult
    public mutating func tick(at now: TimeInterval, maximumGap: TimeInterval? = nil) -> Bool {
        guard phase == .running else { return false }
        if let maximumGap, now - lastSample > maximumGap {
            pauseAtLastSample()
            return false
        }
        accrue(until: now)
        if remainingSeconds <= 0 {
            advance(at: now, automatic: true)
            return true
        }
        return false
    }

    @discardableResult
    public mutating func nextStage(
        at now: TimeInterval,
        eventTime: TimeInterval? = nil,
        isRepeat: Bool = false,
        maximumGap: TimeInterval? = nil
    ) -> Bool {
        guard phase == .running, !isRepeat else { return false }
        let eventTime = eventTime ?? now
        // A queued key event belonging to a previous stage/session must not affect the new one.
        guard eventTime >= stageStartedAt else { return false }
        if let boundary = lastAutomaticTransition,
           eventTime <= boundary + Self.boundaryTolerance { return false }
        // If expiration and this key press coincide, expiration consumes this single transition.
        if tick(at: now, maximumGap: maximumGap) { return true }
        guard phase == .running else { return false }
        advance(at: now, automatic: false)
        return true
    }

    public mutating func pause(at now: TimeInterval) {
        if phase == .confirming {
            resumeOnCancel = false
            return
        }
        guard phase == .running else { return }
        // Pausing never traverses a stage, even if its deadline has just passed.
        accrue(until: now)
        phase = .paused
    }

    public mutating func pauseAtLastSample() {
        if phase == .confirming { resumeOnCancel = false }
        if phase == .running { phase = .paused }
    }

    public mutating func resume(at now: TimeInterval) {
        guard phase == .paused else { return }
        lastSample = now
        // Reject events queued while the window was hidden or the session was paused.
        stageStartedAt = now
        lastAutomaticTransition = nil
        phase = .running
    }

    public mutating func requestConfirmation(_ action: Confirmation, at now: TimeInterval) {
        guard phase == .running || phase == .paused else { return }
        let wasRunning = phase == .running
        pause(at: now)
        resumeOnCancel = wasRunning
        pendingConfirmation = action
        phase = .confirming
    }

    public mutating func cancelConfirmation(at now: TimeInterval) {
        guard phase == .confirming else { return }
        let shouldResume = resumeOnCancel
        pendingConfirmation = nil
        resumeOnCancel = false
        phase = .paused
        if shouldResume { resume(at: now) }
    }

    @discardableResult
    public mutating func confirm(at now: TimeInterval) -> Confirmation? {
        guard phase == .confirming, let action = pendingConfirmation else { return nil }
        if action == .restart {
            begin(configuration, at: now)
        } else {
            reset()
        }
        return action
    }

    public mutating func reset() { self = SessionEngine() }

    private mutating func accrue(until now: TimeInterval) {
        let delta = max(0, now - lastSample)
        let practiced = min(remainingSeconds, delta)
        activeSeconds += practiced
        remainingSeconds = max(0, remainingSeconds - practiced)
        lastSample = max(lastSample, now)
    }

    private mutating func advance(at now: TimeInterval, automatic: Bool) {
        transitionCount += 1
        if stageIndex == Stage.all.count - 1 {
            completedCycles += 1
            if completedCycles == configuration.cycles {
                remainingSeconds = 0
                phase = .complete
                return
            }
            stageIndex = 0
        } else {
            stageIndex += 1
        }
        remainingSeconds = configuration.secondsPerStage
        lastSample = now
        stageStartedAt = now
        lastAutomaticTransition = automatic ? now : nil
    }
}
