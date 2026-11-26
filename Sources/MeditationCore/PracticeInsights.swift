import Foundation

/// What the history says, as the journey screen shows it: totals, streaks, the trend over recent
/// weeks, and the hours of the week the practitioner tends to practice. Computed from day numbers
/// alone, so web/history.js gives the same numbers and the same words.
public struct PracticeInsights: Equatable, Sendable {
    public struct Totals: Equatable, Sendable {
        public var seconds = 0
        public var practices = 0
        public var cycles = 0
        public init(seconds: Int = 0, practices: Int = 0, cycles: Int = 0) {
            self.seconds = seconds
            self.practices = practices
            self.cycles = cycles
        }
    }

    /// The last four weeks against the four before.
    public enum Trend: String, Sendable { case rising, steady, easing, beginning, resting }

    /// Parts of the day, by the hour a practice begins.
    public enum Band: Int, CaseIterable, Sendable {
        case lateNight, earlyMorning, morning, afternoon, evening, night

        public init(hour: Int) {
            switch hour {
            case 0...3: self = .lateNight
            case 4...6: self = .earlyMorning
            case 7...11: self = .morning
            case 12...16: self = .afternoon
            case 17...20: self = .evening
            default: self = .night
            }
        }
    }

    /// How a total compares with the same span just before it.
    public struct Comparison: Equatable, Sendable {
        public enum Direction: String, Sendable { case up, down, same, none }
        public let direction: Direction
        public let text: String
        public init(direction: Direction, text: String) {
            self.direction = direction
            self.text = text
        }
    }

    public static let weeksShown = 12
    /// The hours of the week are read from the last twelve weeks.
    public static let rhythmDays = 84

    public let today: Int
    /// 0 is Sunday.
    public let firstWeekday: Int
    public let all: Totals
    public let firstDay: Int?
    public let activeDays: Int
    public let todayTotals: Totals
    public let last7: Int
    public let last7Practices: Int
    public let previous7: Int
    public let last30: Int
    public let previous30: Int
    public let currentStreak: Int
    public let bestStreak: Int
    public let recent28: Int
    public let previous28: Int
    public let trend: Trend
    /// The first day of each of the last twelve weeks, oldest first; the last is this week.
    public let weekStarts: [Int]
    public let weekTotals: [Int]
    /// Seconds practiced in practices begun in each hour of each weekday, over the last twelve weeks:
    /// `heat[weekday][hour]`, Sunday first.
    public let heat: [[Int]]
    public let rhythmPractices: Int
    public let peak: Band?
    public let quiet: Band?
    /// The weekday with the most practice in the peak part of the day.
    public let busiestWeekday: Int?
    /// Mornings of the last 30 with a practice begun between 3 and 5 am.
    public let amritVelaMornings: Int
    /// The daily time that shows in full gold: most days of the last year with practice reach it.
    public let fullDay: Int
    private let days: [Int: Totals]
    private let quietIsQuiet: Bool

    public init(_ history: PracticeHistory, today: Int, firstWeekday: Int) {
        self.today = today
        self.firstWeekday = ((firstWeekday % 7) + 7) % 7
        var days: [Int: Totals] = [:]
        var all = Totals()
        var heat = Array(repeating: Array(repeating: 0, count: 24), count: 7)
        var rhythmPractices = 0
        var amritVela = Set<Int>()
        for record in history.records {
            let day = record.day
            days[day, default: Totals()].seconds += record.seconds
            days[day, default: Totals()].practices += 1
            days[day, default: Totals()].cycles += record.cycles
            all.seconds += record.seconds
            all.practices += 1
            all.cycles += record.cycles
            if (today - Self.rhythmDays + 1...today).contains(day) {
                heat[CivilDate.weekday(day)][record.start.hour] += record.seconds
                rhythmPractices += 1
            }
            if (today - 29...today).contains(day) && (3...4).contains(record.start.hour) { amritVela.insert(day) }
        }
        self.days = days
        self.all = all
        self.heat = heat
        self.rhythmPractices = rhythmPractices
        amritVelaMornings = amritVela.count
        firstDay = history.records.map(\.day).min()
        activeDays = days.count
        todayTotals = days[today] ?? Totals()

        func span(_ from: Int, _ to: Int) -> Int { (from...to).reduce(0) { $0 + (days[$1]?.seconds ?? 0) } }
        last7 = span(today - 6, today)
        last7Practices = (today - 6...today).reduce(0) { $0 + (days[$1]?.practices ?? 0) }
        previous7 = span(today - 13, today - 7)
        last30 = span(today - 29, today)
        previous30 = span(today - 59, today - 30)
        recent28 = span(today - 27, today)
        previous28 = span(today - 55, today - 28)
        if recent28 == 0 && previous28 == 0 { trend = .resting }
        else if previous28 == 0 { trend = .beginning }
        else {
            let change = Double(recent28 - previous28) / Double(previous28)
            trend = change > 0.1 ? .rising : (change < -0.1 ? .easing : .steady)
        }

        // A streak lives on through today until the day is over.
        var streak = 0
        var day = days[today] != nil ? today : today - 1
        while days[day] != nil {
            streak += 1
            day -= 1
        }
        currentStreak = streak
        var best = 0, run = 0, previous: Int?
        for active in days.keys.sorted() {
            run = previous.map { active == $0 + 1 } == true ? run + 1 : 1
            best = max(best, run)
            previous = active
        }
        bestStreak = best

        let thisWeek = today - (CivilDate.weekday(today) - self.firstWeekday + 7) % 7
        weekStarts = (0..<Self.weeksShown).map { thisWeek - 7 * (Self.weeksShown - 1 - $0) }
        weekTotals = weekStarts.map { span($0, $0 + 6) }

        // The part of the day with the most practice, and the waking part with the least.
        var bands = Array(repeating: 0, count: Band.allCases.count)
        for weekday in 0..<7 {
            for hour in 0..<24 { bands[Band(hour: hour).rawValue] += heat[weekday][hour] }
        }
        if rhythmPractices >= 3 {
            var peak = Band.lateNight
            for band in Band.allCases where bands[band.rawValue] > bands[peak.rawValue] { peak = band }
            var quiet: Band?
            for band in [Band.afternoon, .evening, .morning, .earlyMorning, .night] where band != peak {
                if quiet == nil || bands[band.rawValue] < bands[quiet!.rawValue] { quiet = band }
            }
            // The weekday with the most practice in that part of the day.
            let peakHours = (0..<24).filter { Band(hour: $0) == peak }
            let weekdayTotals = heat.map { row in peakHours.reduce(0) { $0 + row[$1] } }
            var busiest = 0
            for weekday in 1..<7 where weekdayTotals[weekday] > weekdayTotals[busiest] { busiest = weekday }
            self.peak = peak
            self.quiet = quiet
            busiestWeekday = busiest
            quietIsQuiet = quiet.map { bands[$0.rawValue] * 100 <= bands[peak.rawValue] * 15 } ?? false
        } else {
            peak = nil
            quiet = nil
            busiestWeekday = nil
            quietIsQuiet = false
        }

        // The 90th percentile of the last year's days with practice, and never under a minute.
        let year = days.filter { (today - 364...today).contains($0.key) }.map(\.value.seconds).sorted()
        fullDay = year.isEmpty ? 0 : max(PracticeRecord.minimumSeconds, year[(9 * year.count + 9) / 10 - 1])
    }

    public func totals(on day: Int) -> Totals { days[day] ?? Totals() }

    /// How brightly a day shows on the calendar, from 0 (no practice) to 4 (a full day).
    public func level(forDay day: Int) -> Int {
        let seconds = totals(on: day).seconds
        guard seconds > 0, fullDay > 0 else { return 0 }
        return seconds >= fullDay ? 4 : 1 + 3 * seconds / fullDay
    }

    /// How brightly an hour of the week shows, from 0 to 4 (the hour with the most practice).
    public func heatLevel(weekday: Int, hour: Int) -> Int {
        let most = heat.joined().max() ?? 0
        let seconds = heat[weekday][hour]
        guard seconds > 0, most > 0 else { return 0 }
        return 1 + 3 * seconds / most
    }

    /// The day this week begins.
    public func weekStart(of day: Int) -> Int { day - (CivilDate.weekday(day) - firstWeekday + 7) % 7 }

    /// The seven weekdays in calendar order, starting with the first.
    public var weekdayOrder: [Int] { (0..<7).map { (firstWeekday + $0) % 7 } }

    // MARK: Words

    public var todayDetail: String {
        guard todayTotals.practices > 0 else { return "Not yet today" }
        return "\(HistoryText.count(todayTotals.practices, "practice")) · \(HistoryText.count(todayTotals.cycles, "cycle"))"
    }

    public var weekComparison: Comparison { Self.compare(last7, previous7, span: "7 days") }
    public var monthComparison: Comparison { Self.compare(last30, previous30, span: "30 days") }

    public var streakValue: String { HistoryText.count(currentStreak, "day") }
    public var streakDetail: String {
        if currentStreak == 0 { return bestStreak > 0 ? "Best: \(HistoryText.count(bestStreak, "day"))" : "Practice on days in a row" }
        if todayTotals.practices == 0 { return "Practice today to keep it" }
        return currentStreak >= bestStreak ? "Your longest yet" : "Best: \(HistoryText.count(bestStreak, "day"))"
    }

    /// Every saved session begun today or in the six preceding calendar days has equal weight,
    /// including freestyle and sessions ended early. No sessions means no average.
    public var averageSessionSeconds: Int? {
        guard last7Practices > 0 else { return nil }
        return Int((Double(last7) / Double(last7Practices)).rounded())
    }

    public var trendTitle: String {
        switch trend {
        case .rising: return "Rising"
        case .steady: return "Steady"
        case .easing: return "Easing off"
        case .beginning: return "Beginning"
        case .resting: return "Resting"
        }
    }

    public var trendDetail: String {
        let recent = HistoryText.minutes(recent28)
        switch trend {
        case .rising, .easing:
            let change = abs(Double(recent28 - previous28) / Double(previous28))
            return "\(recent) in the last four weeks, \(trend == .rising ? "up" : "down") \(Int((change * 100).rounded()))% on the four before."
        case .steady: return "\(recent) in the last four weeks, much as in the four before."
        case .beginning: return "\(recent) in the last four weeks, your first. Keep going, and your trend will show here."
        case .resting: return "No practice in the last eight weeks. A single cycle begins again."
        }
    }

    /// A few plain sentences about when the practitioner practices, and when they might.
    public var rhythmNotes: [String] {
        guard let peak, let busiestWeekday else {
            return ["Practice a few more times, and the hours you favor will show here."]
        }
        var notes = ["You practice most \(Self.phrase(peak)), especially on \(HistoryText.weekdays[busiestWeekday])s."]
        if let quiet, quietIsQuiet {
            notes.append(Self.suggestion(quiet))
        } else {
            notes.append("Your practice is spread across the day.")
        }
        if amritVelaMornings > 0 {
            notes.append("Amrit vela, 3 to 5 am: \(amritVelaMornings) of the last 30 mornings.")
        }
        return notes
    }

    private static func phrase(_ band: Band) -> String {
        switch band {
        case .lateNight: return "late at night"
        case .earlyMorning: return "in the early morning"
        case .morning: return "in the morning"
        case .afternoon: return "in the afternoon"
        case .evening: return "in the evening"
        case .night: return "at night"
        }
    }

    private static func suggestion(_ band: Band) -> String {
        switch band {
        case .earlyMorning: return "Your early mornings are quiet. Amrit vela, before dawn, is a gentle time to begin."
        case .morning: return "Your mornings are quiet. A cycle before the day gets busy could set its tone."
        case .afternoon: return "Your afternoons are quiet. A short cycle after lunch could carry the calm through the day."
        case .evening: return "Your evenings are quiet. A cycle as the day winds down could help you settle."
        case .night, .lateNight: return "Your nights are quiet. A cycle before sleep could close the day gently."
        }
    }

    private static func compare(_ current: Int, _ previous: Int, span: String) -> Comparison {
        if previous == 0 {
            return current == 0 ? Comparison(direction: .none, text: "None in the \(span) before either")
                                : Comparison(direction: .up, text: "Up from none in the \(span) before")
        }
        let change = Int((abs(Double(current - previous)) / Double(previous) * 100).rounded())
        if change == 0 { return Comparison(direction: .same, text: "The same as the \(span) before") }
        return Comparison(direction: current > previous ? .up : .down,
                          text: "\(current > previous ? "Up" : "Down") \(change)% on the \(span) before")
    }
}

/// Words and numbers for the history, the same on the Mac and on the web.
public enum HistoryText {
    public static let months = ["January", "February", "March", "April", "May", "June", "July", "August",
                                "September", "October", "November", "December"]
    /// Sunday first.
    public static let weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    /// Whole minutes: "45 min", "2 hr 10 min", "2 hr"; "< 1 min" for a few seconds, "0 min" for none.
    public static func minutes(_ seconds: Int) -> String {
        let minutes = Int((Double(max(0, seconds)) / 60).rounded())
        if minutes == 0 { return seconds > 0 ? "< 1 min" : "0 min" }
        if minutes < 60 { return "\(minutes) min" }
        return minutes % 60 == 0 ? "\(minutes / 60) hr" : "\(minutes / 60) hr \(minutes % 60) min"
    }

    /// The shortest form, for a calendar day beside its cycles: "45m", "2h10", "2h"; "<1m" for a few
    /// seconds; empty for none.
    public static func compact(_ seconds: Int) -> String {
        let minutes = Int((Double(max(0, seconds)) / 60).rounded())
        if minutes == 0 { return seconds > 0 ? "<1m" : "" }
        if minutes < 60 { return "\(minutes)m" }
        return minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h\(String(format: "%02d", minutes % 60))"
    }

    public static func count(_ number: Int, _ singular: String) -> String {
        "\(number) \(singular)\(number == 1 ? "" : "s")"
    }

    /// "18 November 2026"
    public static func date(_ day: Int) -> String {
        let date = CivilDate(dayNumber: day)
        return "\(date.day) \(months[date.month - 1]) \(date.year)"
    }

    /// "Tuesday, 18 November"
    public static func dayTitle(_ day: Int) -> String {
        let date = CivilDate(dayNumber: day)
        return "\(weekdays[CivilDate.weekday(day)]), \(date.day) \(months[date.month - 1])"
    }

    /// "18 Nov"
    public static func shortDate(_ day: Int) -> String {
        let date = CivilDate(dayNumber: day)
        return "\(date.day) \(months[date.month - 1].prefix(3))"
    }

    /// "6:42 am"
    public static func time(hour: Int, minute: Int) -> String {
        "\(hour % 12 == 0 ? 12 : hour % 12):\(String(format: "%02d", minute)) \(hour < 12 ? "am" : "pm")"
    }

    /// The marks along the hours of the day: "12a", "3a", … "9p".
    public static func hourMark(_ hour: Int) -> String {
        "\(hour % 12 == 0 ? 12 : hour % 12)\(hour < 12 ? "a" : "p")"
    }
}
