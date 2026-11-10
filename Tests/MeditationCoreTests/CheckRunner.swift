import Foundation

/// A small assertion runner so these deterministic checks also run on Macs with only CLT.
enum Check {
    static var failures = 0
    static var assertions = 0

    private static func record(_ passes: Bool, _ message: String, file: StaticString, line: UInt) {
        assertions += 1
        if !passes {
            failures += 1
            fputs("FAIL \(file):\(line): \(message)\n", stderr)
        }
    }

    static func equal<T: Equatable>(_ value: T, _ expected: T, file: StaticString = #filePath, line: UInt = #line) {
        record(value == expected, "Expected \(expected), got \(value)", file: file, line: line)
    }
    static func equal(_ value: Double, _ expected: Double, accuracy: Double, file: StaticString = #filePath, line: UInt = #line) {
        record(abs(value - expected) <= accuracy, "Expected \(expected) ± \(accuracy), got \(value)", file: file, line: line)
    }
    static func isTrue(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) {
        record(value, "Expected true", file: file, line: line)
    }
    static func isFalse(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) {
        record(!value, "Expected false", file: file, line: line)
    }
    static func isNil<T>(_ value: T?, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        record(value == nil, "Expected nil. \(message)", file: file, line: line)
    }
    static func notNil<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) {
        record(value != nil, "Expected a value", file: file, line: line)
    }
    static func lessThan<T: Comparable>(_ value: T, _ maximum: T, file: StaticString = #filePath, line: UInt = #line) {
        record(value < maximum, "Expected \(value) < \(maximum)", file: file, line: line)
    }
    static func throwsError<T>(_ expression: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) {
        do {
            _ = try expression()
            record(false, "Expected an error", file: file, line: line)
        } catch {
            record(true, "", file: file, line: line)
        }
    }
}

@main
enum CoreCheckRunner {
    static func main() {
        let suite = SessionEngineTests()
        let cases: [(String, () throws -> Void)] = [
            ("Per-step durations and automatic totals", suite.testPerStepDurationsAndAutomaticTotals),
            ("Input validation", suite.testValidationRejectsOutOfRangeAndNonWholeInputs),
            ("Automatic cycles and completion", suite.testAllAutomaticSessionsFinishAtPlannedActiveTime),
            ("Space discards only current time", suite.testSpaceDiscardsOnlyCurrentStageRemainder),
            ("Stage 5 and manual completion", suite.testStageFiveCountsCycleAndFinalManualAdvanceCompletes),
            ("Key repeat", suite.testKeyRepeatNeverAdvances),
            ("Timer then Space at boundary", suite.testAutomaticThenSpaceAtSameBoundaryIsOneTransition),
            ("Space then timer at boundary", suite.testSpaceThenTimerAtSameBoundaryIsOneTransition),
            ("Space on expired stage", suite.testSpaceOnExpiredStageConsumesOnlyExpiration),
            ("Queued stale event", suite.testQueuedKeyFromPriorStageIsIgnored),
            ("Distinct quick presses", suite.testDistinctQuickPhysicalPressesStillWork),
            ("Pause and exact resume", suite.testPauseExcludesElapsedAbsenceAndResumesExactly),
            ("Unobserved time gap", suite.testLongUnobservedGapPausesWithoutUnattendedProgress),
            ("Space after stall", suite.testSpaceAfterLongStallAlsoPauses),
            ("Pause at deadline", suite.testPauseAtDeadlineNeverAdvancesUntilResumed),
            ("Confirmed restart", suite.testRestartNeedsConfirmationAndResetsAllProgress),
            ("Cancel running confirmation", suite.testCancelRunningConfirmationResumesWithoutCountingDialogTime),
            ("Cancel paused confirmation", suite.testCancelPausedConfirmationRemainsPaused),
            ("Absence during confirmation", suite.testLeavingWhileConfirmingPreventsAutomaticResumeOnCancel),
            ("Confirmed end and quit", suite.testEndAndQuitClearSessionOnlyAfterConfirmation),
            ("Ready and complete guards", suite.testReadyAndCompleteIgnoreSpaceAndTimer),
            ("Actual time with mixed advances", suite.testMixedManualAndAutomaticTimeMatchesOnlyPracticedTime),
            ("Clock jitter and bounds", suite.testJitterAndBackwardClockCannotMakeNegativeTime),
            ("Explicit artwork mapping", suite.testAssetMapPreservesOwnerOrderAndLabels),
            ("Duration formatting", suite.testDisplayFormattingRoundsCountdownUpAndPracticeDown),
            ("Legacy preference migration", suite.testLegacyPreferencesKeepTheSamePace),
            ("Per-step preference persistence", suite.testPerStepPreferencesRoundTripAndTakePrecedence),
            ("Invalid preference fallback", suite.testMissingAndInvalidPreferencesUseSensibleDefaults),
            ("Total time shared by every step", suite.testTotalTimeIsSharedEquallyByEveryStep),
            ("Total time validation", suite.testTotalTimeValidation),
            ("Switching timing mode", suite.testSwitchingTimingModeKeepsThePractice),
            ("Total time session length", suite.testTotalTimeSessionFinishesAtTheEnteredTotal),
            ("Cycle title cards", suite.testEveryCycleOpensWithATitleCardOutsidePracticeTime),
            ("Space on a title card", suite.testSpaceOnTitleCardBeginsFirstStepOnly),
            ("Title card boundary", suite.testTitleCardEndAndSpaceAtSameBoundaryIsOneTransition),
            ("Pause on a title card", suite.testPausingOnTitleCardKeepsTheFullFirstStep),
            ("Total time preferences", suite.testTotalTimePreferencesRoundTripAndFallBack)
        ]
        for (name, test) in cases {
            let previous = Check.failures
            do { try test() } catch { Check.failures += 1; fputs("FAIL \(name): \(error)\n", stderr) }
            print("\(Check.failures == previous ? "PASS" : "FAIL") \(name)")
        }
        print("\(cases.count) checks · \(Check.assertions) assertions · \(Check.failures) failures")
        exit(Check.failures == 0 ? 0 : 1)
    }
}
