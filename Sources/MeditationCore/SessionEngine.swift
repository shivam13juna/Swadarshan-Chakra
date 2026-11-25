import Foundation

/// A deterministic state machine. All timestamps are seconds from the same monotonic clock.
/// The AppKit adapter serializes keyboard, lifecycle, and timer events on the main actor.
public struct SessionEngine: Sendable {
    public enum Phase: Equatable, Sendable { case ready, running, paused, confirming, complete }
    public enum Confirmation: Equatable, Sendable { case restart, end, quit }

    /// Every step opens with the cycle of ages, its hand on that step's place, turning there from the
    /// last step's; a cycle's first step has a "Cycle N" card before that. Cards are not practice time:
    /// a step's countdown starts only when its cards end, so no step is ever shortened by one.
    public static let standardIntroduction: TimeInterval = 3

    /// How long each card lasts; 0 goes straight from step to step, without cards.
    public let introductionDuration: TimeInterval
    public private(set) var phase: Phase = .ready
    public private(set) var configuration: SessionConfiguration = .standard
    public private(set) var stageIndex = 0
    public private(set) var completedCycles = 0
    public private(set) var remainingSeconds: TimeInterval = 60
    public private(set) var introductionRemaining: TimeInterval = 0
    /// The time practiced: every running step, plus pauses spent with a timed practice (`isPresent`).
    /// Freestyle pauses, cards, confirmations, and time away never count.
    public private(set) var activeSeconds: TimeInterval = 0
    /// The same time, step by step: `stepSeconds[cycle][step]`, for every cycle begun so far.
    public private(set) var stepSeconds: [[TimeInterval]] = []
    public private(set) var pendingConfirmation: Confirmation?
    public private(set) var transitionCount = 0
    /// Whether the practitioner is with the practice: its window is in front, and the Mac is awake and
    /// unlocked. It outlasts any one practice; see setPresent(_:at:).
    public private(set) var isPresent = true

    private var lastSample: TimeInterval = 0
    private var stageStartedAt: TimeInterval = 0
    private var lastAutomaticTransition: TimeInterval?
    private var resumeOnCancel = false
    /// While paused with the practitioner present, the moment from which the pause is not yet counted.
    private var pausedSince: TimeInterval?

    /// Coalesce a physical key press and a timer expiration delivered at the same boundary.
    public static let boundaryTolerance: TimeInterval = 0.15

    public init(introductionDuration: TimeInterval = SessionEngine.standardIntroduction) {
        self.introductionDuration = max(0, introductionDuration)
    }
    public var currentStage: Stage { Stage.all[stageIndex] }
    public var currentCycle: Int { min(completedCycles + 1, configuration.cycles) }
    /// A card is showing, before the step at `stageIndex`.
    public var isIntroducing: Bool { phase == .running && introductionRemaining > 0 }
    /// The "Cycle N" card, the first of the two before a cycle's first step.
    public var isIntroducingCycle: Bool {
        isIntroducing && stageIndex == 0 && introductionRemaining > introductionDuration
    }
    /// The card just before the step at `stageIndex`: the cycle of ages, its hand on that step's place.
    public var isIntroducingStage: Bool { isIntroducing && !isIntroducingCycle }
    /// The share of this step's time already practiced, from 0 to 1. A freestyle step has no time to share.
    public var progress: Double {
        guard configuration.isTimed else { return 0 }
        return min(1, max(0, 1 - remainingSeconds / configuration.secondsPerStage))
    }

    public mutating func begin(_ configuration: SessionConfiguration, at now: TimeInterval) {
        reset()
        self.configuration = configuration
        remainingSeconds = configuration.secondsPerStage
        introductionRemaining = cardTime(before: 0)
        stepSeconds = [Self.noTime]
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
            pauseAtLastSample(at: now)
            return false
        }
        if introductionRemaining > 0 {
            introductionRemaining = max(0, introductionRemaining - max(0, now - lastSample))
            lastSample = max(lastSample, now)
            guard introductionRemaining == 0 else { return false }
            // The cards have ended; their step starts now with its full time.
            restartClock(at: now, automatic: true)
            return true
        }
        accrue(until: now)
        // A freestyle step never ends by itself.
        if configuration.isTimed && remainingSeconds <= 0 {
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
        if introductionRemaining > 0 {
            // Space on a card begins its step immediately, with its full time, skipping any card still to come.
            introductionRemaining = 0
            restartClock(at: now, automatic: false)
            return true
        }
        advance(at: now, automatic: false)
        return true
    }

    public mutating func pause(at now: TimeInterval) {
        if phase == .confirming {
            resumeOnCancel = false
            return
        }
        guard phase == .running else { return }
        if introductionRemaining > 0 {
            // Pausing on a card begins its step, which waits with its full time.
            introductionRemaining = 0
        } else {
            // Pausing never traverses a stage, even if its deadline has just passed.
            accrue(until: now)
        }
        phase = .paused
        // In timed mode, time paused with a step is practice too, while the practitioner is here.
        pausedSince = isPresent ? now : nil
    }

    /// Pauses as of the last sample, for an absence noticed only now: the time since that sample never
    /// counts. In timed mode, paused time counts from now while the practitioner is here.
    public mutating func pauseAtLastSample(at now: TimeInterval) {
        if phase == .confirming { resumeOnCancel = false }
        if phase == .running {
            introductionRemaining = 0
            phase = .paused
            pausedSince = isPresent ? now : nil
        }
    }

    /// The practitioner has left the practice or come back to it: its window left the front or came
    /// back, or the Mac slept or woke, locked or unlocked. Leaving pauses a running practice as of its
    /// last sample. In timed mode, a pause counts as practice only while they are here.
    public mutating func setPresent(_ present: Bool, at now: TimeInterval) {
        guard present != isPresent else { return }
        if present {
            isPresent = true
            if phase == .paused { pausedSince = now }
        } else {
            countPause(until: now)
            pausedSince = nil
            isPresent = false
            pauseAtLastSample(at: now)
        }
    }

    public mutating func resume(at now: TimeInterval) {
        guard phase == .paused else { return }
        countPause(until: now)
        pausedSince = nil
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
        // The question is not practice: the pause stops counting while it is asked.
        countPause(until: now)
        pausedSince = nil
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
        pausedSince = isPresent ? now : nil
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

    public mutating func reset() {
        let present = isPresent
        self = SessionEngine(introductionDuration: introductionDuration)
        isPresent = present
    }

    private mutating func accrue(until now: TimeInterval) {
        let delta = max(0, now - lastSample)
        // A timed step counts only up to its end; a freestyle step lasts as long as it is given.
        let practiced = configuration.isTimed ? min(remainingSeconds, delta) : delta
        record(practiced)
        remainingSeconds = max(0, remainingSeconds - practiced)
        lastSample = max(lastSample, now)
    }

    private mutating func countPause(until now: TimeInterval) {
        // Freestyle already lets a step last indefinitely; pausing it stops all practice time.
        guard configuration.isTimed, let since = pausedSince else { return }
        record(max(0, now - since))
        pausedSince = max(since, now)
    }

    /// Practice belongs to the step on view: this cycle's row, this step's place in it.
    private mutating func record(_ seconds: TimeInterval) {
        activeSeconds += seconds
        guard stepSeconds.indices.contains(completedCycles) else { return }
        stepSeconds[completedCycles][stageIndex] += seconds
    }

    private static let noTime = [TimeInterval](repeating: 0, count: Stage.all.count)

    /// A cycle's first step opens with two cards, "Cycle N" and then the cycle of ages; every later
    /// step with the cycle of ages alone.
    private func cardTime(before stage: Int) -> TimeInterval {
        stage == 0 ? 2 * introductionDuration : introductionDuration
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
            stepSeconds.append(Self.noTime)
        } else {
            stageIndex += 1
        }
        // The next step opens with its cards; its countdown starts when they end.
        introductionRemaining = cardTime(before: stageIndex)
        remainingSeconds = configuration.secondsPerStage
        restartClock(at: now, automatic: automatic)
    }

    private mutating func restartClock(at now: TimeInterval, automatic: Bool) {
        lastSample = now
        stageStartedAt = now
        lastAutomaticTransition = automatic ? now : nil
    }
}
