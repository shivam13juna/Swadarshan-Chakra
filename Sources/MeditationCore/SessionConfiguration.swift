import Foundation

/// How the practitioner enters time: for one step, or for the whole practice.
public enum TimingMode: String, CaseIterable, Sendable {
    /// Every step receives the entered duration in full.
    case perStep
    /// The entered duration is shared equally by every step of every cycle.
    case total
}

public struct SessionConfiguration: Equatable, Sendable {
    public static let cycleRange = 1...108
    public static let secondRange = 0...59
    /// Seconds for one step, as entered in per-step mode.
    public static let durationRange = 1...7200
    /// Ten hours. With one cycle this is exactly the two-hour per-step maximum for each step.
    public static let maximumTotalSeconds = 36000
    public static let standard = try! SessionConfiguration(cycles: 1, minutesPerStep: 1)

    public let cycles: Int
    public let timing: TimingMode
    /// Whole seconds as entered: one step's time, or the time for all cycles together.
    public let enteredSeconds: Int

    public static func minuteRange(for timing: TimingMode) -> ClosedRange<Int> {
        timing == .perStep ? 0...120 : 0...600
    }

    public var stepCount: Int { cycles * Stage.all.count }
    public var enteredMinutes: Int { enteredSeconds / 60 }
    public var enteredSecondsComponent: Int { enteredSeconds % 60 }
    /// Equal for every step. A shared total may divide into fractions of a second.
    public var secondsPerStage: TimeInterval {
        timing == .perStep ? Double(enteredSeconds) : Double(enteredSeconds) / Double(stepCount)
    }
    public var secondsPerCycle: TimeInterval {
        timing == .perStep ? secondsPerStage * Double(Stage.all.count) : Double(enteredSeconds) / Double(cycles)
    }
    public var plannedSeconds: TimeInterval {
        timing == .perStep ? Double(enteredSeconds * stepCount) : Double(enteredSeconds)
    }

    public init(cycles: Int, minutesPerStep: Int, secondsPerStep: Int = 0) throws {
        try self.init(cycles: cycles, timing: .perStep, minutes: minutesPerStep, seconds: secondsPerStep)
    }

    public init(cycles: Int, totalMinutes: Int, totalSeconds: Int = 0) throws {
        try self.init(cycles: cycles, timing: .total, minutes: totalMinutes, seconds: totalSeconds)
    }

    public init(cycles: Int, timing: TimingMode, minutes: Int, seconds: Int = 0) throws {
        guard Self.cycleRange.contains(cycles) else { throw ValidationError.cycles }
        guard Self.minuteRange(for: timing).contains(minutes) else { throw ValidationError.minutes }
        guard Self.secondRange.contains(seconds) else { throw ValidationError.seconds }
        let entered = minutes * 60 + seconds
        switch timing {
        case .perStep:
            guard Self.durationRange.contains(entered) else { throw ValidationError.duration }
        case .total:
            // At least one second for every step, and no more than the ten-hour total.
            guard entered >= cycles * Stage.all.count, entered <= Self.maximumTotalSeconds else {
                throw ValidationError.duration
            }
        }
        self.cycles = cycles
        self.timing = timing
        self.enteredSeconds = entered
    }

    /// The same practice, entered the other way. A total that does not divide evenly rounds each
    /// step to the nearest second; a per-step practice longer than ten hours becomes the ten-hour total.
    public func expressed(as timing: TimingMode) -> SessionConfiguration {
        guard timing != self.timing else { return self }
        let seconds = timing == .total
            ? min(enteredSeconds * stepCount, Self.maximumTotalSeconds)
            : max(1, Int(secondsPerStage.rounded()))
        return try! SessionConfiguration(cycles: cycles, timing: timing, minutes: seconds / 60, seconds: seconds % 60)
    }

    /// ASCII digits only: a decimal, sign, blank, or embedded whitespace is not a whole number.
    public static func integer(_ text: String, in range: ClosedRange<Int>) -> Int? {
        guard !text.isEmpty, text.utf8.allSatisfy({ (48...57).contains($0) }),
              let value = Int(text), range.contains(value) else { return nil }
        return value
    }

    public enum ValidationError: Error { case cycles, minutes, seconds, duration }
}

public enum TimeText {
    public static func countdown(_ seconds: TimeInterval) -> String {
        clock(Int(ceil(max(0, seconds))))
    }

    public static func elapsed(_ seconds: TimeInterval) -> String {
        // A millisecond of tolerance keeps floating-point sums of a full 10:00 from reading 09:59.
        clock(Int(floor(max(0, seconds) + 0.001)))
    }

    public static func duration(_ seconds: TimeInterval) -> String {
        let whole = Int(max(0, seconds))
        if whole < 60 { return "\(whole) sec" }
        let minutes = whole / 60
        let remainder = whole % 60
        if minutes < 60 {
            return remainder == 0 ? "\(minutes) min" : "\(minutes) min \(remainder) sec"
        }
        let hours = minutes / 60
        let tail = minutes % 60
        var parts = ["\(hours) hr"]
        if tail > 0 { parts.append("\(tail) min") }
        if remainder > 0 { parts.append("\(remainder) sec") }
        return parts.joined(separator: " ")
    }

    /// Rounded to the nearest second, marked "≈" when a shared total does not divide evenly.
    public static func approximateDuration(_ seconds: TimeInterval) -> String {
        let rounded = seconds.rounded()
        let text = duration(rounded)
        return abs(seconds - rounded) < 0.0005 ? text : "≈ \(text)"
    }

    private static func clock(_ seconds: Int) -> String {
        if seconds >= 3600 {
            return String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
        }
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
