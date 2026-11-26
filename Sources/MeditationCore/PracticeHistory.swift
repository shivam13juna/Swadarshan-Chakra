import Foundation

// The practice history: every practice kept on this device, and the backup file that carries it to
// another. web/history.js reads and writes the same file; keep the two in step (Tests/fixtures).

/// A date on the practitioner's own calendar. Days are counted from 1 January 1970 as plain numbers,
/// so the Mac app and the web version agree exactly, whatever time zone either runs in.
public struct CivilDate: Equatable, Hashable, Sendable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init?(year: Int, month: Int, day: Int) {
        guard (1970...9999).contains(year), (1...12).contains(month),
              (1...Self.days(inMonth: month, year: year)).contains(day) else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    /// The date a day number names (Howard Hinnant's civil_from_days).
    public init(dayNumber: Int) {
        let z = dayNumber + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let dayOfEra = z - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let shiftedMonth = (5 * dayOfYear + 2) / 153
        day = dayOfYear - (153 * shiftedMonth + 2) / 5 + 1
        month = shiftedMonth < 10 ? shiftedMonth + 3 : shiftedMonth - 9
        year = yearOfEra + era * 400 + (month <= 2 ? 1 : 0)
    }

    /// Days since 1 January 1970 (Howard Hinnant's days_from_civil).
    public var dayNumber: Int {
        let shiftedYear = month <= 2 ? year - 1 : year
        let era = (shiftedYear >= 0 ? shiftedYear : shiftedYear - 399) / 400
        let yearOfEra = shiftedYear - era * 400
        let dayOfYear = (153 * (month > 2 ? month - 3 : month + 9) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    /// 0 is Sunday, 6 is Saturday. 1 January 1970 was a Thursday.
    public static func weekday(_ dayNumber: Int) -> Int { ((dayNumber % 7) + 11) % 7 }

    public static func days(inMonth month: Int, year: Int) -> Int {
        switch month {
        case 2: return year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }
}

/// When a practice began, on the clock where it happened, to the second: "2026-11-18T06:42:10+05:30",
/// or "2026-11-18T01:12:10Z" in UTC. Practices are counted by their own local day and hour.
public struct PracticeTime: Equatable, Sendable {
    public let date: CivilDate
    public let hour: Int
    public let minute: Int
    public let second: Int
    /// Minutes ahead of UTC.
    public let offset: Int

    public init?(_ text: String) {
        let c = Array(text.utf8)
        guard c.count == 20 || c.count == 25 else { return nil }
        func digits(_ start: Int, _ count: Int) -> Int? {
            var value = 0
            for index in start..<(start + count) {
                guard (48...57).contains(c[index]) else { return nil }
                value = value * 10 + Int(c[index] - 48)
            }
            return value
        }
        // "-", "-", "T", ":", ":"
        guard c[4] == 45, c[7] == 45, c[10] == 84, c[13] == 58, c[16] == 58,
              let year = digits(0, 4), let month = digits(5, 2), let day = digits(8, 2),
              let hour = digits(11, 2), let minute = digits(14, 2), let second = digits(17, 2),
              let date = CivilDate(year: year, month: month, day: day),
              hour < 24, minute < 60, second < 60 else { return nil }
        var offset = 0
        if c.count == 20 {
            guard c[19] == 90 else { return nil }   // "Z"
        } else {
            guard c[19] == 43 || c[19] == 45, c[22] == 58,
                  let hours = digits(20, 2), let minutes = digits(23, 2), hours <= 14, minutes < 60 else { return nil }
            offset = (hours * 60 + minutes) * (c[19] == 45 ? -1 : 1)
        }
        self.date = date
        self.hour = hour
        self.minute = minute
        self.second = second
        self.offset = offset
    }

    /// A moment on this Mac's clock, or in another time zone.
    public init?(_ moment: Date, in timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: moment)
        guard let year = parts.year, let month = parts.month, let day = parts.day,
              let date = CivilDate(year: year, month: month, day: day) else { return nil }
        self.date = date
        hour = parts.hour ?? 0
        minute = parts.minute ?? 0
        second = parts.second ?? 0
        offset = timeZone.secondsFromGMT(for: moment) / 60
    }

    public var text: String {
        let clock = String(format: "%04d-%02d-%02dT%02d:%02d:%02d", date.year, date.month, date.day, hour, minute, second)
        guard offset != 0 else { return clock + "Z" }
        return clock + String(format: "%@%02d:%02d", offset < 0 ? "-" : "+", abs(offset) / 60, abs(offset) % 60)
    }

    public var dayNumber: Int { date.dayNumber }
    /// Seconds since 1970 in UTC, which orders practices begun in different time zones.
    public var instant: Int { dayNumber * 86_400 + hour * 3600 + minute * 60 + second - offset * 60 }
}

/// One practice, as kept in the history and written to backups.
public struct PracticeRecord: Equatable, Sendable {
    /// A practice is kept once it has a minute of practice, or a whole cycle.
    public static let minimumSeconds = 60
    public static let maximumSeconds = 10_000_000

    public let id: String
    public let start: PracticeTime
    /// The time practiced, as the completion screen counts it.
    public let seconds: Int
    public let cycles: Int
    public let planned: Int
    public let timing: TimingMode
    /// The time given to each of the five steps, all cycles together, when known.
    public let steps: [Int]?
    /// Where it was practiced: "mac" or "web".
    public let device: String?
    /// A practice entered by the practitioner, rather than recorded by the app's timer.
    public let manual: Bool

    public init?(id: String, start: PracticeTime, seconds: Int, cycles: Int, planned: Int, timing: TimingMode,
                 steps: [Int]?, device: String?, manual: Bool = false) {
        guard (1...100).contains(id.count), (0...Self.maximumSeconds).contains(seconds),
              SessionConfiguration.cycleRange.contains(planned), (0...planned).contains(cycles) else { return nil }
        if let steps {
            guard steps.count == Stage.all.count,
                  steps.allSatisfy({ (0...Self.maximumSeconds).contains($0) }) else { return nil }
        }
        if let device { guard (1...40).contains(device.count) else { return nil } }
        if manual {
            guard cycles == planned, (1...86_400).contains(seconds), steps == nil else { return nil }
        }
        self.id = id
        self.start = start
        self.seconds = seconds
        self.cycles = cycles
        self.planned = planned
        self.timing = timing
        self.steps = steps
        self.device = device
        self.manual = manual
    }

    /// A completed practice elsewhere. Its aggregate time is known; individual form times are not.
    /// Freestyle keeps version-one backups compatible: no app timer was used for this session.
    public static func manuallyAdded(id: String, start: PracticeTime, seconds: Int, cycles: Int) -> PracticeRecord? {
        guard (1...86_400).contains(seconds), SessionConfiguration.cycleRange.contains(cycles) else { return nil }
        return PracticeRecord(id: id, start: start, seconds: seconds, cycles: cycles, planned: cycles,
                              timing: .freestyle, steps: nil, device: nil, manual: true)
    }

    /// Manual entries describe complete cycles, each with five steps.
    public var averageSecondsPerStep: Double? {
        guard manual, cycles > 0 else { return nil }
        return Double(seconds) / Double(cycles * Stage.all.count)
    }

    /// The practice under way or just ended, as the engine has counted it.
    public init?(id: String, start: PracticeTime, engine: SessionEngine, device: String) {
        let steps = (0..<Stage.all.count).map { step in
            Int(engine.stepSeconds.reduce(0) { $0 + $1[step] }.rounded())
        }
        self.init(id: id, start: start, seconds: Int(engine.activeSeconds.rounded()), cycles: engine.completedCycles,
                  planned: engine.configuration.cycles, timing: engine.configuration.timing, steps: steps, device: device)
    }

    /// Whether the practice so far is worth keeping: a minute of practice, or a whole cycle.
    public static func isWorthKeeping(_ engine: SessionEngine) -> Bool {
        engine.activeSeconds >= Double(minimumSeconds) || engine.completedCycles >= 1
    }

    /// One entry of a backup's "practices", as JSONSerialization reads it. Nil when any field is wrong.
    public init?(json: Any) {
        guard let object = json as? [String: Any], let id = object["id"] as? String,
              let startText = object["start"] as? String, let start = PracticeTime(startText),
              let seconds = Self.integer(object["seconds"]), let cycles = Self.integer(object["cycles"]),
              let planned = Self.integer(object["planned"]),
              let timingText = object["timing"] as? String, let timing = TimingMode(rawValue: timingText) else { return nil }
        var steps: [Int]?
        if let value = object["steps"], !(value is NSNull) {
            guard let list = value as? [Any] else { return nil }
            let numbers = list.compactMap(Self.integer)
            guard numbers.count == list.count else { return nil }
            steps = numbers
        }
        var device: String?
        if let value = object["device"], !(value is NSNull) {
            guard let text = value as? String else { return nil }
            device = text
        }
        var manual = false
        if let value = object["manual"] {
            guard let boolean = value as? NSNumber, CFGetTypeID(boolean) == CFBooleanGetTypeID() else { return nil }
            manual = boolean.boolValue
        }
        self.init(id: id, start: start, seconds: seconds, cycles: cycles, planned: planned, timing: timing,
                  steps: steps, device: device, manual: manual)
    }

    /// A whole number, as JSON writes it: not a fraction, and not true or false.
    private static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let double = number.doubleValue
        guard double.rounded() == double, abs(double) < 1e15 else { return nil }
        return number.intValue
    }

    public var completed: Bool { cycles >= planned }
    public var day: Int { start.dayNumber }

    /// One line of JSON, its fields in a fixed order.
    public var json: String {
        var fields = ["\"id\":\(Self.quoted(id))", "\"start\":\(Self.quoted(start.text))", "\"seconds\":\(seconds)",
                      "\"cycles\":\(cycles)", "\"planned\":\(planned)", "\"timing\":\(Self.quoted(timing.rawValue))"]
        if let steps { fields.append("\"steps\":[\(steps.map(String.init).joined(separator: ","))]") }
        if let device { fields.append("\"device\":\(Self.quoted(device))") }
        if manual { fields.append("\"manual\":true") }
        return "{\(fields.joined(separator: ","))}"
    }

    static func quoted(_ text: String) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return String(decoding: (try? encoder.encode(text)) ?? Data("\"\"".utf8), as: UTF8.self)
    }
}

/// Every practice kept on this device, oldest first, each once.
public struct PracticeHistory: Equatable, Sendable {
    /// What a backup file says it is, and the newest layout this version reads.
    public static let format = "swadarshan-chakra-history"
    public static let version = 1

    public enum ReadError: Error, Equatable {
        /// Not JSON, or not an object.
        case unreadable
        /// JSON, but not a Swadarshan Chakra backup.
        case notABackup
        /// A backup from a newer version of the app.
        case newerVersion(Int)
    }

    /// What a merge did: practices new to this device, practices it already had in part and now has
    /// in full, and practices it already had.
    public struct Merge: Equatable, Sendable {
        public var added = 0
        public var updated = 0
        public var unchanged = 0
        public init(added: Int = 0, updated: Int = 0, unchanged: Int = 0) {
            self.added = added
            self.updated = updated
            self.unchanged = unchanged
        }
    }

    public private(set) var records: [PracticeRecord] = []

    public init(_ records: [PracticeRecord] = []) {
        merge(records)
    }

    public var isEmpty: Bool { records.isEmpty }

    /// Saves the practice under way, replacing what was kept of it before.
    public mutating func upsert(_ record: PracticeRecord) {
        records.removeAll { $0.id == record.id }
        insert(record)
    }

    /// Adds practices this device doesn't have yet. A practice it has already is kept as it is, unless
    /// the other copy is the longer one: a practice saved partway and finished later.
    @discardableResult
    public mutating func merge(_ incoming: [PracticeRecord]) -> Merge {
        var result = Merge()
        var index = Dictionary(records.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        for record in incoming {
            if let position = index[record.id] {
                if record.seconds > records[position].seconds {
                    records[position] = record
                    result.updated += 1
                } else {
                    result.unchanged += 1
                }
            } else {
                index[record.id] = records.count
                records.append(record)
                result.added += 1
            }
        }
        if result.added + result.updated > 0 { records.sort(by: Self.isOrdered) }
        return result
    }

    public func records(on day: Int) -> [PracticeRecord] { records.filter { $0.day == day } }

    /// The backup file, or the history file kept on this Mac: a small JSON document, one practice per line.
    public func document(exported: PracticeTime? = nil) -> Data {
        var lines = ["{", "  \"format\": \"\(Self.format)\",", "  \"version\": \(Self.version),",
                     "  \"app\": \"Swadarshan Chakra\","]
        if let exported { lines.append("  \"exported\": \"\(exported.text)\",") }
        if records.isEmpty {
            lines.append("  \"practices\": []")
        } else {
            lines.append("  \"practices\": [")
            lines += records.indices.map { "    \(records[$0].json)\($0 == records.count - 1 ? "" : ",")" }
            lines.append("  ]")
        }
        lines.append("}")
        return Data((lines.joined(separator: "\n") + "\n").utf8)
    }

    /// Reads a backup or history file. Practices that can't be read are left out and counted.
    public static func read(_ data: Data) throws -> (history: PracticeHistory, skipped: Int) {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw ReadError.unreadable
        }
        guard object["format"] as? String == format, let practices = object["practices"] as? [Any] else {
            throw ReadError.notABackup
        }
        guard let number = object["version"] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.rounded() == number.doubleValue, number.intValue >= 1 else {
            throw ReadError.notABackup
        }
        guard number.intValue <= version else { throw ReadError.newerVersion(number.intValue) }
        let records = practices.compactMap(PracticeRecord.init(json:))
        return (PracticeHistory(records), practices.count - records.count)
    }

    /// What a backup's file name should be: "Swadarshan Chakra backup 2026-11-18.json".
    public static func backupName(on day: Int) -> String {
        let date = CivilDate(dayNumber: day)
        return String(format: "Swadarshan Chakra backup %04d-%02d-%02d.json", date.year, date.month, date.day)
    }

    private mutating func insert(_ record: PracticeRecord) {
        let position = records.firstIndex { Self.isOrdered(record, $0) } ?? records.count
        records.insert(record, at: position)
    }

    private static func isOrdered(_ first: PracticeRecord, _ second: PracticeRecord) -> Bool {
        let (a, b) = (first.start.instant, second.start.instant)
        return a != b ? a < b : first.id < second.id
    }
}

extension PracticeHistory.Merge {
    /// What an import did, in a sentence or two.
    public func summary(of file: String, skipped: Int) -> String {
        var parts: [String] = []
        if added == 0 && updated == 0 {
            parts.append("Everything in “\(file)” was already here.")
        } else {
            if added > 0 { parts.append("Added \(HistoryText.count(added, "practice")) from “\(file)”.") }
            if updated > 0 { parts.append("Brought \(HistoryText.count(updated, "practice")) up to date\(added > 0 ? "" : " from “\(file)”").") }
            if unchanged > 0 { parts.append("\(unchanged) \(unchanged == 1 ? "was" : "were") already here.") }
        }
        if skipped > 0 { parts.append("\(skipped) couldn't be read and \(skipped == 1 ? "was" : "were") left out.") }
        return parts.joined(separator: " ")
    }
}

extension PracticeHistory.ReadError {
    /// Why a file couldn't be imported.
    public func message(for file: String) -> String {
        switch self {
        case .unreadable: return "“\(file)” couldn't be read. Choose a backup saved by Swadarshan Chakra."
        case .notABackup: return "“\(file)” isn't a Swadarshan Chakra backup."
        case .newerVersion: return "“\(file)” comes from a newer version of Swadarshan Chakra. Update this one to import it."
        }
    }
}
