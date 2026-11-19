import AppKit
import SwiftUI
import MeditationCore

/// Native, reproducible layout captures. This mode never starts a timer or writes user preferences.
@MainActor
enum PreviewRenderer {
    static func render(artwork: ArtworkLibrary, directory: String) {
        Task { @MainActor in
            do {
                let output = URL(fileURLWithPath: directory, isDirectory: true)
                try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                let scenarios: [(String, CGFloat, CGFloat)] = [
                    ("ready", 1440, 900), ("running", 1440, 900), ("paused", 1280, 800),
                    ("complete", 1440, 900), ("confirming", 1280, 800),
                    ("compact-ready", 1024, 640), ("compact-running", 1024, 640),
                    ("invalid", 1024, 640), ("fourth-form", 1440, 900), ("compact-fourth-form", 1024, 640),
                    ("first-form", 1440, 900), ("third-form", 1440, 900), ("fifth-form", 1440, 900),
                    ("wide-second-form", 2560, 1080), ("portrait-fourth-form", 900, 1440),
                    ("long-duration", 1024, 640), ("zero-duration", 1024, 640),
                    ("cycle-intro", 1440, 900), ("next-cycle-intro", 1440, 900), ("compact-cycle-intro", 1024, 640),
                    ("second-cycle-paused", 1440, 900), ("total-time", 1440, 900),
                    ("compact-total-time", 1024, 640), ("total-time-too-short", 1024, 640),
                    ("freestyle", 1440, 900), ("compact-freestyle", 1024, 640), ("freestyle-running", 1440, 900),
                    ("freestyle-paused", 1024, 640), ("freestyle-complete", 1440, 900),
                    ("no-countdown-bar", 1440, 900), ("between-steps", 1440, 900), ("turning-hand", 1440, 900),
                    ("wide-between-steps", 2560, 1080), ("compact-between-steps", 1024, 640),
                    ("portrait-between-steps", 900, 1440), ("first-step-card", 1440, 900),
                    ("summary", 1440, 900), ("compact-summary", 1024, 640),
                    ("medium-summary", 1280, 800), ("wide-summary", 2560, 1440),
                    ("journey", 1440, 900), ("compact-journey", 1024, 640), ("wide-journey", 2560, 1440),
                    ("journey-empty", 1440, 900), ("ready-empty", 1440, 900)
                ]
                // The sample the captures show, as the app would export it: the web version imports it too.
                try sampleHistory.document(exported: PracticeTime(sampleNow))
                    .write(to: output.appendingPathComponent("sample-backup.json"))
                for (name, width, height) in scenarios {
                    let model = makeModel(name)
                    let root = MeditationView(model: model, artwork: artwork)
                    let host = NSHostingView(rootView: root)
                    let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: width, height: height),
                                          styleMask: .borderless, backing: .buffered, defer: false)
                    window.isReleasedWhenClosed = false
                    window.contentView = host
                    window.orderFront(nil)
                    host.layoutSubtreeIfNeeded()
                    // A card between steps is captured once its hand has turned, or, for "turning-hand",
                    // partway through the two-second turn from Sat Yuga to Dwapar Yuga.
                    let settle: UInt64 = name == "turning-hand" ? 1_200 : (Self.turns[name] == nil ? 350 : 2_600)
                    try await Task.sleep(nanoseconds: settle * 1_000_000)
                    guard host.bounds.size == NSSize(width: width, height: height) else {
                        throw NSError(domain: "Preview", code: 1, userInfo: [NSLocalizedDescriptionKey: "Layout exceeded the requested display size for \(name)"])
                    }
                    guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
                        throw CocoaError(.fileWriteUnknown)
                    }
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    guard let data = bitmap.representation(using: .png, properties: [:]) else {
                        throw CocoaError(.fileWriteUnknown)
                    }
                    let destination = output.appendingPathComponent("\(name).png")
                    try data.write(to: destination)
                    print("Rendered \(name): \(Int(width)) × \(Int(height)) → \(destination.path)")
                    window.close()
                }
                NSApp.terminate(nil)
            } catch {
                fputs("Preview rendering failed: \(error)\n", stderr)
                exit(1)
            }
        }
    }

    /// A finished practice of a minute per step whose steps took different times: most their full
    /// minute, some moved on early with Space, some paused 45 s longer with the practitioner there.
    private static func finishedPractice(cycles: Int) -> SessionEngine {
        var engine = SessionEngine(introductionDuration: 0)
        engine.begin(try! SessionConfiguration(cycles: cycles, minutesPerStep: 1), at: 0)
        var now = 0.0
        for step in 0..<(cycles * Stage.all.count) {
            switch step % 7 {
            case 2, 6:
                now += step % 7 == 2 ? 38 : 51
                engine.nextStage(at: now)
            case 4:
                engine.pause(at: now + 20)
                engine.resume(at: now + 65)
                now += 105
                engine.tick(at: now)
            default:
                now += 60
                engine.tick(at: now)
            }
        }
        return engine
    }

    /// The cards between steps, by the step each one turns the dial to.
    private static let turns = ["between-steps": 1, "turning-hand": 2, "wide-between-steps": 2,
                                "compact-between-steps": 3, "portrait-between-steps": 4]

    /// Midday on Wednesday, 18 November 2026, in UTC: the same day in nearly every time zone.
    private static let sampleNow = Date(timeIntervalSince1970: Double(20775 * 86400 + 12 * 3600))

    /// Fourteen weeks of a morning practice that grows more regular, longer practices at weekends, and
    /// some evenings; the afternoons stay free. The same every time.
    static let sampleHistory: PracticeHistory = {
        let today = 20775
        var seed: UInt64 = 108
        func random(_ range: Int) -> Int {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((seed >> 33) % UInt64(range))
        }
        var records: [PracticeRecord] = []
        func add(_ day: Int, hour: Int, cycles: Int, perStep: Int, device: String) {
            let date = CivilDate(dayNumber: day)
            let start = String(format: "%04d-%02d-%02dT%02d:%02d:%02d+05:30", date.year, date.month, date.day,
                               hour, random(60), random(60))
            records.append(PracticeRecord(id: "sample-\(records.count + 1)", start: PracticeTime(start)!,
                                          seconds: cycles * 5 * perStep, cycles: cycles, planned: cycles, timing: .perStep,
                                          steps: Array(repeating: cycles * perStep, count: 5), device: device)!)
        }
        for offset in stride(from: 97, through: 0, by: -1) {
            let day = today - offset
            let weekday = CivilDate.weekday(day)
            if offset < 12 || random(100) < 40 + (97 - offset) * 55 / 97 {
                add(day, hour: 4 + random(3), cycles: 2 + random(3), perStep: 60 * (2 + random(2)),
                    device: random(3) == 0 ? "web" : "mac")
            }
            if (weekday == 0 || weekday == 6) && random(100) < 55 {
                add(day, hour: 8 + random(2), cycles: 4 + random(5), perStep: 120, device: "mac")
            }
            if offset > 0 && random(100) < 18 {
                add(day, hour: 20 + random(2), cycles: 1 + random(2), perStep: 60, device: "web")
            }
        }
        return PracticeHistory(records)
    }()

    /// The journey captures show setup scrolled down to it.
    private static func makeModel(_ name: String) -> SessionModel {
        let model = makeSessionModel(name)
        if name.contains("journey") { model.showJourney() }
        return model
    }

    private static func makeSessionModel(_ name: String) -> SessionModel {
        let setupScreens = ["ready", "compact-ready", "invalid", "long-duration", "zero-duration",
                            "total-time", "compact-total-time", "total-time-too-short", "freestyle", "compact-freestyle",
                            "journey", "compact-journey", "wide-journey", "journey-empty", "ready-empty"]
        let defaults = UserDefaults(suiteName: "com.swadarshan.chakra.previews")!
        // Every capture shows the same history, on the same day, with weeks that begin on Monday.
        let history = name.hasSuffix("-empty") ? PracticeHistory() : sampleHistory
        func SessionModel(defaults: UserDefaults, automaticTicks: Bool, initialEngine: SessionEngine) -> SwadarshanChakra.SessionModel {
            .init(defaults: defaults, automaticTicks: automaticTicks, initialEngine: initialEngine,
                  store: .memory(history), clock: { sampleNow }, firstWeekday: 1)
        }
        if let stage = turns[name] {
            var engine = SessionEngine()
            engine.begin(try! SessionConfiguration(cycles: 3, minutesPerStep: 1), at: 0)
            // Space begins the step on each card, then moves on to the next step's card.
            for now in 1...(2 * stage) { engine.nextStage(at: Double(now)) }
            return SessionModel(defaults: defaults, automaticTicks: false, initialEngine: engine)
        }
        if name == "first-step-card" {
            var engine = SessionEngine()
            engine.begin(try! SessionConfiguration(cycles: 3, minutesPerStep: 1), at: 0)
            engine.tick(at: 3.5)   // The cycle card has given way to step 1's own card.
            return SessionModel(defaults: defaults, automaticTicks: false, initialEngine: engine)
        }
        if name.hasSuffix("summary") {
            return SessionModel(defaults: defaults, automaticTicks: false,
                                initialEngine: finishedPractice(cycles: name == "compact-summary" ? 30 : 3))
        }
        if name.hasPrefix("freestyle-") {
            // Freestyle steps, without the card that opens each cycle: no countdown, and no bar.
            var engine = SessionEngine(introductionDuration: 0)
            engine.begin(try! SessionConfiguration(freestyleCycles: name == "freestyle-complete" ? 1 : 3), at: 0)
            engine.nextStage(at: 95)
            if name == "freestyle-paused" { engine.pause(at: 200) }
            if name == "freestyle-complete" {
                for now in [260.0, 410, 530, 702] { engine.nextStage(at: now) }
            }
            return SessionModel(defaults: defaults, automaticTicks: false, initialEngine: engine)
        }
        if name.hasSuffix("cycle-intro") || name == "second-cycle-paused" {
            var engine = SessionEngine()
            engine.begin(try! SessionConfiguration(cycles: 3, minutesPerStep: 1), at: 0)
            if name != "cycle-intro" && name != "compact-cycle-intro" {
                // Cycle 1, each step begun from its card by Space, then the next cycle's card.
                for now in 1...10 { engine.nextStage(at: Double(now)) }
            }
            if name == "second-cycle-paused" {
                engine.nextStage(at: 11)
                engine.tick(at: 26)
                engine.pause(at: 26)
            }
            return SessionModel(defaults: defaults, automaticTicks: false, initialEngine: engine)
        }
        // The remaining screens show steps directly, without the card that opens each cycle.
        var engine = SessionEngine(introductionDuration: 0)
        let config = try! SessionConfiguration(cycles: name == "complete" ? 1 : 3, minutesPerStep: 1)
        if !setupScreens.contains(name) {
            engine.begin(config, at: 0)
            if name != "first-form" { engine.nextStage(at: 24) }
            engine.tick(at: 37)
            if name == "third-form" { engine.nextStage(at: 40) }
            if name.contains("fourth-form") {
                engine.nextStage(at: 40)
                engine.nextStage(at: 43)
            }
            if name == "fifth-form" {
                for now in [40.0, 43, 46] { engine.nextStage(at: now) }
            }
            if name == "paused" { engine.pause(at: 37) }
            if name == "confirming" { engine.requestConfirmation(.restart, at: 37) }
            if name == "complete" {
                for now in [70.0, 96, 132, 169] { engine.nextStage(at: now) }
            }
        }
        let model = SessionModel(defaults: defaults, automaticTicks: false, initialEngine: engine)
        if name == "invalid" { model.cyclesText = "0"; model.minutesText = "1.5" }
        if name == "long-duration" { model.cyclesText = "107"; model.minutesText = "119"; model.secondsText = "59" }
        if name == "zero-duration" { model.minutesText = "0"; model.secondsText = "00" }
        if name.contains("total-time") {
            model.cyclesText = name == "compact-total-time" ? "7" : (name == "total-time-too-short" ? "108" : "3")
            model.setTimingMode(.total)
            model.minutesText = name == "total-time-too-short" ? "5" : "10"
            model.secondsText = "00"
        }
        if name.hasSuffix("freestyle") {
            model.cyclesText = "3"
            model.setTimingMode(.freestyle)
        }
        if name == "no-countdown-bar" {
            model.showsCountdownBar = false
            defaults.removeObject(forKey: "showsCountdownBar")   // Only this capture goes without it.
        }
        return model
    }
}
