import Foundation

public struct SessionConfiguration: Equatable, Sendable {
    public static let cycleRange = 1...108
    public static let minuteRange = 0...120
    public static let secondRange = 0...59
    public static let durationRange = 1...7200
    public static let standard = try! SessionConfiguration(cycles: 1, minutesPerStep: 1)

    public let cycles: Int
    public let stepDurationSeconds: Int
    public var minutesPerStep: Int { stepDurationSeconds / 60 }
    public var secondsComponent: Int { stepDurationSeconds % 60 }
    public var secondsPerStage: TimeInterval { Double(stepDurationSeconds) }
    public var secondsPerCycle: TimeInterval { secondsPerStage * Double(Stage.all.count) }
    public var plannedSeconds: TimeInterval { Double(cycles) * secondsPerCycle }

    public init(cycles: Int, minutesPerStep: Int, secondsPerStep: Int = 0) throws {
        guard Self.cycleRange.contains(cycles) else { throw ValidationError.cycles }
        guard Self.minuteRange.contains(minutesPerStep) else { throw ValidationError.minutes }
        guard Self.secondRange.contains(secondsPerStep) else { throw ValidationError.seconds }
        let duration = minutesPerStep * 60 + secondsPerStep
        guard Self.durationRange.contains(duration) else { throw ValidationError.duration }
        self.cycles = cycles
        self.stepDurationSeconds = duration
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
        clock(Int(floor(max(0, seconds))))
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

    private static func clock(_ seconds: Int) -> String {
        if seconds >= 3600 {
            return String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
        }
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
