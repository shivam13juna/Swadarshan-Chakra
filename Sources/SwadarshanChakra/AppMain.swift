import AppKit
import SwiftUI
import MeditationCore

@main
enum SwadarshanChakraApp {
    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { application.run() }
    }
}

final class MeditationWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private var window: MeditationWindow?
    private var model: SessionModel!
    private var artwork: ArtworkLibrary!
    private var keyboardMonitor: Any?
    private enum FullScreenTransition { case entering, exiting }
    private var fullScreenTransition: FullScreenTransition?
    private var wantsMeditationVisible = false
    /// Set when the window opens with "Open in full screen" ticked, and cleared once that entry
    /// starts. Leaving full screen later (green button, ⌃⌘F) is never undone by a focus change.
    private var fullScreenOnOpen = false
    private var quitting = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        do { artwork = try ArtworkLibrary() }
        catch {
            let alert = NSAlert(error: error)
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        // Bundled launches use the composed AppIcon.icns for Finder and the Dock.
        // Give unbundled SwiftPM runs an icon without overriding the packaged one.
        if Bundle.main.bundleURL.pathExtension != "app" {
            NSApp.applicationIconImage = artwork.brandIcon
        }
        if CommandLine.arguments.contains("--verify-resources") {
            for stage in Stage.all {
                print("\(stage.assetID): \(stage.fileName) → \(stage.label)")
            }
            print("All five supplied pictures decoded successfully from \(ArtworkLibrary.resourceBundle.bundlePath)")
            print("Supplied icon.png loaded for the header, dialogs, and menu bar.")
            NSApp.terminate(nil)
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--render-previews"),
           CommandLine.arguments.indices.contains(index + 1) {
            PreviewRenderer.render(artwork: artwork, directory: CommandLine.arguments[index + 1])
            return
        }
        if CommandLine.arguments.contains("--verify-timer") {
            Task { @MainActor in
                do {
                    try await verifyLiveTimer()
                    print("Live timer verification passed.")
                    NSApp.terminate(nil)
                } catch {
                    fputs("Live timer verification failed: \(error.localizedDescription)\n", stderr)
                    exit(1)
                }
            }
            return
        }
        let smokeTest = CommandLine.arguments.contains("--smoke-test")
        model = SessionModel(defaults: smokeTest ? UserDefaults(suiteName: "com.swadarshan.chakra.smoke")! : .standard)
        // One meditation window; keep tab-bar items out of the View menu.
        NSWindow.allowsAutomaticWindowTabbing = false
        model.hideWindow = { [weak self] in self?.hideMeditation() }
        model.quitApplication = { [weak self] in self?.quitting = true; NSApp.terminate(nil) }
        configureStatusItem()
        configureApplicationMenu()
        observeLifecycle()
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let consumed = MainActor.assumeIsolated {
                guard let self else { return false }
                return self.handleKey(event) == nil
            }
            return consumed ? nil : event
        }
        if !CommandLine.arguments.contains("--menu-bar-only") { showMeditation() }
        if smokeTest { runSmokeTest() }
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }
        let icon = artwork.brandIcon.copy() as! NSImage
        icon.size = NSSize(width: 20, height: 20)
        icon.isTemplate = false
        button.image = icon
        button.imageScaling = .scaleProportionallyDown
        button.toolTip = "Swadarshan Chakra · Open meditation"
        button.setAccessibilityLabel("Open Swadarshan Chakra meditation")
        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func configureApplicationMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Open Meditation", action: #selector(showMeditation), keyEquivalent: "o").target = self
        appMenu.addItem(withTitle: "Hide Meditation", action: #selector(hideMeditation), keyEquivalent: "w").target = self
        appMenu.addItem(withTitle: "Hide Swadarshan Chakra", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h").target = NSApp
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Swadarshan Chakra", action: #selector(requestQuit), keyEquivalent: "q").target = self
        appItem.submenu = appMenu
        main.addItem(appItem)

        // Keep native text editing and the standard shortcuts available in setup fields.
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        // The standard full-screen toggle. AppKit retitles it "Exit Full Screen" while in full screen.
        let viewItem = NSMenuItem()
        let view = NSMenu(title: "View")
        view.addItem(withTitle: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
            .keyEquivalentModifierMask = [.control, .command]
        viewItem.submenu = view
        main.addItem(viewItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.mainMenu = main
        NSApp.windowsMenu = windowMenu
    }

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: "Open Meditation", action: #selector(showMeditation), keyEquivalent: "").target = self
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quit Swadarshan Chakra", action: #selector(requestQuit), keyEquivalent: "q").target = self
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            showMeditation()
        }
    }

    @objc func showMeditation() {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else { return }
        // Opening (rather than bringing forward a window already in use) applies the setting.
        let opening = !wantsMeditationVisible
        if opening { fullScreenOnOpen = model.opensInFullScreen }
        wantsMeditationVisible = true
        // Own activation and the full-screen Space while a window is open, just like
        // a normal Mac app. Return to a menu-bar-only utility after closing it.
        if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }
        let window: MeditationWindow
        if let existing = self.window {
            window = existing
        } else {
            // The standard window buttons stay available, as in any Mac app: the green one enters or
            // leaves full screen. Content runs under the transparent title bar; see topInset(for:).
            window = MeditationWindow(contentRect: screen.visibleFrame,
                                      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                      backing: .buffered, defer: false)
            window.title = "Swadarshan Chakra"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            window.isReleasedWhenClosed = false
            window.tabbingMode = .disallowed
            window.backgroundColor = NSColor(calibratedRed: 0.025, green: 0.04, blue: 0.09, alpha: 1)
            window.collectionBehavior = [.fullScreenPrimary, .fullScreenDisallowsTiling]
            // The smallest layout the screens are designed and checked for.
            window.contentMinSize = NSSize(width: 1024, height: 640)
            window.delegate = self
            self.window = window
        }
        // AppKit owns the frame while entering or occupying its native full-screen Space. Full screen
        // opens on the display under the pointer; an ordinary window keeps the size and place it was given.
        if fullScreenOnOpen && fullScreenTransition == nil && !window.styleMask.contains(.fullScreen) {
            window.setFrame(screen.visibleFrame, display: true)
        }
        updateWindowContent()
        if NSApp.isHidden { NSApp.unhide(nil) }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        model.windowVisible = true
        // Remove text-field focus so Return can begin, while Tab still reaches every setup control.
        window.makeFirstResponder(window.contentView)
        // Finish activation before requesting the asynchronous Space transition.
        DispatchQueue.main.async { [weak self] in self?.enterFullScreenIfNeeded() }
    }

    @objc func hideMeditation() {
        wantsMeditationVisible = false
        model?.windowVisible = false
        fullScreenOnOpen = false
        model?.pause(reason: "Paused when the window was closed.")
        guard let window, fullScreenTransition == nil else { return }
        if window.styleMask.contains(.fullScreen) {
            fullScreenTransition = .exiting
            window.toggleFullScreen(nil)
        } else {
            window.orderOut(nil)
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private func updateWindowContent() {
        guard let window else { return }
        let root = MeditationView(model: model, artwork: artwork, topInset: topInset(for: window))
        if let host = window.contentView as? NSHostingView<MeditationView> {
            host.rootView = root
        } else {
            window.contentView = NSHostingView(rootView: root)
        }
    }

    /// The top space controls keep clear: the camera housing in full screen, or the title bar
    /// with its window buttons in an ordinary window. The artwork itself still fills the window.
    private func topInset(for window: NSWindow) -> CGFloat {
        if window.styleMask.contains(.fullScreen) { return window.screen?.safeAreaInsets.top ?? 0 }
        return max(0, window.frame.height - window.contentLayoutRect.height)
    }

    private func enterFullScreenIfNeeded() {
        guard fullScreenOnOpen, wantsMeditationVisible, fullScreenTransition == nil, let window,
              window.isKeyWindow, !window.styleMask.contains(.fullScreen) else { return }
        fullScreenOnOpen = false
        fullScreenTransition = .entering
        window.toggleFullScreen(nil)
    }

    func window(_ window: NSWindow, willUseFullScreenPresentationOptions proposedOptions: NSApplication.PresentationOptions) -> NSApplication.PresentationOptions {
        // Let AppKit manage menu bar/Dock visibility for the full-screen Space. Do not
        // overwrite presentationOptions on focus changes, which can reveal Finder's menu.
        var options = proposedOptions.subtracting([.hideMenuBar, .hideDock])
        options.formUnion([.fullScreen, .autoHideMenuBar, .autoHideDock])
        return options
    }

    func windowWillEnterFullScreen(_ notification: Notification) {
        fullScreenTransition = .entering
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        fullScreenTransition = nil
        updateWindowContent()
        if !wantsMeditationVisible { hideMeditation() }
    }

    func windowWillExitFullScreen(_ notification: Notification) {
        // Closing exits through hideMeditation, which has already let the window go. Any other exit
        // (the green button, View ▸ Exit Full Screen, ⌃⌘F) keeps practicing in an ordinary window.
        fullScreenTransition = .exiting
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        fullScreenTransition = nil
        // Also honors a reopen requested while a close was already leaving full screen.
        if wantsMeditationVisible { showMeditation() }
        else {
            window?.orderOut(nil)
            NSApp.setActivationPolicy(.accessory)
        }
    }

    func windowDidFailToEnterFullScreen(_ window: NSWindow) {
        // Stay in an ordinary window rather than retrying.
        fullScreenTransition = nil
        updateWindowContent()
    }

    func windowDidFailToExitFullScreen(_ window: NSWindow) {
        fullScreenTransition = nil
        if !wantsMeditationVisible {
            window.orderOut(nil)
            NSApp.setActivationPolicy(.accessory)
        }
    }

    @objc private func requestQuit() {
        if model.engine.phase == .running || model.engine.phase == .paused {
            showMeditation()
            model.request(.quit)
        } else if model.engine.phase != .confirming {
            quitting = true
            NSApp.terminate(nil)
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if quitting || model == nil { return .terminateNow }
        if model.engine.phase == .running || model.engine.phase == .paused {
            requestQuit()
            return .terminateCancel
        }
        return model.engine.phase == .confirming ? .terminateCancel : .terminateNow
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMeditation()
        return true
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { hideMeditation(); return false }
    /// Covered completely, minimized, or on another Space: nothing on screen needs to move.
    func windowDidChangeOcclusionState(_ notification: Notification) {
        model?.windowVisible = wantsMeditationVisible && window?.occlusionState.contains(.visible) == true
    }
    func windowDidBecomeKey(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in self?.enterFullScreenIfNeeded() }
    }
    func windowDidResignKey(_ notification: Notification) {
        logSmokeLifecycle("Window resigned key")
        pauseForAbsence()
    }
    func applicationDidResignActive(_ notification: Notification) {
        logSmokeLifecycle("Application resigned active")
        pauseForAbsence()
    }
    func applicationDidHide(_ notification: Notification) { pauseForAbsence() }
    func applicationDidBecomeActive(_ notification: Notification) {
        if wantsMeditationVisible && window?.isVisible == true { window?.makeKeyAndOrderFront(nil) }
        DispatchQueue.main.async { [weak self] in self?.enterFullScreenIfNeeded() }
    }

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        guard let window, window.isKeyWindow else { return event }
        return routeKey(event, textEditing: window.firstResponder is NSTextView)
    }

    private func routeKey(_ event: NSEvent, textEditing: Bool = false) -> NSEvent? {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option])
        if event.keyCode == 53 && modifiers.isEmpty {
            if !event.isARepeat { model.escape() }
            return nil
        }
        if event.keyCode == 49 && modifiers.isEmpty {
            if model.engine.phase == .running {
                model.nextStage(eventTime: event.timestamp, isRepeat: event.isARepeat)
                return nil
            }
            // Space in a setup text field is just input; elsewhere it must not activate a
            // focused Resume/Restart/Begin button as an unexpected side effect.
            if model.engine.phase == .ready && textEditing { return event }
            return nil
        }
        return event
    }

    private func observeLifecycle() {
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            workspace.addObserver(self, selector: #selector(pauseForAbsence), name: name, object: nil)
        }
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(pauseForAbsence),
            name: Notification.Name("com.apple.screenIsLocked"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    @objc private func pauseForAbsence() {
        model?.pause(reason: "Paused while you were away.", away: true)
    }

    private func logSmokeLifecycle(_ event: String) {
        guard CommandLine.arguments.contains("--smoke-test") else { return }
        print("LIFECYCLE \(event)")
        fflush(stdout)
    }

    @objc private func screensChanged() {
        guard let window, window.isVisible else { return }
        pauseForAbsence()
        // Keep an ordinary window's chosen size; only bring it back if its display went away.
        if fullScreenTransition == nil && !window.styleMask.contains(.fullScreen) && window.screen == nil,
           let screen = NSScreen.main {
            window.setFrame(screen.visibleFrame, display: true)
        }
        updateWindowContent()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let keyboardMonitor { NSEvent.removeMonitor(keyboardMonitor) }
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }

    /// Native integration checks without Accessibility permissions. The long timer probe uses a
    /// separate model so the user can switch apps while it runs; actual focus safeguards stay on.
    private func verifyLiveTimer() async throws {
        let suiteName = "com.swadarshan.chakra.timer-check"
        let probe = SessionModel(defaults: UserDefaults(suiteName: suiteName)!)
        // The probe's screens, in a window of their own off screen, so the step bar runs live as well.
        let screens = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 1024, height: 640),
                               styleMask: .borderless, backing: .buffered, defer: false)
        screens.isReleasedWhenClosed = false
        screens.contentView = NSHostingView(rootView: MeditationView(model: probe, artwork: artwork))
        screens.orderFront(nil)
        probe.windowVisible = true
        defer {
            probe.pause()
            screens.close()
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }
        func failure(_ code: Int, _ message: String) -> NSError {
            NSError(domain: "TimerCheck", code: code, userInfo: [NSLocalizedDescriptionKey: message])
        }
        /// Polls while the main run loop keeps delivering the live timer; returns the seconds waited.
        func wait(upTo limit: TimeInterval, until condition: () -> Bool) async throws -> TimeInterval {
            let start = SessionModel.now
            while !condition() {
                if SessionModel.now - start > limit { break }
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            return SessionModel.now - start
        }
        probe.cyclesText = "1"
        probe.minutesText = "0"
        probe.secondsText = "12"
        probe.begin()
        guard probe.engine.isIntroducingCycle && probe.engine.currentCycle == 1 else {
            throw failure(1, "Practice did not open with the Cycle 1 card")
        }
        print("PASS Practice opens with the Cycle 1 card")
        let card = try await wait(upTo: 5) { !probe.engine.isIntroducingCycle }
        guard card >= 2.9 && card < 3.6, probe.engine.phase == .running, probe.engine.stageIndex == 0,
              probe.engine.remainingSeconds > 11.7 else {
            throw failure(2, "The cycle card did not last three seconds before a full first step (\(card) s)")
        }
        print("PASS The cycle card lasts three seconds, then the first step starts with its full time")
        let step = try await wait(upTo: 14) { probe.engine.stageIndex != 0 }
        guard step >= 11.7 && step < 12.6, probe.engine.phase == .running, probe.engine.stageIndex == 1,
              probe.engine.completedCycles == 0 else {
            throw failure(3, "Live timer did not advance exactly one stage after 12 seconds (\(step) s)")
        }
        print("PASS Live timer advances exactly one stage after 12 seconds")
        guard probe.engine.remainingSeconds > 11.5 && probe.engine.remainingSeconds <= 12 else {
            throw failure(4, "Automatic advance did not start a fresh full countdown")
        }
        print("PASS Automatic advance starts a fresh full countdown")

        func stepMeter(in view: NSView) -> StepMeterView? {
            if let found = view as? StepMeterView { return found }
            for subview in view.subviews { if let found = stepMeter(in: subview) { return found } }
            return nil
        }
        guard let host = screens.contentView, let meter = stepMeter(in: host) else {
            throw failure(5, "The step screen has no bar along its bottom edge")
        }
        let firstTime = SessionModel.now, first = meter.shownFraction
        try await Task.sleep(nanoseconds: 1_000_000_000)
        let laterTime = SessionModel.now, later = meter.shownFraction
        // Per second, the bar should lose one step's worth of its length divided by the step's seconds.
        let rate = (first - later) / (laterTime - firstTime) * probe.engine.configuration.secondsPerStage
        guard first > 0.95, abs(rate - 1) < 0.05, abs(later - (1 - probe.engine.progress)) < 0.03 else {
            throw failure(5, "The step bar did not empty with the live timer (from \(first) to \(later), rate \(rate))")
        }
        probe.pause()
        try await Task.sleep(nanoseconds: 300_000_000)
        let held = meter.shownFraction
        try await Task.sleep(nanoseconds: 500_000_000)
        guard held == meter.shownFraction, abs(held - (1 - probe.engine.progress)) < 0.001 else {
            throw failure(6, "The step bar did not hold still while paused")
        }
        print("PASS The step bar empties with the live timer and holds still while paused")
    }

    private func runSmokeTest() {
        Task { @MainActor in
            func require(_ condition: Bool, _ name: String) throws {
                if !condition { throw NSError(domain: "SmokeTest", code: 1, userInfo: [NSLocalizedDescriptionKey: name]) }
                print("PASS \(name)")
                fflush(stdout)
            }
            func settle(_ milliseconds: UInt64 = 150) async throws {
                try await Task.sleep(nanoseconds: milliseconds * 1_000_000)
            }
            @MainActor func awaitFullScreen() async throws {
                for _ in 0..<60 {
                    if window?.isKeyWindow == true, window?.styleMask.contains(.fullScreen) == true,
                       fullScreenTransition == nil { return }
                    try await settle(100)
                }
                throw NSError(domain: "SmokeTest", code: 2, userInfo: [NSLocalizedDescriptionKey:
                    "Native full-screen entry timed out (active=\(NSApp.isActive), key=\(window?.isKeyWindow == true), fullScreen=\(window?.styleMask.contains(.fullScreen) == true))"])
            }
            @MainActor func awaitWindowed() async throws {
                for _ in 0..<60 {
                    if window?.isVisible == true, window?.styleMask.contains(.fullScreen) == false,
                       fullScreenTransition == nil { return }
                    try await settle(100)
                }
                throw NSError(domain: "SmokeTest", code: 4, userInfo: [NSLocalizedDescriptionKey: "Leaving full screen timed out"])
            }
            @MainActor func awaitHidden() async throws {
                for _ in 0..<60 {
                    if window?.isVisible == false && fullScreenTransition == nil { return }
                    try await settle(100)
                }
                throw NSError(domain: "SmokeTest", code: 3, userInfo: [NSLocalizedDescriptionKey: "Native full-screen close timed out"])
            }
            @MainActor func key(_ code: UInt16, _ characters: String, repeatKey: Bool = false, modifiers: NSEvent.ModifierFlags = [], posted: Bool = false) {
                guard let window = self.window,
                      let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                          timestamp: SessionModel.now, windowNumber: window.windowNumber, context: nil,
                          characters: characters, charactersIgnoringModifiers: characters, isARepeat: repeatKey, keyCode: code) else { return }
                if posted { NSApp.postEvent(event, atStart: false) }
                else { _ = routeKey(event) }
            }
            do {
                try await awaitFullScreen()
                try await settle(400)
                print("Full-screen state: active=\(NSApp.isActive), appOptions=\(NSApp.presentationOptions.rawValue), systemOptions=\(NSApp.currentSystemPresentationOptions.rawValue), menuVisible=\(NSMenu.menuBarVisible())")
                try require(window?.isKeyWindow == true, "Full-screen window becomes key")
                try require(window?.styleMask.contains(.fullScreen) == true && NSApp.currentSystemPresentationOptions.contains(.fullScreen),
                            "Window enters native macOS full-screen mode")
                // In native full screen, currentSystemPresentationOptions reports .fullScreen
                // without the auto-hide bits. Check the menu's actual visibility instead.
                try require(!NSMenu.menuBarVisible(), "macOS menu bar is hidden in the full-screen Space")
                try require(NSApp.presentationOptions.contains(.autoHideDock), "Full-screen presentation auto-hides the Dock")
                if let window, let screen = window.screen {
                    try require(window.frame.width == screen.frame.width && window.frame.height >= screen.visibleFrame.height,
                                "Full-screen window fills the display's usable area")
                }
                try require(window?.standardWindowButton(.zoomButton)?.isHidden == false,
                            "The window keeps its standard full-screen button")
                // The green button, View ▸ Exit Full Screen, and ⌃⌘F all send toggleFullScreen.
                window?.toggleFullScreen(nil)
                try await awaitWindowed()
                try require(wantsMeditationVisible && window?.isKeyWindow == true,
                            "Leaving full screen keeps meditation open in an ordinary window")
                window?.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                try await settle(800)
                try require(window?.styleMask.contains(.fullScreen) == false,
                            "Focus changes do not force full screen back")
                window?.toggleFullScreen(nil)
                try await awaitFullScreen()
                model.opensInFullScreen = false
                hideMeditation()
                try await awaitHidden()
                showMeditation()
                try await awaitWindowed()
                try await settle(800)
                try require(window?.styleMask.contains(.fullScreen) == false,
                            "With Open in full screen unticked, meditation opens in a window")
                model.opensInFullScreen = true
                hideMeditation()
                try await awaitHidden()
                showMeditation()
                try await awaitFullScreen()
                try require(window?.styleMask.contains(.fullScreen) == true,
                            "With Open in full screen ticked, meditation opens in full screen")
                try await settle(400)
                key(49, " ", posted: true)
                try await settle()
                try require(model.engine.phase == .ready, "Space does not start setup")
                model.cyclesText = "0"
                model.begin()
                try require(model.engine.phase == .ready, "Invalid setup cannot begin")
                model.cyclesText = "1"
                model.minutesText = "0"
                model.secondsText = "00"
                model.begin()
                try require(model.engine.phase == .ready && !model.durationValid, "A zero-length step cannot begin")
                model.secondsText = "60"
                model.begin()
                try require(model.engine.phase == .ready && !model.secondsValid, "Seconds outside 0–59 are rejected")
                model.minutesText = "1"
                model.secondsText = "00"
                key(36, "\r", posted: true)
                try await settle()
                try require(model.engine.phase == .running, "Return activates Begin")
                try require(model.engine.isIntroducingCycle && model.engine.currentCycle == 1,
                            "Practice opens with the Cycle 1 card")
                try require(model.engine.configuration.secondsPerStage == 60 && model.engine.configuration.plannedSeconds == 300,
                            "One minute per step produces a five-minute cycle")
                model.pause()
                model.practiceAgain()
                model.cyclesText = "3"
                model.setTimingMode(.total)
                try require(model.minutesText == "15" && model.secondsText == "00",
                            "Switching to total time keeps the same practice")
                model.minutesText = "10"
                model.begin()
                try require(model.engine.configuration.secondsPerStage == 40 && model.engine.configuration.plannedSeconds == 600,
                            "Ten minutes for three cycles gives each step 40 seconds")
                model.pause()
                model.practiceAgain()
                model.setTimingMode(.perStep)
                try require(model.minutesText == "0" && model.secondsText == "40", "Switching back shows 40 seconds per step")
                model.minutesText = "1"
                model.secondsText = "00"
                model.cyclesText = "2"
                model.begin()
                key(49, " ")
                try await settle()
                try require(!model.engine.isIntroducingCycle && model.engine.stageIndex == 0 && model.engine.remainingSeconds == 60,
                            "Space on the cycle card begins the first step with its full time")
                key(49, " ")
                try await settle()
                try require(model.engine.stageIndex == 1, "Native Space handler advances one stage")
                for _ in 0..<4 { key(49, " ", repeatKey: true) }
                try await settle()
                try require(model.engine.stageIndex == 1, "Native key repeats are consumed")
                key(53, "\u{1b}")
                try await settle()
                try require(model.engine.phase == .paused, "Escape pauses")
                let remaining = model.engine.remainingSeconds
                key(49, " ")
                try await settle()
                try require(model.engine.phase == .paused && model.engine.stageIndex == 1,
                            "Space stays inactive while paused")
                hideMeditation()
                try await awaitHidden()
                try require(window?.isVisible == false, "Close hides the window")
                try require(NSApp.activationPolicy() == .accessory, "Closing restores the menu-bar-only utility")
                statusItem.button?.performClick(nil)
                try await awaitFullScreen()
                try require(window?.isVisible == true && model.engine.phase == .paused,
                            "Menu bar reopens the paused session in native full screen")
                try require(model.engine.remainingSeconds == remaining, "Close and reopen preserve exact remaining time")
                model.resume()
                try require(model.engine.phase == .running, "Resume restores running state")
                NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
                try require(model.engine.phase == .paused, "Mac sleep notification pauses practice")
                model.resume()
                // Exercise the lock handler locally; never broadcast a fake lock to other apps.
                pauseForAbsence()
                try require(model.engine.phase == .paused, "Screen-lock handler pauses practice")
                model.resume()
                // Transfer real keyboard focus to another window in this app's Space.
                // Programmatic app deactivation cannot grant the subsequent activation
                // request a user gesture, so it isn't a reliable app-switch simulation.
                let focusProbe = MeditationWindow(contentRect: NSRect(x: 40, y: 40, width: 120, height: 60),
                                                  styleMask: .borderless, backing: .buffered, defer: false)
                focusProbe.isReleasedWhenClosed = false
                focusProbe.collectionBehavior = [.fullScreenAuxiliary]
                focusProbe.makeKeyAndOrderFront(nil)
                try await settle()
                try require(focusProbe.isKeyWindow && model.engine.phase == .paused,
                            "Losing the key window pauses practice")
                focusProbe.close()
                showMeditation()
                try await awaitFullScreen()
                model.request(.restart)
                try require(model.engine.phase == .confirming, "Restart asks before discarding progress")
                key(53, "\u{1b}")
                try await settle()
                try require(model.engine.phase == .paused && model.engine.stageIndex == 1,
                            "Escape cancels restart and preserves progress")
                model.request(.restart)
                try await settle()
                model.confirm()
                try require(model.engine.phase == .running && model.engine.stageIndex == 0 && model.engine.isIntroducingCycle,
                            "Confirmed restart returns to the Cycle 1 card")
                key(49, " ")
                try await settle(70)
                for index in 1...10 {
                    key(49, " ")
                    try await settle(70)
                    try require(model.engine.completedCycles == index / 5, "Manual step \(index) counts cycles correctly")
                    if index == 5 {
                        try require(model.engine.isIntroducingCycle && model.engine.currentCycle == 2,
                                    "Completing a cycle shows the Cycle 2 card")
                        key(49, " ")
                        try await settle(70)
                    }
                }
                try require(model.engine.phase == .complete, "Final Stage 5 completes the session")
                try require(model.engine.activeSeconds < model.engine.configuration.plannedSeconds,
                            "Completion reports shortened active practice time")
                key(49, " ")
                try await settle()
                try require(model.engine.phase == .complete, "Space stays inactive after completion")
                model.practiceAgain()
                try require(model.engine.phase == .ready, "Practice Again returns to setup")
                hideMeditation()
                showMeditation()
                try await awaitFullScreen()
                try require(model.engine.phase == .ready && window?.isVisible == true,
                            "Reopening during a full-screen exit restores the window")
                hideMeditation()
                try await awaitHidden()

                try await verifyLiveTimer()
                print("Native smoke test passed.")
                UserDefaults.standard.removePersistentDomain(forName: "com.swadarshan.chakra.smoke")
                quitting = true
                NSApp.terminate(nil)
            } catch {
                fputs("Native smoke test failed: \(error.localizedDescription)\n", stderr)
                UserDefaults.standard.removePersistentDomain(forName: "com.swadarshan.chakra.smoke")
                exit(1)
            }
        }
    }
}
