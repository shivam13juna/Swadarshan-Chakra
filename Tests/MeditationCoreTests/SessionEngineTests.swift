import Foundation
import MeditationCore

final class SessionEngineTests {
    private func configuration(_ cycles: Int = 1, _ minutes: Int = 1, _ seconds: Int = 0) -> SessionConfiguration {
        try! SessionConfiguration(cycles: cycles, minutesPerStep: minutes, secondsPerStep: seconds)
    }

    private func total(_ cycles: Int, _ minutes: Int, _ seconds: Int = 0) -> SessionConfiguration {
        try! SessionConfiguration(cycles: cycles, totalMinutes: minutes, totalSeconds: seconds)
    }

    /// Step timing in isolation, without the title card that opens each cycle.
    private func stageEngine() -> SessionEngine { SessionEngine(introductionDuration: 0) }

    func testPerStepDurationsAndAutomaticTotals() throws {
        for (cycles, minutes, seconds, stage, planned) in [
            (1, 1, 0, 60, 300), (3, 1, 0, 60, 900), (3, 2, 0, 120, 1800),
            (2, 1, 24, 84, 840), (1, 0, 12, 12, 60), (2, 7, 0, 420, 4200)
        ] {
            let config = try SessionConfiguration(cycles: cycles, minutesPerStep: minutes, secondsPerStep: seconds)
            Check.equal(config.secondsPerStage, Double(stage))
            Check.equal(config.secondsPerCycle, Double(stage * 5))
            Check.equal(config.plannedSeconds, Double(planned))
        }
    }

    func testValidationRejectsOutOfRangeAndNonWholeInputs() {
        for value in ["", " ", "0", "-1", "+1", "1.5", "1 2", "1\n", " 2", "109", "99999999999999999999999999"] {
            Check.isNil(SessionConfiguration.integer(value, in: SessionConfiguration.cycleRange), value)
        }
        for value in ["1", "5", "108"] {
            Check.notNil(SessionConfiguration.integer(value, in: SessionConfiguration.cycleRange))
        }
        Check.notNil(SessionConfiguration.integer("120", in: SessionConfiguration.minuteRange(for: .perStep)))
        Check.isNil(SessionConfiguration.integer("121", in: SessionConfiguration.minuteRange(for: .perStep)))
        Check.throwsError(try SessionConfiguration(cycles: 0, minutesPerStep: 1))
        Check.throwsError(try SessionConfiguration(cycles: 1, minutesPerStep: -1))
        Check.throwsError(try SessionConfiguration(cycles: 1, minutesPerStep: 0))
        Check.throwsError(try SessionConfiguration(cycles: 1, minutesPerStep: 120, secondsPerStep: 1))
        Check.throwsError(try SessionConfiguration(cycles: 1, minutesPerStep: 1, secondsPerStep: 60))
        Check.throwsError(try SessionConfiguration(cycles: 1, minutesPerStep: 1, secondsPerStep: -1))
        Check.equal(configuration(1, 0, 1).secondsPerStage, 1)
        Check.equal(configuration(108, 120).secondsPerStage, 7200)
    }

    func testAllAutomaticSessionsFinishAtPlannedActiveTime() {
        for config in [configuration(), configuration(3, 2), configuration(2, 1, 24), configuration(1, 0, 12)] {
            var engine = stageEngine()
            engine.begin(config, at: 0)
            for step in 1...(config.cycles * 5) {
                Check.isTrue(engine.tick(at: Double(step) * config.secondsPerStage))
                Check.equal(engine.completedCycles, step / 5)
                if step < config.cycles * 5 {
                    Check.equal(engine.stageIndex, step % 5)
                    Check.equal(engine.remainingSeconds, config.secondsPerStage)
                }
            }
            Check.equal(engine.phase, .complete)
            Check.equal(engine.activeSeconds, config.plannedSeconds)
            Check.equal(engine.completedCycles, config.cycles)
        }
    }

    func testSpaceDiscardsOnlyCurrentStageRemainder() {
        var engine = stageEngine()
        engine.begin(configuration(), at: 0)
        engine.tick(at: 20)
        Check.isTrue(engine.nextStage(at: 20))
        Check.equal(engine.stageIndex, 1)
        Check.equal(engine.remainingSeconds, 60)
        Check.equal(engine.activeSeconds, 20)
        Check.equal(engine.completedCycles, 0)
        engine.tick(at: 79)
        Check.equal(engine.remainingSeconds, 1)
        engine.tick(at: 80)
        Check.equal(engine.stageIndex, 2)
        Check.equal(engine.remainingSeconds, 60)
    }

    func testProgressIsTheShareOfTheStepPracticed() {
        var engine = stageEngine()
        engine.begin(configuration(), at: 0)
        Check.equal(engine.progress, 0)
        engine.tick(at: 15)
        Check.equal(engine.progress, 0.25)
        engine.pause(at: 30)
        Check.equal(engine.progress, 0.5)
        engine.resume(at: 100)
        engine.nextStage(at: 100)
        Check.equal(engine.progress, 0)
    }

    func testStageFiveCountsCycleAndFinalManualAdvanceCompletes() {
        var engine = stageEngine()
        engine.begin(configuration(3), at: 0)
        for step in 1...15 {
            engine.nextStage(at: Double(step))
            Check.equal(engine.completedCycles, step / 5)
            if step < 15 { Check.equal(engine.stageIndex, step % 5) }
        }
        Check.equal(engine.phase, .complete)
        Check.equal(engine.completedCycles, 3)
        Check.equal(engine.activeSeconds, 15)
    }

    func testKeyRepeatNeverAdvances() {
        var engine = stageEngine()
        engine.begin(configuration(), at: 0)
        engine.nextStage(at: 1)
        for now in stride(from: 1.1, to: 4, by: 0.1) {
            Check.isFalse(engine.nextStage(at: now, isRepeat: true))
        }
        Check.equal(engine.stageIndex, 1)
        Check.equal(engine.transitionCount, 1)
    }

    func testAutomaticThenSpaceAtSameBoundaryIsOneTransition() {
        for offset in [0.0, 0.01, 0.1, SessionEngine.boundaryTolerance] {
            var engine = stageEngine()
            engine.begin(configuration(), at: 0)
            engine.tick(at: 60)
            Check.isFalse(engine.nextStage(at: 60 + offset, eventTime: 60 + offset))
            Check.equal(engine.stageIndex, 1)
            Check.equal(engine.transitionCount, 1)
        }
    }

    func testSpaceThenTimerAtSameBoundaryIsOneTransition() {
        var engine = stageEngine()
        engine.begin(configuration(), at: 0)
        engine.nextStage(at: 59.999)
        engine.tick(at: 60)
        Check.equal(engine.stageIndex, 1)
        Check.equal(engine.transitionCount, 1)
        Check.equal(engine.remainingSeconds, 59.999, accuracy: 0.0001)
    }

    func testSpaceOnExpiredStageConsumesOnlyExpiration() {
        var engine = stageEngine()
        engine.begin(configuration(), at: 0)
        engine.nextStage(at: 60)
        Check.equal(engine.stageIndex, 1)
        Check.equal(engine.remainingSeconds, 60)
        Check.equal(engine.transitionCount, 1)
    }

    func testQueuedKeyFromPriorStageIsIgnored() {
        var engine = stageEngine()
        engine.begin(configuration(), at: 0)
        engine.tick(at: 60)
        Check.isFalse(engine.nextStage(at: 60.5, eventTime: 59.9))
        Check.equal(engine.stageIndex, 1)
        Check.isTrue(engine.nextStage(at: 60.7, eventTime: 60.7))
        Check.equal(engine.stageIndex, 2)
    }

    func testDistinctQuickPhysicalPressesStillWork() {
        var engine = stageEngine()
        engine.begin(configuration(), at: 0)
        engine.nextStage(at: 0.01)
        engine.nextStage(at: 0.02)
        Check.equal(engine.stageIndex, 2)
    }

    func testPauseKeepsTheStepTimeAndResumesExactly() {
        var engine = stageEngine()
        engine.begin(configuration(), at: 0)
        engine.pause(at: 23)
        Check.equal(engine.remainingSeconds, 37)
        engine.tick(at: 400)
        Check.isFalse(engine.nextStage(at: 400))
        Check.equal(engine.remainingSeconds, 37)
        engine.resume(at: 400)
        engine.tick(at: 410)
        Check.equal(engine.remainingSeconds, 27)
        // The step's own time waited; the pause itself, spent with the step, is practice too.
        Check.equal(engine.activeSeconds, 410)
    }

    func testPausedTimeCountsAsPracticeOnlyWhilePresent() {
        var engine = stageEngine()
        engine.begin(configuration(), at: 0)
        engine.pause(at: 10)
        engine.resume(at: 40)
        Check.equal(engine.activeSeconds, 40)
        Check.equal(engine.remainingSeconds, 50)
        engine.pause(at: 50)
        engine.setPresent(false, at: 60)
        Check.isFalse(engine.isPresent)
        engine.setPresent(true, at: 500)
        engine.resume(at: 520)
        // 10 s paused before leaving and 20 s after coming back; the 440 s away never count.
        Check.equal(engine.activeSeconds, 80)
        Check.equal(engine.remainingSeconds, 40)
        // Leaving a running practice pauses it as of the last sample, and nothing counts until they're back.
        engine.tick(at: 530)
        engine.setPresent(false, at: 530.1)
        Check.equal(engine.phase, .paused)
        engine.setPresent(true, at: 900)
        engine.resume(at: 905)
        Check.equal(engine.activeSeconds, 95)
        Check.equal(engine.remainingSeconds, 30)
        // A confirmation is not practice.
        engine.requestConfirmation(.restart, at: 910)
        engine.cancelConfirmation(at: 950)
        engine.tick(at: 960)
        Check.equal(engine.activeSeconds, 110)
        engine.pause(at: 970)
        engine.requestConfirmation(.end, at: 980)
        engine.cancelConfirmation(at: 1000)
        engine.resume(at: 1010)
        // 10 s running, 10 s paused, the 20 s question skipped, then 10 s paused.
        Check.equal(engine.activeSeconds, 140)
        // Presence outlasts the practice.
        engine.setPresent(false, at: 1020)
        engine.reset()
        Check.isFalse(engine.isPresent)
        engine.begin(configuration(), at: 1030)
        Check.isFalse(engine.isPresent)
    }

    func testLongUnobservedGapPausesWithoutUnattendedProgress() {
        var engine = stageEngine()
        engine.begin(configuration(2, 0, 12), at: 0)
        engine.tick(at: 1, maximumGap: 2.5)
        engine.tick(at: 1000, maximumGap: 2.5)
        Check.equal(engine.phase, .paused)
        Check.equal(engine.stageIndex, 0)
        Check.equal(engine.remainingSeconds, 11)
        Check.equal(engine.activeSeconds, 1)
    }

    func testSpaceAfterLongStallAlsoPauses() {
        var engine = stageEngine()
        engine.begin(configuration(), at: 0)
        Check.isFalse(engine.nextStage(at: 200, maximumGap: 2.5))
        Check.equal(engine.phase, .paused)
        Check.equal(engine.stageIndex, 0)
    }

    func testPauseAtDeadlineNeverAdvancesUntilResumed() {
        var engine = stageEngine()
        engine.begin(configuration(), at: 0)
        engine.pause(at: 60)
        Check.equal(engine.stageIndex, 0)
        engine.resume(at: 200)
        engine.tick(at: 200)
        Check.equal(engine.stageIndex, 1)
        Check.equal(engine.remainingSeconds, 60)
    }

    func testRestartNeedsConfirmationAndResetsAllProgress() {
        var engine = stageEngine()
        engine.begin(configuration(3, 7), at: 0)
        for now in 1...7 { engine.nextStage(at: Double(now)) }
        engine.requestConfirmation(.restart, at: 8)
        Check.equal(engine.phase, .confirming)
        Check.equal(engine.completedCycles, 1)
        Check.isFalse(engine.nextStage(at: 9))
        engine.confirm(at: 20)
        Check.equal(engine.phase, .running)
        Check.equal(engine.stageIndex, 0)
        Check.equal(engine.completedCycles, 0)
        Check.equal(engine.activeSeconds, 0)
        Check.equal(engine.remainingSeconds, 420)
        Check.equal(engine.configuration.cycles, 3)
    }

    func testCancelRunningConfirmationResumesWithoutCountingDialogTime() {
        var engine = stageEngine()
        engine.begin(configuration(), at: 0)
        engine.requestConfirmation(.end, at: 10)
        engine.tick(at: 50)
        engine.cancelConfirmation(at: 100)
        Check.equal(engine.phase, .running)
        Check.equal(engine.remainingSeconds, 50)
        engine.tick(at: 110)
        Check.equal(engine.activeSeconds, 20)
    }

    func testCancelPausedConfirmationRemainsPaused() {
        var engine = stageEngine()
        engine.begin(configuration(), at: 0)
        engine.pause(at: 10)
        engine.requestConfirmation(.restart, at: 20)
        engine.cancelConfirmation(at: 30)
        Check.equal(engine.phase, .paused)
        Check.equal(engine.remainingSeconds, 50)
    }

    func testLeavingWhileConfirmingPreventsAutomaticResumeOnCancel() {
        var engine = stageEngine()
        engine.begin(configuration(), at: 0)
        engine.requestConfirmation(.end, at: 10)
        engine.setPresent(false, at: 50)
        engine.cancelConfirmation(at: 100)
        Check.equal(engine.phase, .paused)
    }

    func testEndAndQuitClearSessionOnlyAfterConfirmation() {
        for action in [SessionEngine.Confirmation.end, .quit] {
            var engine = stageEngine()
            engine.begin(configuration(), at: 0)
            engine.nextStage(at: 5)
            engine.requestConfirmation(action, at: 10)
            Check.equal(engine.stageIndex, 1)
            Check.equal(engine.confirm(at: 20), action)
            Check.equal(engine.phase, .ready)
            Check.equal(engine.activeSeconds, 0)
        }
    }

    func testReadyAndCompleteIgnoreSpaceAndTimer() {
        var engine = stageEngine()
        Check.isFalse(engine.nextStage(at: 0))
        Check.isFalse(engine.tick(at: 100))
        engine.begin(configuration(), at: 100)
        for now in 101...105 { engine.nextStage(at: Double(now)) }
        Check.equal(engine.phase, .complete)
        Check.isFalse(engine.nextStage(at: 200))
        Check.isFalse(engine.tick(at: 500))
        Check.equal(engine.activeSeconds, 5)
        Check.equal(engine.completedCycles, 1)
    }

    func testMixedManualAndAutomaticTimeMatchesOnlyPracticedTime() {
        var engine = stageEngine()
        engine.begin(configuration(), at: 0)
        engine.nextStage(at: 20)
        engine.tick(at: 80)
        engine.nextStage(at: 90)
        engine.tick(at: 150)
        engine.nextStage(at: 160)
        Check.equal(engine.phase, .complete)
        Check.equal(engine.activeSeconds, 160)
        Check.lessThan(engine.activeSeconds, engine.configuration.plannedSeconds)
    }

    func testJitterAndBackwardClockCannotMakeNegativeTime() {
        var engine = stageEngine()
        engine.begin(configuration(), at: 100)
        engine.tick(at: 99)
        Check.equal(engine.remainingSeconds, 60)
        engine.tick(at: 100.1)
        engine.tick(at: 100.9)
        engine.tick(at: 101.7)
        Check.equal(engine.remainingSeconds, 58.3, accuracy: 0.0001)
        engine.tick(at: 200)
        Check.equal(engine.stageIndex, 1)
        Check.equal(engine.remainingSeconds, 60)
        Check.equal(engine.activeSeconds, 60)
    }

    func testAssetMapPreservesOwnerOrderAndLabels() {
        Check.equal(Stage.all.map(\.id), [1, 2, 3, 4, 5])
        Check.equal(Stage.all.map(\.fileName), ["pic_1.png", "pic_2.jpg", "pic_3.png", "pic_4.png", "pic_5.png"])
        Check.equal(Stage.all[1].label, "विश्व महाराजन — सतयुग में")
        Check.equal(Stage.all[3].label, "परम पवित्र ब्राह्मण — संगम युग में")
        Check.equal(Set(Stage.all.map(\.assetID)).count, 5)
    }

    func testDisplayFormattingRoundsCountdownUpAndPracticeDown() {
        Check.equal(TimeText.countdown(36.01), "00:37")
        Check.equal(TimeText.countdown(-1), "00:00")
        Check.equal(TimeText.elapsed(36.99), "00:36")
        Check.equal(TimeText.countdown(84), "01:24")
        Check.equal(TimeText.elapsed(3601), "1:00:01")
        Check.equal(TimeText.duration(840), "14 min")
        Check.equal(TimeText.duration(3605), "1 hr 5 sec")
        Check.equal(TimeText.duration(3661), "1 hr 1 min 1 sec")
    }

    func testLegacyPreferencesKeepTheSamePace() {
        let suite = "com.swadarshan.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(2, forKey: "cycles")
        for (oldMinutes, expectedSeconds) in [(1, 12), (5, 60), (7, 84), (10, 120), (120, 1440)] {
            defaults.set(oldMinutes, forKey: "minutesPerCycle")
            let loaded = SessionPreferences.load(from: defaults)
            Check.equal(loaded.enteredSeconds, expectedSeconds)
            Check.equal(loaded.timing, .perStep)
            Check.equal(loaded.cycles, 2)
            Check.equal(loaded.plannedSeconds, Double(2 * oldMinutes * 60))
        }
    }

    func testPerStepPreferencesRoundTripAndTakePrecedence() {
        let suite = "com.swadarshan.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(10, forKey: "minutesPerCycle")
        let configured = configuration(3, 1, 30)
        SessionPreferences.save(configured, to: defaults)
        let loaded = SessionPreferences.load(from: defaults)
        Check.equal(loaded, configured)
        Check.equal(loaded.enteredMinutes, 1)
        Check.equal(loaded.enteredSecondsComponent, 30)
        Check.equal(loaded.plannedSeconds, 1350)
    }

    func testTotalTimeIsSharedEquallyByEveryStep() {
        let threeInTen = total(3, 10)
        Check.equal(threeInTen.secondsPerStage, 40)
        Check.equal(threeInTen.secondsPerCycle, 200)
        Check.equal(threeInTen.plannedSeconds, 600)
        Check.equal(total(1, 5).secondsPerStage, 60)
        Check.equal(total(1, 600).secondsPerStage, 7200)
        Check.equal(total(3, 0, 15).secondsPerStage, 1)
        // An uneven split keeps every step equal and the planned total exact.
        let sevenInTen = total(7, 10)
        Check.equal(sevenInTen.secondsPerStage, 600.0 / 35, accuracy: 1e-12)
        Check.equal(sevenInTen.plannedSeconds, 600)
        Check.equal(TimeText.approximateDuration(sevenInTen.secondsPerStage), "≈ 17 sec")
        Check.equal(TimeText.approximateDuration(sevenInTen.secondsPerCycle), "≈ 1 min 26 sec")
        Check.equal(TimeText.approximateDuration(threeInTen.secondsPerStage), "40 sec")
        Check.equal(TimeText.approximateDuration(threeInTen.secondsPerCycle), "3 min 20 sec")
    }

    func testTotalTimeValidation() {
        Check.equal(SessionConfiguration.minuteRange(for: .total), 0...600)
        Check.equal(SessionConfiguration.minuteRange(for: .perStep), 0...120)
        Check.throwsError(try SessionConfiguration(cycles: 1, totalMinutes: 0))
        Check.throwsError(try SessionConfiguration(cycles: 1, totalMinutes: 0, totalSeconds: 4))
        Check.notNil(try? SessionConfiguration(cycles: 1, totalMinutes: 0, totalSeconds: 5))
        Check.throwsError(try SessionConfiguration(cycles: 3, totalMinutes: 0, totalSeconds: 14))
        Check.throwsError(try SessionConfiguration(cycles: 108, totalMinutes: 8, totalSeconds: 59))
        Check.notNil(try? SessionConfiguration(cycles: 108, totalMinutes: 9))
        Check.throwsError(try SessionConfiguration(cycles: 1, totalMinutes: 600, totalSeconds: 1))
        Check.throwsError(try SessionConfiguration(cycles: 1, totalMinutes: 601))
        Check.throwsError(try SessionConfiguration(cycles: 0, totalMinutes: 10))
        Check.throwsError(try SessionConfiguration(cycles: 1, totalMinutes: 10, totalSeconds: 60))
    }

    func testSwitchingTimingModeKeepsThePractice() {
        let perStep = configuration(3, 1)
        let asTotal = perStep.expressed(as: .total)
        Check.equal(asTotal.timing, .total)
        Check.equal(asTotal.enteredMinutes, 15)
        Check.equal(asTotal.secondsPerStage, 60)
        Check.equal(asTotal.expressed(as: .perStep), perStep)
        Check.equal(total(3, 10).expressed(as: .perStep), configuration(3, 0, 40))
        Check.equal(total(7, 10).expressed(as: .perStep), configuration(7, 0, 17))
        Check.equal(total(108, 9).expressed(as: .perStep), configuration(108, 0, 1))
        // Beyond the ten-hour total, the longest total possible is offered instead.
        Check.equal(configuration(108, 120).expressed(as: .total), total(108, 600))
        Check.equal(perStep.expressed(as: .perStep), perStep)
    }

    func testTotalTimeSessionFinishesAtTheEnteredTotal() {
        let config = total(7, 10)
        var engine = stageEngine()
        engine.begin(config, at: 0)
        var now = 0.0
        for step in 1...35 {
            now += config.secondsPerStage + 0.01
            Check.isTrue(engine.tick(at: now))
            Check.equal(engine.completedCycles, step / 5)
        }
        Check.equal(engine.phase, .complete)
        Check.equal(engine.activeSeconds, 600, accuracy: 1e-9)
        Check.equal(TimeText.elapsed(engine.activeSeconds), "10:00")
        Check.equal(TimeText.elapsed(599.9999999), "10:00")
    }

    func testEveryCycleOpensWithATitleCardOutsidePracticeTime() {
        var engine = SessionEngine()
        Check.equal(engine.introductionDuration, 3)
        engine.begin(configuration(2), at: 0)
        Check.isTrue(engine.isIntroducingCycle)
        Check.isFalse(engine.isIntroducingStage)
        Check.equal(engine.currentCycle, 1)
        Check.equal(engine.stageIndex, 0)
        Check.isFalse(engine.tick(at: 2.9))
        Check.isTrue(engine.isIntroducingCycle)
        Check.equal(engine.remainingSeconds, 60)
        Check.equal(engine.activeSeconds, 0)
        // After three seconds the cycle card gives way to step 1's own card, the cycle of ages.
        Check.isFalse(engine.tick(at: 3))
        Check.isFalse(engine.isIntroducingCycle)
        Check.isTrue(engine.isIntroducingStage)
        Check.equal(engine.stageIndex, 0)
        Check.isFalse(engine.tick(at: 5.9))
        Check.isTrue(engine.isIntroducingStage)
        Check.isTrue(engine.tick(at: 6))
        Check.isFalse(engine.isIntroducing)
        Check.equal(engine.stageIndex, 0)
        Check.equal(engine.remainingSeconds, 60)
        Check.equal(engine.transitionCount, 0)
        engine.tick(at: 66)
        Check.equal(engine.stageIndex, 1)
        // Each later step opens with a card of its own: Space begins the step, and Space again moves on.
        for now in stride(from: 67.0, through: 74, by: 1) { engine.nextStage(at: now) }
        // Completing cycle 1 introduces cycle 2 before its first step.
        Check.equal(engine.completedCycles, 1)
        Check.isTrue(engine.isIntroducingCycle)
        Check.isFalse(engine.isIntroducingStage)
        Check.equal(engine.currentCycle, 2)
        Check.equal(engine.stageIndex, 0)
        Check.isFalse(engine.tick(at: 76.9))
        Check.isTrue(engine.isIntroducingCycle)
        Check.isFalse(engine.tick(at: 77))
        Check.isTrue(engine.isIntroducingStage)
        Check.isTrue(engine.tick(at: 80))
        Check.isFalse(engine.isIntroducing)
        // 60 s for step 1, then 1 s for each of steps 2 to 5; no card counts.
        Check.equal(engine.activeSeconds, 64, accuracy: 1e-9)
        for now in stride(from: 81.0, through: 89, by: 1) { engine.nextStage(at: now) }
        // The last cycle ends in completion, never another card.
        Check.equal(engine.phase, .complete)
        Check.isFalse(engine.isIntroducing)
        Check.equal(engine.currentCycle, 2)
    }

    func testEveryLaterStepOpensWithACardOutsidePracticeTime() {
        var engine = SessionEngine()
        engine.begin(configuration(2), at: 0)
        Check.isTrue(engine.tick(at: 6))
        // Step 1's time runs out: step 2's card shows, and step 2 waits with its full time.
        Check.isTrue(engine.tick(at: 66))
        Check.isTrue(engine.isIntroducingStage)
        Check.isTrue(engine.isIntroducing)
        Check.isFalse(engine.isIntroducingCycle)
        Check.equal(engine.stageIndex, 1)
        Check.equal(engine.remainingSeconds, 60)
        Check.equal(engine.transitionCount, 1)
        Check.isFalse(engine.tick(at: 68.9))
        Check.equal(engine.remainingSeconds, 60)
        Check.equal(engine.activeSeconds, 60)
        Check.isTrue(engine.tick(at: 69))
        Check.isFalse(engine.isIntroducing)
        Check.equal(engine.stageIndex, 1)
        Check.equal(engine.remainingSeconds, 60)
        // A key press at the card's end is the same single transition.
        Check.isFalse(engine.nextStage(at: 69.05, eventTime: 69.05))
        Check.equal(engine.stageIndex, 1)
        // Space ends a step early; on its card, Space begins the next step at once, with its full time.
        Check.isTrue(engine.nextStage(at: 73))
        Check.isTrue(engine.isIntroducingStage)
        Check.equal(engine.stageIndex, 2)
        Check.isTrue(engine.nextStage(at: 74))
        Check.isFalse(engine.isIntroducing)
        Check.equal(engine.stageIndex, 2)
        Check.equal(engine.remainingSeconds, 60)
        Check.isFalse(engine.nextStage(at: 74.5, isRepeat: true))
        // Pausing on a card begins its step, which waits with its full time.
        Check.isTrue(engine.nextStage(at: 83))
        engine.pause(at: 84)
        Check.equal(engine.phase, .paused)
        Check.isFalse(engine.isIntroducing)
        Check.equal(engine.stageIndex, 3)
        Check.equal(engine.remainingSeconds, 60)
        engine.resume(at: 93)
        engine.tick(at: 103)
        Check.equal(engine.remainingSeconds, 50)
        // 60 + 4 + 9 s of steps, 9 s paused with step 4, and 10 s of it; no card counts.
        Check.equal(engine.activeSeconds, 92)
        Check.equal(engine.stepSeconds, [[60, 4, 9, 19, 0]])
        // Without cards, each step follows the last at once.
        var direct = stageEngine()
        direct.begin(configuration(), at: 0)
        Check.isFalse(direct.isIntroducing)
        Check.isTrue(direct.nextStage(at: 5))
        Check.isFalse(direct.isIntroducingStage)
        Check.equal(direct.stageIndex, 1)
    }

    func testTimeIsRecordedForEachStepOfEachCycle() {
        var engine = stageEngine()
        engine.begin(configuration(2), at: 0)
        Check.equal(engine.stepSeconds, [[0, 0, 0, 0, 0]])
        engine.tick(at: 60)                  // Step 1 runs its full minute.
        engine.nextStage(at: 70)             // Step 2: 10 s, then Space.
        engine.pause(at: 75)                 // Step 3: 5 s, 20 s paused with it, and 5 s more.
        engine.resume(at: 95)
        engine.nextStage(at: 100)
        engine.tick(at: 110)                 // Step 4: 10 s, 100 s away, and 5 s more.
        engine.setPresent(false, at: 110)
        engine.setPresent(true, at: 210)
        engine.resume(at: 210)
        engine.nextStage(at: 215)
        engine.nextStage(at: 225)            // Step 5: 10 s, which completes cycle 1.
        Check.equal(engine.stepSeconds, [[60, 10, 30, 15, 10], [0, 0, 0, 0, 0]])
        for now in [226.0, 227, 228, 229, 230] { engine.nextStage(at: now) }
        Check.equal(engine.phase, .complete)
        Check.equal(engine.stepSeconds, [[60, 10, 30, 15, 10], [1, 1, 1, 1, 1]])
        Check.equal(engine.stepSeconds.joined().reduce(0, +), engine.activeSeconds)
        // A new practice starts its record afresh.
        engine.begin(configuration(), at: 300)
        Check.equal(engine.stepSeconds, [[0, 0, 0, 0, 0]])
        engine.reset()
        Check.equal(engine.stepSeconds, [])
    }

    func testSpaceOnTitleCardBeginsFirstStepOnly() {
        var engine = SessionEngine()
        engine.begin(configuration(), at: 0)
        Check.isTrue(engine.nextStage(at: 1))
        Check.isFalse(engine.isIntroducingCycle)
        Check.equal(engine.stageIndex, 0)
        Check.equal(engine.remainingSeconds, 60)
        Check.isFalse(engine.nextStage(at: 1.5, isRepeat: true))
        Check.isTrue(engine.nextStage(at: 2))
        Check.equal(engine.stageIndex, 1)
        Check.equal(engine.activeSeconds, 1)
    }

    func testTitleCardEndAndSpaceAtSameBoundaryIsOneTransition() {
        var engine = SessionEngine()
        engine.begin(configuration(), at: 0)
        Check.isTrue(engine.tick(at: 6))
        Check.isFalse(engine.nextStage(at: 6.05, eventTime: 6.05))
        Check.equal(engine.stageIndex, 0)
        // A press made during the cards but delivered after they ended is stale.
        Check.isFalse(engine.nextStage(at: 6.3, eventTime: 5.9))
        Check.equal(engine.stageIndex, 0)
        Check.isTrue(engine.nextStage(at: 6.4, eventTime: 6.4))
        Check.equal(engine.stageIndex, 1)
    }

    func testPausingOnTitleCardKeepsTheFullFirstStep() {
        var engine = SessionEngine()
        engine.begin(configuration(), at: 0)
        engine.pause(at: 1.5)
        Check.equal(engine.phase, .paused)
        Check.isFalse(engine.isIntroducingCycle)
        Check.equal(engine.remainingSeconds, 60)
        engine.resume(at: 100)
        Check.isFalse(engine.isIntroducingCycle)
        engine.tick(at: 130)
        Check.equal(engine.remainingSeconds, 30)
        // The pause counts as practice (98.5 s); the card never does.
        Check.equal(engine.activeSeconds, 128.5)

        var away = SessionEngine()
        away.begin(configuration(), at: 0)
        away.tick(at: 1, maximumGap: 2.5)
        away.tick(at: 500, maximumGap: 2.5)
        Check.equal(away.phase, .paused)
        Check.isFalse(away.isIntroducingCycle)
        Check.equal(away.remainingSeconds, 60)

        var confirming = SessionEngine()
        confirming.begin(configuration(), at: 0)
        confirming.requestConfirmation(.restart, at: 1)
        confirming.cancelConfirmation(at: 10)
        Check.equal(confirming.phase, .running)
        Check.isFalse(confirming.isIntroducingCycle)
        Check.equal(confirming.remainingSeconds, 60)
        confirming.requestConfirmation(.restart, at: 20)
        confirming.confirm(at: 30)
        Check.isTrue(confirming.isIntroducingCycle)
        Check.equal(confirming.currentCycle, 1)
        confirming.reset()
        Check.equal(confirming.introductionDuration, 3)
    }

    func testTotalTimePreferencesRoundTripAndFallBack() {
        let suite = "com.swadarshan.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        SessionPreferences.save(configuration(2, 1, 30), to: defaults)
        let configured = total(3, 5)
        SessionPreferences.save(configured, to: defaults)
        Check.equal(SessionPreferences.load(from: defaults), configured)
        // A total too short for the saved cycles (108 need 9 min) falls back to the per-step time.
        defaults.set(108, forKey: "cycles")
        Check.equal(SessionPreferences.load(from: defaults), configuration(108, 1, 30))
        SessionPreferences.save(configuration(4, 2), to: defaults)
        Check.equal(SessionPreferences.load(from: defaults), configuration(4, 2))
    }

    func testFreestyleHasNoTimer() throws {
        let free = try SessionConfiguration(freestyleCycles: 3)
        Check.equal(free.timing, .freestyle)
        Check.isFalse(free.isTimed)
        Check.isTrue(configuration().isTimed)
        Check.isTrue(total(3, 10).isTimed)
        Check.equal(free.stepCount, 15)
        Check.equal(free.enteredSeconds, 0)
        Check.equal(free.secondsPerStage, 0)
        Check.equal(free.secondsPerCycle, 0)
        Check.equal(free.plannedSeconds, 0)
        Check.equal(SessionConfiguration.minuteRange(for: .freestyle), 0...0)
        Check.throwsError(try SessionConfiguration(freestyleCycles: 0))
        Check.throwsError(try SessionConfiguration(freestyleCycles: 109))
        Check.throwsError(try SessionConfiguration(cycles: 1, timing: .freestyle, minutes: 0, seconds: 5))
        Check.throwsError(try SessionConfiguration(cycles: 1, timing: .freestyle, minutes: 1))
        // There is no time to carry over either way.
        Check.equal(configuration(3, 1).expressed(as: .freestyle), free)
        Check.equal(total(3, 10).expressed(as: .freestyle), free)
        Check.equal(free.expressed(as: .perStep), free)
        Check.equal(free.expressed(as: .total), free)
    }

    func testFreestyleStepsLastUntilThePractitionerMovesOn() {
        var engine = SessionEngine()
        engine.begin(try! SessionConfiguration(freestyleCycles: 2), at: 0)
        // The cards that open each cycle still last three seconds each.
        Check.isTrue(engine.isIntroducingCycle)
        Check.isFalse(engine.tick(at: 2.9))
        Check.isFalse(engine.tick(at: 3))
        Check.isTrue(engine.isIntroducingStage)
        Check.isTrue(engine.tick(at: 6))
        Check.isFalse(engine.isIntroducing)
        // A step never ends by itself, however long it is given.
        Check.isFalse(engine.tick(at: 4000))
        Check.equal(engine.phase, .running)
        Check.equal(engine.stageIndex, 0)
        Check.equal(engine.progress, 0)
        Check.equal(engine.activeSeconds, 3994)
        Check.isTrue(engine.nextStage(at: 4010))
        Check.equal(engine.stageIndex, 1)
        Check.isTrue(engine.isIntroducingStage)
        Check.equal(engine.activeSeconds, 4004)
        Check.isFalse(engine.nextStage(at: 4010.5, isRepeat: true))
        // Each later step's card lasts three seconds too; then the step waits for Space.
        Check.isTrue(engine.tick(at: 4013))
        for now in [4020.0, 4030, 4040] {
            engine.nextStage(at: now)
            Check.isTrue(engine.isIntroducingStage)
            Check.isTrue(engine.tick(at: now + 3))
        }
        engine.nextStage(at: 4050)
        Check.equal(engine.completedCycles, 1)
        Check.isTrue(engine.isIntroducingCycle)
        Check.equal(engine.currentCycle, 2)
        Check.isTrue(engine.tick(at: 4056))
        engine.pause(at: 4060)
        engine.resume(at: 4100)
        for now in [4110.0, 4120, 4130, 4140] {
            engine.nextStage(at: now)
            engine.tick(at: now + 3)
        }
        engine.nextStage(at: 4150)
        Check.equal(engine.phase, .complete)
        Check.equal(engine.completedCycles, 2)
        // 4004 + 4 × 7 s in cycle 1, then 4 + 10 + 4 × 7 s in cycle 2; no pause or card counts.
        Check.equal(engine.activeSeconds, 4074)
        Check.equal(engine.stepSeconds, [[4004, 7, 7, 7, 7], [14, 7, 7, 7, 7]])
    }

    func testFreestylePausesNeverCountAsPractice() {
        var engine = stageEngine()
        engine.begin(try! SessionConfiguration(freestyleCycles: 1), at: 0)
        engine.pause(at: 10)
        Check.isFalse(engine.tick(at: 20))
        Check.isFalse(engine.nextStage(at: 30))
        engine.resume(at: 40)
        Check.equal(engine.activeSeconds, 10)
        Check.equal(engine.stepSeconds, [[10, 0, 0, 0, 0]])

        engine.pause(at: 50)
        engine.setPresent(false, at: 60)
        Check.equal(engine.activeSeconds, 20)
        engine.setPresent(true, at: 500)
        engine.resume(at: 520)
        Check.equal(engine.activeSeconds, 20)

        // Leaving and returning never starts counting a freestyle pause.
        engine.tick(at: 530)
        engine.setPresent(false, at: 530.1)
        engine.setPresent(true, at: 900)
        engine.resume(at: 905)
        Check.equal(engine.activeSeconds, 30)

        engine.requestConfirmation(.restart, at: 910)
        engine.cancelConfirmation(at: 950)
        Check.equal(engine.phase, .running)
        engine.tick(at: 960)
        Check.equal(engine.activeSeconds, 45)
        engine.pause(at: 970)
        engine.requestConfirmation(.end, at: 980)
        Check.equal(engine.activeSeconds, 55)
        engine.cancelConfirmation(at: 1000)
        Check.equal(engine.phase, .paused)
        engine.resume(at: 1010)
        Check.equal(engine.activeSeconds, 55)

        // An unobserved gap pauses at the last sample; the pause after it is excluded too.
        engine.tick(at: 1015)
        engine.tick(at: 1100, maximumGap: 2.5)
        Check.equal(engine.phase, .paused)
        engine.resume(at: 1200)
        Check.equal(engine.activeSeconds, 60)
        for now in [1205.0, 1210, 1215, 1220, 1225] { engine.nextStage(at: now) }
        Check.equal(engine.phase, .complete)
        Check.equal(engine.activeSeconds, 85)
        Check.equal(engine.stepSeconds, [[65, 5, 5, 5, 5]])
        Check.equal(engine.stepSeconds.joined().reduce(0, +), engine.activeSeconds)

        // Escape during the opening cards begins a paused step without counting that pause.
        var cards = SessionEngine()
        cards.begin(try! SessionConfiguration(freestyleCycles: 1), at: 0)
        cards.pause(at: 1.5)
        cards.resume(at: 100)
        cards.tick(at: 105)
        Check.equal(cards.activeSeconds, 5)
        Check.equal(cards.stepSeconds, [[5, 0, 0, 0, 0]])
    }

    func testFreestylePreferencesKeepTheTimeLastEntered() {
        let suite = "com.swadarshan.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        SessionPreferences.save(configuration(3, 1, 30), to: defaults)
        let free = try! SessionConfiguration(freestyleCycles: 2)
        SessionPreferences.save(free, to: defaults)
        Check.equal(SessionPreferences.load(from: defaults), free)
        // The time fields keep the time last entered, for when a timer is chosen again.
        Check.equal(SessionPreferences.loadTimed(from: defaults), configuration(2, 1, 30))
        SessionPreferences.save(total(4, 20), to: defaults)
        Check.equal(SessionPreferences.load(from: defaults), total(4, 20))
        Check.equal(SessionPreferences.loadTimed(from: defaults), total(4, 20))
    }

    func testMissingAndInvalidPreferencesUseSensibleDefaults() {
        let suite = "com.swadarshan.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        Check.equal(SessionPreferences.load(from: defaults), .standard)
        defaults.set(-8, forKey: "cycles")
        defaults.set(0, forKey: "stepDurationSeconds")
        defaults.set(500, forKey: "minutesPerCycle")
        Check.equal(SessionPreferences.load(from: defaults), .standard)
    }
}
