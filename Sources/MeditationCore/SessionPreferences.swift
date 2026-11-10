import Foundation

public enum SessionPreferences {
    public static func load(from defaults: UserDefaults) -> SessionConfiguration {
        let savedCycles = defaults.integer(forKey: "cycles")
        let cycles = SessionConfiguration.cycleRange.contains(savedCycles) ? savedCycles : 1
        if defaults.string(forKey: "timingMode") == TimingMode.total.rawValue {
            let total = defaults.integer(forKey: "totalDurationSeconds")
            if let configuration = try? SessionConfiguration(cycles: cycles, totalMinutes: total / 60,
                                                              totalSeconds: total % 60) {
                return configuration
            }
        }
        let savedDuration = defaults.integer(forKey: "stepDurationSeconds")
        let oldCycleMinutes = defaults.integer(forKey: "minutesPerCycle")
        let duration: Int
        if SessionConfiguration.durationRange.contains(savedDuration) {
            duration = savedDuration
        } else if (1...120).contains(oldCycleMinutes) {
            // Preserve the original practice pace exactly, including e.g. 7 min / 5 = 1:24.
            duration = oldCycleMinutes * 12
        } else {
            duration = SessionConfiguration.standard.enteredSeconds
        }
        return try! SessionConfiguration(cycles: cycles, minutesPerStep: duration / 60,
                                         secondsPerStep: duration % 60)
    }

    public static func save(_ configuration: SessionConfiguration, to defaults: UserDefaults) {
        defaults.set(configuration.cycles, forKey: "cycles")
        defaults.set(configuration.timing.rawValue, forKey: "timingMode")
        let key = configuration.timing == .perStep ? "stepDurationSeconds" : "totalDurationSeconds"
        defaults.set(configuration.enteredSeconds, forKey: key)
    }
}
