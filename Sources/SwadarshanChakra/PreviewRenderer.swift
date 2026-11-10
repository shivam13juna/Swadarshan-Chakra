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
                    ("compact-total-time", 1024, 640), ("total-time-too-short", 1024, 640)
                ]
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
                    try await Task.sleep(nanoseconds: 350_000_000)
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

    private static func makeModel(_ name: String) -> SessionModel {
        let setupScreens = ["ready", "compact-ready", "invalid", "long-duration", "zero-duration",
                            "total-time", "compact-total-time", "total-time-too-short"]
        let defaults = UserDefaults(suiteName: "com.swadarshan.chakra.previews")!
        if name.hasSuffix("cycle-intro") || name == "second-cycle-paused" {
            var engine = SessionEngine()
            engine.begin(try! SessionConfiguration(cycles: 3, minutesPerStep: 1), at: 0)
            if name != "cycle-intro" && name != "compact-cycle-intro" {
                for now in 1...6 { engine.nextStage(at: Double(now)) }   // Cycle 1, then the next card.
            }
            if name == "second-cycle-paused" {
                engine.nextStage(at: 7)
                engine.tick(at: 22)
                engine.pause(at: 22)
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
        return model
    }
}
