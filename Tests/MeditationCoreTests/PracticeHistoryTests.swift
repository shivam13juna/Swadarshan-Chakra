import Foundation
import MeditationCore

/// The practice history, its backup file, and the insights drawn from it. Tests/web/history-checks.mjs
/// asserts the same numbers and words on the same fixture, so the Mac and the web read each other's backups.
struct PracticeHistoryTests {
    private static let fixtureURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("fixtures/history-v1.json")
    private let today = 20775   // Wednesday, 18 November 2026
    private let monday = 1

    private func fixture() throws -> Data { try Data(contentsOf: Self.fixtureURL) }
    private func time(_ text: String) -> PracticeTime { PracticeTime(text)! }
    private func record(_ id: String, _ start: String, _ seconds: Int, cycles: Int = 1, planned: Int? = nil) -> PracticeRecord {
        PracticeRecord(id: id, start: time(start), seconds: seconds, cycles: cycles, planned: planned ?? cycles,
                       timing: .perStep, steps: nil, device: nil)!
    }
    private func dayRecord(_ offset: Int, _ seconds: Int) -> PracticeRecord {
        let date = CivilDate(dayNumber: today - offset)
        return record("d\(offset)", String(format: "%04d-%02d-%02dT07:00:00+05:30", date.year, date.month, date.day), seconds)
    }

    func testCalendarDays() {
        Check.equal(CivilDate(year: 1970, month: 1, day: 1)!.dayNumber, 0)
        Check.equal(CivilDate(year: 2026, month: 11, day: 18)!.dayNumber, today)
        Check.equal(CivilDate.weekday(0), 4)
        Check.equal(CivilDate.weekday(today), 3)
        Check.equal(CivilDate.days(inMonth: 2, year: 2024), 29)
        Check.equal(CivilDate.days(inMonth: 2, year: 2100), 28)
        Check.equal(CivilDate.days(inMonth: 2, year: 2000), 29)
        var roundTrips = true
        for day in stride(from: 0, to: 40000, by: 37) where CivilDate(dayNumber: day).dayNumber != day { roundTrips = false }
        Check.isTrue(roundTrips)
        Check.equal(CivilDate(dayNumber: 20513), CivilDate(year: 2026, month: 3, day: 1)!)
        Check.isNil(CivilDate(year: 2026, month: 2, day: 29))
    }

    func testPracticeTimes() {
        let india = time("2026-11-18T06:42:10+05:30")
        Check.equal([india.dayNumber, india.hour, india.minute, india.second, india.offset], [today, 6, 42, 10, 330])
        Check.equal(india.instant, today * 86400 + 6 * 3600 + 42 * 60 + 10 - 330 * 60)
        Check.equal(time("2026-11-18T01:12:10Z").instant, india.instant)
        Check.equal(time("2026-10-25T06:30:00-07:00").offset, -420)
        for bad in ["2026-11-18T06:42:10", "2026-11-18 06:42:10Z", "2026-13-01T00:00:00Z", "2026-11-18T24:00:00Z",
                    "2026-11-18T06:42:10+15:00", "2026-02-29T00:00:00Z", "1969-12-31T23:59:59Z", "2026-11-18T06:42:10.5Z",
                    "2026-11-18T06:42:10+0530", ""] {
            Check.isNil(PracticeTime(bad), bad)
        }
        for text in ["2026-11-18T06:42:10+05:30", "2026-11-18T01:12:10Z", "2026-10-25T06:30:00-07:00", "2024-02-29T23:59:59+14:00"] {
            Check.equal(time(text).text, text)
        }
        let moment = Date(timeIntervalSince1970: Double(india.instant))
        Check.equal(PracticeTime(moment, in: TimeZone(identifier: "Asia/Kolkata")!)?.text, "2026-11-18T06:42:10+05:30")
        Check.equal(PracticeTime(moment, in: TimeZone(secondsFromGMT: 0)!)?.text, "2026-11-18T01:12:10Z")
        Check.equal(PracticeTime(Date(timeIntervalSince1970: Double(time("2026-10-25T06:30:00-07:00").instant)),
                                 in: TimeZone(identifier: "America/Los_Angeles")!)?.text, "2026-10-25T06:30:00-07:00")
        Check.equal(PracticeTime(moment)?.instant, india.instant)
    }

    func testReadingTheSharedBackup() throws {
        let (history, skipped) = try PracticeHistory.read(fixture())
        Check.equal(skipped, 12)
        Check.equal(history.records.map(\.id).joined(separator: " "),
                    "a20 a19 a18 b05 b06 b07 b08 b09 b10 a17 a09 a08 a07 a06 a05 a04 a03 a01 a02")
        func kept(_ id: String) -> PracticeRecord { history.records.first { $0.id == id }! }
        Check.equal([kept("a06").seconds, kept("a06").cycles], [900, 2])
        Check.equal(kept("a03").seconds, 1500)
        Check.isNil(kept("a08").steps)
        Check.isNil(kept("a08").device)
        Check.equal(kept("a02").steps, [60, 70, 50, 80, 70])
        Check.equal(kept("a09").day, CivilDate(year: 2026, month: 10, day: 25)!.dayNumber)
        Check.equal(history.records(on: today).map(\.id), ["a01", "a02"])
    }

    func testInsightsFromTheSharedBackup() throws {
        let insights = PracticeInsights(try PracticeHistory.read(fixture()).history, today: today, firstWeekday: monday)
        Check.equal(insights.all, .init(seconds: 18150, practices: 19, cycles: 59))
        Check.equal(insights.firstDay, 20393)
        Check.equal(insights.activeDays, 18)
        Check.equal(insights.todayTotals, .init(seconds: 1230, practices: 2, cycles: 4))
        Check.equal([insights.last7, insights.previous7, insights.last30, insights.previous30], [5430, 3600, 10950, 5400])
        Check.equal([insights.currentStreak, insights.bestStreak], [4, 6])
        Check.equal([insights.recent28, insights.previous28], [10650, 5700])
        Check.equal(insights.trend, .rising)
        Check.equal(insights.weekStarts, [20696, 20703, 20710, 20717, 20724, 20731, 20738, 20745, 20752, 20759, 20766, 20773])
        Check.equal(insights.weekTotals, [0, 0, 1200, 0, 1800, 3600, 0, 1200, 720, 0, 5700, 3330])
        Check.equal(insights.rhythmPractices, 18)
        Check.equal(insights.peak, .earlyMorning)
        Check.equal(insights.quiet, .afternoon)
        Check.equal(insights.busiestWeekday, 1)
        Check.equal([insights.amritVelaMornings, insights.fullDay], [2, 1800])
        Check.equal([insights.heat[1][6], insights.heat[0][1], insights.heat[2][21]], [2400, 720, 3600])
        Check.equal([insights.heatLevel(weekday: 1, hour: 6), insights.heatLevel(weekday: 0, hour: 1),
                     insights.heatLevel(weekday: 2, hour: 21), insights.heatLevel(weekday: 2, hour: 2)], [3, 1, 4, 0])
        Check.equal([today, today - 2, today - 8, today - 4].map(insights.level(forDay:)), [3, 2, 4, 0])
        Check.equal(insights.weekdayOrder, [1, 2, 3, 4, 5, 6, 0])
        Check.equal(insights.todayDetail, "2 practices · 4 cycles")
        Check.equal(insights.weekComparison, .init(direction: .up, text: "Up 51% on the 7 days before"))
        Check.equal(insights.monthComparison, .init(direction: .up, text: "Up 103% on the 30 days before"))
        Check.equal([insights.streakValue, insights.streakDetail], ["4 days", "Best: 6 days"])
        Check.equal(insights.last7Practices, 6)
        Check.equal(insights.averageSessionSeconds, 905)
        Check.equal([insights.trendTitle, insights.trendDetail],
                    ["Rising", "2 hr 58 min in the last four weeks, up 87% on the four before."])
        Check.equal(insights.rhythmNotes, [
            "You practice most in the early morning, especially on Mondays.",
            "Your afternoons are quiet. A short cycle after lunch could carry the calm through the day.",
            "Amrit vela, 3 to 5 am: 2 of the last 30 mornings."
        ])
        Check.equal(PracticeInsights(PracticeHistory(), today: today, firstWeekday: 0).weekStart(of: today), 20772)
    }

    func testAnEmptyHistory() {
        let insights = PracticeInsights(PracticeHistory(), today: today, firstWeekday: monday)
        Check.equal([insights.all.seconds, insights.currentStreak, insights.bestStreak], [0, 0, 0])
        Check.isNil(insights.firstDay)
        Check.equal(insights.trend, .resting)
        Check.equal(insights.trendTitle, "Resting")
        Check.equal(insights.weekTotals, Array(repeating: 0, count: 12))
        Check.equal([insights.todayDetail, insights.streakDetail], ["Not yet today", "Practice on days in a row"])
        Check.equal(insights.last7Practices, 0)
        Check.isNil(insights.averageSessionSeconds)
        Check.equal(insights.weekComparison, .init(direction: .none, text: "None in the 7 days before either"))
        Check.equal(insights.rhythmNotes, ["Practice a few more times, and the hours you favor will show here."])
        Check.equal([insights.level(forDay: today), insights.heatLevel(weekday: 3, hour: 6)], [0, 0])
    }

    func testTrendsAndStreaks() {
        let steady = PracticeInsights(PracticeHistory([dayRecord(3, 1000), dayRecord(40, 1050)]), today: today, firstWeekday: monday)
        Check.equal(steady.trend, .steady)
        Check.equal(steady.trendDetail, "17 min in the last four weeks, much as in the four before.")
        let easing = PracticeInsights(PracticeHistory([dayRecord(3, 800), dayRecord(40, 1000)]), today: today, firstWeekday: monday)
        Check.equal(easing.trend, .easing)
        Check.equal([easing.trendTitle, easing.trendDetail],
                    ["Easing off", "13 min in the last four weeks, down 20% on the four before."])
        let beginning = PracticeInsights(PracticeHistory([dayRecord(1, 600), dayRecord(2, 600)]), today: today, firstWeekday: monday)
        Check.equal(beginning.trend, .beginning)
        Check.equal(beginning.currentStreak, 2)
        Check.equal(beginning.streakDetail, "Practice today to keep it")
        Check.equal(beginning.trendDetail, "20 min in the last four weeks, your first. Keep going, and your trend will show here.")
        let resting = PracticeInsights(PracticeHistory([dayRecord(80, 600)]), today: today, firstWeekday: monday)
        Check.equal(resting.trend, .resting)
        Check.equal(resting.currentStreak, 0)
        Check.equal(resting.streakDetail, "Best: 1 day")
        let lapsed = PracticeInsights(PracticeHistory([dayRecord(2, 600), dayRecord(3, 600)]), today: today, firstWeekday: monday)
        Check.equal(lapsed.currentStreak, 0)
    }

    func testWeeklySessionAverage() {
        let freestyle = PracticeRecord(id: "freestyle", start: time("2026-11-18T20:00:00+05:30"),
                                       seconds: 1800, cycles: 1, planned: 1, timing: .freestyle, steps: nil, device: "web")!
        let history = PracticeHistory([
            dayRecord(0, 600), freestyle, dayRecord(6, 3000), // three sessions on two days
            dayRecord(7, 9000), dayRecord(-1, 9000) // just outside either boundary
        ])
        let insights = PracticeInsights(history, today: today, firstWeekday: monday)
        Check.equal(insights.last7Practices, 3)
        Check.equal(insights.last7, 5400)
        Check.equal(insights.averageSessionSeconds, 1800)
        let endedEarly = record("partial", "2026-11-17T06:00:00+05:30", 600, cycles: 0, planned: 3)
        let withPartial = PracticeInsights(PracticeHistory(history.records + [endedEarly]), today: today, firstWeekday: 0)
        Check.equal(withPartial.last7Practices, 4)
        Check.equal(withPartial.averageSessionSeconds, 1500)
        let old = PracticeInsights(PracticeHistory([dayRecord(7, 600)]), today: today, firstWeekday: monday)
        Check.isNil(old.averageSessionSeconds)
        let zero = PracticeInsights(PracticeHistory([dayRecord(0, 0)]), today: today, firstWeekday: monday)
        Check.equal(zero.averageSessionSeconds, 0)
        let rounded = PracticeInsights(PracticeHistory([dayRecord(0, 60), dayRecord(1, 61)]), today: today, firstWeekday: monday)
        Check.equal(rounded.averageSessionSeconds, 61)
    }

    func testMergingAnotherDevicesPractices() throws {
        let incoming = try PracticeHistory.read(fixture()).history.records
        var local = PracticeHistory([record("a01", "2026-11-18T04:12:00+05:30", 600, cycles: 2, planned: 3),
                                     record("local-1", "2026-11-14T06:00:00Z", 1200, cycles: 4)])
        Check.equal(local.merge(incoming), .init(added: 18, updated: 1, unchanged: 0))
        Check.equal(local.records.count, 20)
        Check.equal(local.records.first { $0.id == "a01" }?.seconds, 900)
        Check.equal(local.merge(incoming), .init(added: 0, updated: 0, unchanged: 19))
        local.upsert(record("a01", "2026-11-18T04:12:00+05:30", 300))
        Check.equal(local.records.count, 20)
        Check.equal(local.records.first { $0.id == "a01" }?.seconds, 300)
        let india = record("i", "2026-11-18T06:00:00+05:30", 600)
        let utc = record("u", "2026-11-18T01:00:00Z", 600)
        Check.equal(PracticeHistory([utc, india]).records.map(\.id), ["i", "u"])
        Check.equal(PracticeHistory.Merge(added: 18, updated: 1, unchanged: 0).summary(of: "b.json", skipped: 12),
                    "Added 18 practices from “b.json”. Brought 1 practice up to date. 12 couldn't be read and were left out.")
        Check.equal(PracticeHistory.Merge(added: 0, updated: 0, unchanged: 19).summary(of: "b.json", skipped: 0),
                    "Everything in “b.json” was already here.")
        Check.equal(PracticeHistory.Merge(added: 0, updated: 1, unchanged: 1).summary(of: "b.json", skipped: 1),
                    "Brought 1 practice up to date from “b.json”. 1 was already here. 1 couldn't be read and was left out.")
        Check.equal(PracticeHistory.backupName(on: today), "Swadarshan Chakra backup 2026-11-18.json")
    }

    func testManuallyAddedPractices() throws {
        let fixture = Self.fixtureURL.deletingLastPathComponent().appendingPathComponent("history-manual-v1.json")
        let (history, skipped) = try PracticeHistory.read(Data(contentsOf: fixture))
        Check.equal(skipped, 3)
        Check.equal(history.records.map(\.id), ["manual-old", "manual-new"])
        let start = time("2026-11-18T06:00:00+05:30")
        let manual = PracticeRecord.manuallyAdded(id: "manual-new", start: start, seconds: 600, cycles: 3)!
        Check.equal(history.records.last, manual)
        Check.isTrue(manual.completed && manual.manual)
        Check.isNil(manual.steps)
        Check.isNil(manual.device)
        Check.equal(manual.averageSecondsPerStep, 40)
        Check.equal(manual.json, "{\"id\":\"manual-new\",\"start\":\"2026-11-18T06:00:00+05:30\",\"seconds\":600,\"cycles\":3,\"planned\":3,\"timing\":\"freestyle\",\"manual\":true}")
        let regular = record("regular", start.text, 1200)
        Check.isNil(regular.averageSecondsPerStep)
        Check.isTrue(!regular.json.contains("manual"))
        let insights = PracticeInsights(PracticeHistory(history.records + [regular]), today: today, firstWeekday: monday)
        Check.equal(insights.last7Practices, 2)
        Check.equal(insights.averageSessionSeconds, 900)
        Check.equal(insights.todayTotals.cycles, 4)
        Check.equal(try PracticeHistory.read(history.document()).history, history)
        var merged = history
        Check.equal(merged.merge(history.records).unchanged, 2)
        Check.equal(merged.records.count, 2)
        for (seconds, cycles) in [(0, 3), (-1, 3), (86401, 3), (600, 0), (600, 109)] {
            Check.isNil(PracticeRecord.manuallyAdded(id: "bad", start: start, seconds: seconds, cycles: cycles))
        }
        Check.equal(PracticeRecord.manuallyAdded(id: "tiny", start: start, seconds: 1, cycles: 1)?.averageSecondsPerStep, 0.2)
        Check.equal(PracticeRecord.manuallyAdded(id: "maximum", start: start, seconds: 86400, cycles: 108)?.seconds, 86400)
    }

    func testWritingAndReadingABackup() throws {
        let history = try PracticeHistory.read(fixture()).history
        let text = String(decoding: history.document(exported: time("2026-11-18T20:05:00+05:30")), as: UTF8.self)
        let lines = text.components(separatedBy: "\n")
        Check.equal(Array(lines.prefix(6)), ["{", "  \"format\": \"swadarshan-chakra-history\",", "  \"version\": 1,",
                                             "  \"app\": \"Swadarshan Chakra\",", "  \"exported\": \"2026-11-18T20:05:00+05:30\",",
                                             "  \"practices\": ["])
        Check.equal(lines[6], "    {\"id\":\"a20\",\"start\":\"2025-11-01T06:00:00+05:30\",\"seconds\":600,\"cycles\":2,\"planned\":2,\"timing\":\"perStep\",\"steps\":[120,120,120,120,120],\"device\":\"mac\"},")
        let back = try PracticeHistory.read(Data(text.utf8))
        Check.equal(back.skipped, 0)
        Check.equal(back.history, history)
        Check.equal(String(decoding: PracticeHistory().document(), as: UTF8.self),
                    "{\n  \"format\": \"swadarshan-chakra-history\",\n  \"version\": 1,\n  \"app\": \"Swadarshan Chakra\",\n  \"practices\": []\n}\n")
        // An id or device with quotes or slashes still reads back exactly.
        let odd = PracticeRecord(id: "a \"quoted\" / id", start: time("2026-11-18T06:00:00Z"), seconds: 60, cycles: 0,
                                 planned: 1, timing: .freestyle, steps: nil, device: "mac/2")!
        Check.equal(try PracticeHistory.read(PracticeHistory([odd]).document()).history.records, [odd])
    }

    func testFilesThatArentBackups() {
        func error(_ text: String) -> PracticeHistory.ReadError? {
            do { _ = try PracticeHistory.read(Data(text.utf8)); return nil } catch { return error as? PracticeHistory.ReadError }
        }
        Check.equal(error("not json"), .unreadable)
        Check.equal(error("[]"), .unreadable)
        Check.equal(error("{\"format\": \"something-else\", \"version\": 1, \"practices\": []}"), .notABackup)
        Check.equal(error("{\"format\": \"swadarshan-chakra-history\", \"version\": 1}"), .notABackup)
        Check.equal(error("{\"format\": \"swadarshan-chakra-history\", \"version\": \"1\", \"practices\": []}"), .notABackup)
        Check.equal(error("{\"format\": \"swadarshan-chakra-history\", \"version\": 2, \"practices\": []}"), .newerVersion(2))
        Check.isNil(error("{\"format\": \"swadarshan-chakra-history\", \"version\": 1, \"practices\": []}"))
        Check.equal(PracticeHistory.ReadError.unreadable.message(for: "b.json"),
                    "“b.json” couldn't be read. Choose a backup saved by Swadarshan Chakra.")
        Check.equal(PracticeHistory.ReadError.notABackup.message(for: "b.json"), "“b.json” isn't a Swadarshan Chakra backup.")
        Check.equal(PracticeHistory.ReadError.newerVersion(2).message(for: "b.json"),
                    "“b.json” comes from a newer version of Swadarshan Chakra. Update this one to import it.")
    }

    func testPracticesFromTheEngine() throws {
        var engine = SessionEngine(introductionDuration: 0)
        engine.begin(try SessionConfiguration(cycles: 2, minutesPerStep: 0, secondsPerStep: 30), at: 0)
        for now in stride(from: 30.0, through: 300, by: 30) { engine.tick(at: now) }
        Check.equal(engine.phase, .complete)
        let start = time("2026-11-18T06:00:00+05:30")
        let finished = PracticeRecord(id: "x", start: start, engine: engine, device: "mac")!
        Check.equal([finished.seconds, finished.cycles, finished.planned], [300, 2, 2])
        Check.equal(finished.timing, .perStep)
        Check.equal(finished.steps, [60, 60, 60, 60, 60])
        Check.equal(finished.device, "mac")
        Check.equal(finished.start.text, "2026-11-18T06:00:00+05:30")
        Check.isTrue(finished.completed)
        var short = SessionEngine(introductionDuration: 0)
        short.begin(try SessionConfiguration(cycles: 3, minutesPerStep: 1), at: 0)
        short.tick(at: 20)
        Check.isFalse(PracticeRecord.isWorthKeeping(short))
        short.tick(at: 40)
        short.tick(at: 60)
        Check.isTrue(PracticeRecord.isWorthKeeping(short))
        Check.equal(PracticeRecord(id: "y", start: start, engine: short, device: "mac")?.cycles, 0)
        var quick = SessionEngine(introductionDuration: 0)
        quick.begin(try SessionConfiguration(cycles: 1, minutesPerStep: 0, secondsPerStep: 2), at: 0)
        for now in stride(from: 2.0, through: 10, by: 2) { quick.tick(at: now) }
        Check.equal(quick.phase, .complete)
        Check.isTrue(PracticeRecord.isWorthKeeping(quick))
    }

    func testWordsAndNumbers() {
        Check.equal([0, 29, 30, 89, 90, 3600, 3630, 7800].map(HistoryText.minutes),
                    ["0 min", "< 1 min", "1 min", "1 min", "2 min", "1 hr", "1 hr 1 min", "2 hr 10 min"])
        Check.equal([0, 20, 2700, 7800, 7200, 7500].map(HistoryText.compact), ["", "<1m", "45m", "2h10", "2h", "2h05"])
        Check.equal([HistoryText.time(hour: 0, minute: 5), HistoryText.time(hour: 12, minute: 0), HistoryText.time(hour: 19, minute: 40)],
                    ["12:05 am", "12:00 pm", "7:40 pm"])
        Check.equal([0, 3, 12, 15].map(HistoryText.hourMark), ["12a", "3a", "12p", "3p"])
        Check.equal([HistoryText.date(today), HistoryText.dayTitle(today), HistoryText.shortDate(20696)],
                    ["18 November 2026", "Wednesday, 18 November", "31 Aug"])
        Check.equal([HistoryText.count(1, "day"), HistoryText.count(2, "day")], ["1 day", "2 days"])
    }
}
