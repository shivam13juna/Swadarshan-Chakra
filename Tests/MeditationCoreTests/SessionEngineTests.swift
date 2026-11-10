import Foundation
import MeditationCore

final class SessionEngineTests {
    private func configuration(_ cycles: Int = 1, _ minutes: Int = 1, _ seconds: Int = 0) -> SessionConfiguration {
        try! SessionConfiguration(cycles: cycles, minutesPerStep: minutes, secondsPerStep: seconds)
    }

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
        Check.notNil(SessionConfiguration.integer("120", in: SessionConfiguration.minuteRange))
        Check.isNil(SessionConfiguration.integer("121", in: SessionConfiguration.minuteRange))
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
            var engine = SessionEngine()
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
        var engine = SessionEngine()
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

    func testStageFiveCountsCycleAndFinalManualAdvanceCompletes() {
        var engine = SessionEngine()
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
        var engine = SessionEngine()
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
            var engine = SessionEngine()
            engine.begin(configuration(), at: 0)
            engine.tick(at: 60)
            Check.isFalse(engine.nextStage(at: 60 + offset, eventTime: 60 + offset))
            Check.equal(engine.stageIndex, 1)
            Check.equal(engine.transitionCount, 1)
        }
    }

    func testSpaceThenTimerAtSameBoundaryIsOneTransition() {
        var engine = SessionEngine()
        engine.begin(configuration(), at: 0)
        engine.nextStage(at: 59.999)
        engine.tick(at: 60)
        Check.equal(engine.stageIndex, 1)
        Check.equal(engine.transitionCount, 1)
        Check.equal(engine.remainingSeconds, 59.999, accuracy: 0.0001)
    }

    func testSpaceOnExpiredStageConsumesOnlyExpiration() {
        var engine = SessionEngine()
        engine.begin(configuration(), at: 0)
        engine.nextStage(at: 60)
        Check.equal(engine.stageIndex, 1)
        Check.equal(engine.remainingSeconds, 60)
        Check.equal(engine.transitionCount, 1)
    }

    func testQueuedKeyFromPriorStageIsIgnored() {
        var engine = SessionEngine()
        engine.begin(configuration(), at: 0)
        engine.tick(at: 60)
        Check.isFalse(engine.nextStage(at: 60.5, eventTime: 59.9))
        Check.equal(engine.stageIndex, 1)
        Check.isTrue(engine.nextStage(at: 60.7, eventTime: 60.7))
        Check.equal(engine.stageIndex, 2)
    }

    func testDistinctQuickPhysicalPressesStillWork() {
        var engine = SessionEngine()
        engine.begin(configuration(), at: 0)
        engine.nextStage(at: 0.01)
        engine.nextStage(at: 0.02)
        Check.equal(engine.stageIndex, 2)
    }

    func testPauseExcludesElapsedAbsenceAndResumesExactly() {
        var engine = SessionEngine()
        engine.begin(configuration(), at: 0)
        engine.pause(at: 23)
        Check.equal(engine.remainingSeconds, 37)
        engine.tick(at: 400)
        Check.isFalse(engine.nextStage(at: 400))
        Check.equal(engine.remainingSeconds, 37)
        engine.resume(at: 400)
        engine.tick(at: 410)
        Check.equal(engine.remainingSeconds, 27)
        Check.equal(engine.activeSeconds, 33)
    }

    func testLongUnobservedGapPausesWithoutUnattendedProgress() {
        var engine = SessionEngine()
        engine.begin(configuration(2, 0, 12), at: 0)
        engine.tick(at: 1, maximumGap: 2.5)
        engine.tick(at: 1000, maximumGap: 2.5)
        Check.equal(engine.phase, .paused)
        Check.equal(engine.stageIndex, 0)
        Check.equal(engine.remainingSeconds, 11)
        Check.equal(engine.activeSeconds, 1)
    }

    func testSpaceAfterLongStallAlsoPauses() {
        var engine = SessionEngine()
        engine.begin(configuration(), at: 0)
        Check.isFalse(engine.nextStage(at: 200, maximumGap: 2.5))
        Check.equal(engine.phase, .paused)
        Check.equal(engine.stageIndex, 0)
    }

    func testPauseAtDeadlineNeverAdvancesUntilResumed() {
        var engine = SessionEngine()
        engine.begin(configuration(), at: 0)
        engine.pause(at: 60)
        Check.equal(engine.stageIndex, 0)
        engine.resume(at: 200)
        engine.tick(at: 200)
        Check.equal(engine.stageIndex, 1)
        Check.equal(engine.remainingSeconds, 60)
    }

    func testRestartNeedsConfirmationAndResetsAllProgress() {
        var engine = SessionEngine()
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
        var engine = SessionEngine()
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
        var engine = SessionEngine()
        engine.begin(configuration(), at: 0)
        engine.pause(at: 10)
        engine.requestConfirmation(.restart, at: 20)
        engine.cancelConfirmation(at: 30)
        Check.equal(engine.phase, .paused)
        Check.equal(engine.remainingSeconds, 50)
    }

    func testLeavingWhileConfirmingPreventsAutomaticResumeOnCancel() {
        var engine = SessionEngine()
        engine.begin(configuration(), at: 0)
        engine.requestConfirmation(.end, at: 10)
        engine.pauseAtLastSample()
        engine.cancelConfirmation(at: 100)
        Check.equal(engine.phase, .paused)
    }

    func testEndAndQuitClearSessionOnlyAfterConfirmation() {
        for action in [SessionEngine.Confirmation.end, .quit] {
            var engine = SessionEngine()
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
        var engine = SessionEngine()
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
        var engine = SessionEngine()
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
        var engine = SessionEngine()
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
        Check.equal(Stage.all[3].label, "परम पवित्र ब्राह्मण — कलियुग में")
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
            Check.equal(loaded.stepDurationSeconds, expectedSeconds)
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
        Check.equal(loaded.minutesPerStep, 1)
        Check.equal(loaded.secondsComponent, 30)
        Check.equal(loaded.plannedSeconds, 1350)
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
