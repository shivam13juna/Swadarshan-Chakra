// Checks that web/engine.js behaves like MeditationCore. Run: node Tests/web/engine-checks.mjs
import {
  STAGES, PER_STEP, TOTAL, SessionConfiguration as Config, SessionEngine, TimeText,
  loadPreferences, savePreferences,
} from "../../web/engine.js";

let checks = 0;
let failures = 0;
function check(name, body) {
  checks += 1;
  try {
    body();
  } catch (error) {
    failures += 1;
    console.error(`✗ ${name}: ${error.message}`);
  }
}
function equal(actual, expected, what = "value") {
  if (actual !== expected) throw new Error(`${what}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
}
function near(actual, expected, what = "value") {
  if (Math.abs(actual - expected) > 1e-9) throw new Error(`${what}: expected ${expected}, got ${actual}`);
}

const perStep = (cycles, minutes, seconds = 0) => new Config(cycles, PER_STEP, minutes, seconds);
const total = (cycles, minutes, seconds = 0) => new Config(cycles, TOTAL, minutes, seconds);
const stageEngine = () => new SessionEngine(0);

check("five forms in order", () => {
  equal(STAGES.length, 5, "count");
  equal(STAGES[3].context, "संगम युग में", "stage 4 context");
  equal(STAGES[4].context, "", "stage 5 context");
});

check("per-step timing", () => {
  const config = perStep(3, 1, 30);
  equal(config.secondsPerStage, 90, "per step");
  equal(config.secondsPerCycle, 450, "per cycle");
  equal(config.plannedSeconds, 1350, "planned");
});

check("total time is shared equally", () => {
  const config = total(3, 10);
  equal(config.secondsPerStage, 40, "per step");
  equal(TimeText.duration(config.secondsPerCycle), "3 min 20 sec", "per cycle");
  const uneven = total(7, 10);
  equal(uneven.plannedSeconds, 600, "planned stays exact");
  equal(TimeText.approximateDuration(uneven.secondsPerStage), "≈ 17 sec", "per step");
  equal(TimeText.approximateDuration(uneven.secondsPerCycle), "≈ 1 min 26 sec", "per cycle");
});

check("validation", () => {
  equal(Config.make(0, PER_STEP, 1), null, "zero cycles");
  equal(Config.make(109, PER_STEP, 1), null, "109 cycles");
  equal(Config.make(1, PER_STEP, 0, 0), null, "zero-length step");
  equal(Config.make(1, PER_STEP, 120, 0)?.enteredSeconds, 7200, "two hours per step");
  equal(Config.make(1, PER_STEP, 120, 1), null, "over two hours per step");
  equal(Config.make(1, PER_STEP, 1, 60), null, "60 seconds");
  equal(Config.make(1, TOTAL, 0, 4), null, "less than a second per step");
  equal(Config.make(1, TOTAL, 600, 0)?.enteredSeconds, 36000, "ten hours");
  equal(Config.make(1, TOTAL, 600, 1), null, "over ten hours");
});

check("minimum total is one second per step", () => {
  equal(Config.make(108, TOTAL, 8, 59), null, "539 s");
  equal(Config.make(108, TOTAL, 9, 0)?.enteredSeconds ?? null, 540, "540 s");
});

check("whole numbers only", () => {
  const range = [0, 120];
  equal(Config.integer("12", range), 12, "12");
  equal(Config.integer("007", range), 7, "007");
  for (const text of ["", " 12", "12 ", "1.5", "-1", "+1", "١٢", "121", "1e2"]) {
    equal(Config.integer(text, range), null, JSON.stringify(text));
  }
});

check("switching how time is entered keeps the practice", () => {
  equal(perStep(3, 1).expressed(TOTAL).enteredSeconds, 900, "per step to total");
  equal(total(7, 10).expressed(PER_STEP).enteredSeconds, 17, "total to per step rounds");
  equal(perStep(108, 120).expressed(TOTAL).enteredSeconds, 36000, "capped at ten hours");
  equal(total(1, 600).expressed(PER_STEP).enteredSeconds, 7200, "ten hours for one cycle");
});

check("time text", () => {
  equal(TimeText.countdown(59.2), "01:00", "countdown rounds up");
  equal(TimeText.countdown(0), "00:00", "zero");
  equal(TimeText.countdown(3600), "1:00:00", "hours");
  equal(TimeText.elapsed(599.9999999), "10:00", "float tolerance");
  equal(TimeText.duration(59), "59 sec", "seconds");
  equal(TimeText.duration(3725), "1 hr 2 min 5 sec", "hours");
  equal(TimeText.duration(7200), "2 hr", "whole hours");
  equal(TimeText.approximateDuration(40), "40 sec", "exact");
});

check("each cycle opens with a three-second card that is not practice time", () => {
  const engine = new SessionEngine();
  engine.begin(perStep(2, 0, 10), 100);
  equal(engine.isIntroducingCycle, true, "card at begin");
  equal(engine.tick(102.9), false, "card still showing");
  equal(engine.tick(103), true, "card ends");
  equal(engine.isIntroducingCycle, false, "step begins");
  equal(engine.remainingSeconds, 10, "full first step");
  engine.tick(108);
  near(engine.remainingSeconds, 5, "counting down");
  near(engine.activeSeconds, 5, "card not counted");
});

check("steps advance one at a time and cycles begin with a card", () => {
  const engine = stageEngine();
  engine.begin(perStep(2, 0, 10), 0);
  engine.tick(0);
  for (let step = 1; step < 5; step += 1) {
    equal(engine.tick(step * 10), true, `step ${step} ends`);
    equal(engine.stageIndex, step, "next step");
  }
  const withCard = new SessionEngine();
  withCard.begin(perStep(2, 0, 10), 0);
  withCard.tick(3);
  for (let step = 1; step <= 5; step += 1) withCard.tick(3 + step * 10);
  equal(withCard.completedCycles, 1, "one cycle");
  equal(withCard.stageIndex, 0, "back to the first form");
  equal(withCard.isIntroducingCycle, true, "second cycle card");
  equal(withCard.currentCycle, 2, "cycle 2");
});

check("space on the card starts the cycle with a full first step", () => {
  const engine = new SessionEngine();
  engine.begin(perStep(1, 1), 0);
  equal(engine.nextStage(1), true, "skips the card");
  equal(engine.isIntroducingCycle, false, "card gone");
  equal(engine.remainingSeconds, 60, "full step");
  equal(engine.stageIndex, 0, "still the first form");
});

check("pausing on the card begins the cycle, paused with a full step", () => {
  const engine = new SessionEngine();
  engine.begin(perStep(1, 1), 0);
  engine.pause(1);
  equal(engine.phase, "paused", "paused");
  equal(engine.introductionRemaining, 0, "card consumed");
  equal(engine.remainingSeconds, 60, "full step");
});

check("pause keeps the exact remaining time and ignores Space", () => {
  const engine = stageEngine();
  engine.begin(perStep(1, 1), 0);
  engine.tick(0);
  engine.tick(12.5);
  engine.pause(12.5);
  equal(engine.nextStage(20), false, "Space while paused");
  engine.resume(50);
  near(engine.remainingSeconds, 47.5, "remaining");
  engine.tick(51);
  near(engine.remainingSeconds, 46.5, "resumes counting");
});

check("held Space and stale events never skip", () => {
  const engine = stageEngine();
  engine.begin(perStep(1, 1), 0);
  engine.tick(0);
  equal(engine.nextStage(5, { isRepeat: true }), false, "key repeat");
  equal(engine.nextStage(5, { eventTime: -1 }), false, "event from before this step");
  equal(engine.nextStage(5), true, "a fresh press");
  equal(engine.stageIndex, 1, "one step");
});

check("a key press at the moment a step ends is coalesced", () => {
  const engine = stageEngine();
  engine.begin(perStep(1, 0, 10), 0);
  engine.tick(0);
  equal(engine.tick(10), true, "timer ends step 1");
  equal(engine.nextStage(10.05, { eventTime: 10.05 }), false, "press at the boundary");
  equal(engine.stageIndex, 1, "only one step");
  equal(engine.nextStage(10.4, { eventTime: 10.4 }), true, "a later press");
  equal(engine.stageIndex, 2, "next step");
  const raced = stageEngine();
  raced.begin(perStep(1, 0, 10), 0);
  raced.tick(0);
  equal(raced.nextStage(10.1, { eventTime: 9.95 }), true, "key arrives as the step expires");
  equal(raced.stageIndex, 1, "expiry consumes the press");
});

check("a long unobserved gap pauses at the last sample", () => {
  const engine = stageEngine();
  engine.begin(perStep(1, 1), 0);
  engine.tick(0);
  engine.tick(10);
  equal(engine.tick(400, 2.5), false, "gap");
  equal(engine.phase, "paused", "paused");
  near(engine.remainingSeconds, 50, "absence not counted");
});

check("the last step of the last cycle completes the practice", () => {
  const engine = stageEngine();
  engine.begin(perStep(1, 0, 1), 0);
  engine.tick(0);
  for (let step = 1; step <= 5; step += 1) engine.tick(step);
  equal(engine.phase, "complete", "complete");
  equal(engine.completedCycles, 1, "cycles");
  near(engine.activeSeconds, 5, "practiced");
  equal(TimeText.elapsed(engine.activeSeconds), "00:05", "practiced text");
});

check("restart and end ask first; cancelling restores the previous state", () => {
  const engine = stageEngine();
  engine.begin(perStep(2, 1), 0);
  engine.tick(0);
  engine.tick(10);
  engine.requestConfirmation("restart", 10);
  equal(engine.phase, "confirming", "confirming");
  engine.cancelConfirmation(20);
  equal(engine.phase, "running", "running again");
  near(engine.remainingSeconds, 50, "progress kept");
  engine.pause(20);
  engine.requestConfirmation("end", 21);
  engine.cancelConfirmation(22);
  equal(engine.phase, "paused", "still paused");
  engine.requestConfirmation("restart", 23);
  equal(engine.confirm(23), "restart", "restart confirmed");
  equal(engine.phase, "running", "running from the start");
  equal(engine.stageIndex, 0, "first form");
  engine.requestConfirmation("end", 24);
  equal(engine.confirm(24), "end", "end confirmed");
  equal(engine.phase, "ready", "ready");
});

check("absence during a confirmation stays paused after cancelling", () => {
  const engine = stageEngine();
  engine.begin(perStep(1, 1), 0);
  engine.tick(0);
  engine.requestConfirmation("end", 5);
  engine.pauseAtLastSample();
  engine.cancelConfirmation(9);
  equal(engine.phase, "paused", "paused");
});

check("saved settings", () => {
  const stored = new Map();
  savePreferences(total(3, 10), (key, value) => stored.set(key, value));
  const loaded = loadPreferences((key) => stored.get(key) ?? null);
  equal(loaded.timing, TOTAL, "timing");
  equal(loaded.enteredSeconds, 600, "total");
  equal(loaded.cycles, 3, "cycles");
  const tooShort = new Map([["cycles", "108"], ["timingMode", TOTAL], ["totalDurationSeconds", "300"], ["stepDurationSeconds", "84"]]);
  const fallback = loadPreferences((key) => tooShort.get(key) ?? null);
  equal(fallback.timing, PER_STEP, "invalid total falls back");
  equal(fallback.enteredSeconds, 84, "per-step value kept");
  const empty = loadPreferences(() => null);
  equal(empty.cycles, 1, "default cycles");
  equal(empty.enteredSeconds, 60, "default minute");
  const bad = loadPreferences((key) => ({ cycles: "500", stepDurationSeconds: "abc" })[key] ?? null);
  equal(bad.cycles, 1, "out-of-range cycles");
  equal(bad.enteredSeconds, 60, "unreadable duration");
});

console.log(`${checks - failures}/${checks} web engine checks passed`);
if (failures) process.exit(1);
