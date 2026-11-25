// Checks that web/engine.js behaves like MeditationCore. Run: node Tests/web/engine-checks.mjs
import {
  STAGES, PER_STEP, TOTAL, FREESTYLE, SessionConfiguration as Config, SessionEngine, TimeText,
  loadPreferences, loadTimedPreferences, savePreferences,
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

check("each cycle opens with a three-second card, then step 1's own card, neither practice time", () => {
  const engine = new SessionEngine();
  engine.begin(perStep(2, 0, 10), 100);
  equal(engine.isIntroducingCycle, true, "card at begin");
  equal(engine.isIntroducingStage, false, "the cycle card first");
  equal(engine.tick(102.9), false, "card still showing");
  equal(engine.tick(103), false, "the cycle card gives way");
  equal(engine.isIntroducingCycle, false, "to step 1's card");
  equal(engine.isIntroducingStage, true, "the cycle of ages");
  equal(engine.stageIndex, 0, "before step 1");
  equal(engine.tick(105.9), false, "still showing");
  equal(engine.tick(106), true, "cards end");
  equal(engine.isIntroducing, false, "step begins");
  equal(engine.remainingSeconds, 10, "full first step");
  engine.tick(111);
  near(engine.remainingSeconds, 5, "counting down");
  near(engine.activeSeconds, 5, "cards not counted");
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
  withCard.tick(6);
  let now = 6;
  for (let step = 1; step < 5; step += 1) {
    now += 10;
    equal(withCard.tick(now), true, `step ${step} ends`);
    equal(withCard.isIntroducingStage, true, `the card before step ${step + 1}`);
    equal(withCard.stageIndex, step, "leads to the next step");
    equal(withCard.remainingSeconds, 10, "which waits with its full time");
    now += 3;
    equal(withCard.tick(now), true, "the card ends");
  }
  equal(withCard.tick(now + 10), true, "step 5 ends");
  equal(withCard.completedCycles, 1, "one cycle");
  equal(withCard.stageIndex, 0, "back to the first form");
  equal(withCard.isIntroducingCycle, true, "second cycle card");
  equal(withCard.isIntroducingStage, false, "not a card between steps");
  equal(withCard.currentCycle, 2, "cycle 2");
  near(withCard.activeSeconds, 50, "no card counted");
});

check("each later step opens with a three-second card that is not practice time", () => {
  const engine = new SessionEngine();
  engine.begin(perStep(2, 1), 0);
  equal(engine.tick(6), true, "the cycle's cards end");
  equal(engine.tick(66), true, "step 1 ends");
  equal(engine.isIntroducingStage, true, "card between steps");
  equal(engine.isIntroducing, true, "a card");
  equal(engine.isIntroducingCycle, false, "not a cycle card");
  equal(engine.stageIndex, 1, "leads to step 2");
  equal(engine.remainingSeconds, 60, "step 2 waits with its full time");
  equal(engine.tick(68.9), false, "card still showing");
  near(engine.activeSeconds, 60, "card not counted");
  equal(engine.tick(69), true, "card ends");
  equal(engine.isIntroducing, false, "step 2 begins");
  equal(engine.nextStage(69.05, { eventTime: 69.05 }), false, "a press at the card's end is the same transition");
  equal(engine.nextStage(73), true, "Space ends step 2 early");
  equal(engine.isIntroducingStage, true, "step 3's card");
  equal(engine.nextStage(74), true, "Space on the card begins step 3");
  equal(engine.isIntroducing, false, "card gone");
  equal(engine.remainingSeconds, 60, "full step 3");
  equal(engine.nextStage(74.5, { isRepeat: true }), false, "key repeat");
  equal(engine.nextStage(83), true, "on to step 4's card");
  engine.pause(84);
  equal(engine.phase, "paused", "pausing on the card");
  equal(engine.stageIndex, 3, "begins step 4");
  equal(engine.remainingSeconds, 60, "paused with its full time");
  engine.resume(93);
  engine.tick(103);
  near(engine.remainingSeconds, 50, "counting down");
  near(engine.activeSeconds, 92, "60 + 4 + 9 + 9 paused + 10; no card counted");
  equal(JSON.stringify(engine.stepSeconds), "[[60,4,9,19,0]]", "step by step");
  const direct = stageEngine();
  direct.begin(perStep(1, 1), 0);
  equal(direct.nextStage(5), true, "without cards");
  equal(direct.isIntroducingStage, false, "no card");
  equal(direct.stageIndex, 1, "straight to step 2");
});

check("the time of each step of each cycle is recorded", () => {
  const engine = stageEngine();
  engine.begin(perStep(2, 1), 0);
  equal(JSON.stringify(engine.stepSeconds), "[[0,0,0,0,0]]", "an empty first cycle");
  engine.tick(60);                    // Step 1 runs its full minute.
  engine.nextStage(70);               // Step 2: 10 s, then Space.
  engine.pause(75);                   // Step 3: 5 s, 20 s paused with it, and 5 s more.
  engine.resume(95);
  engine.nextStage(100);
  engine.tick(110);                   // Step 4: 10 s, 100 s away, and 5 s more.
  engine.setPresent(false, 110);
  engine.setPresent(true, 210);
  engine.resume(210);
  engine.nextStage(215);
  engine.nextStage(225);              // Step 5: 10 s, which completes cycle 1.
  equal(JSON.stringify(engine.stepSeconds), "[[60,10,30,15,10],[0,0,0,0,0]]", "cycle 1, and cycle 2 begun");
  for (const time of [226, 227, 228, 229, 230]) engine.nextStage(time);
  equal(engine.phase, "complete", "complete");
  equal(JSON.stringify(engine.stepSeconds), "[[60,10,30,15,10],[1,1,1,1,1]]", "both cycles");
  near(engine.stepSeconds.flat().reduce((sum, seconds) => sum + seconds, 0), engine.activeSeconds, "adds up to the practiced time");
  engine.begin(perStep(1, 1), 300);
  equal(JSON.stringify(engine.stepSeconds), "[[0,0,0,0,0]]", "a new practice starts afresh");
  engine.reset();
  equal(engine.stepSeconds.length, 0, "none after a reset");
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

check("progress is the share of the step already practiced", () => {
  const engine = stageEngine();
  engine.begin(perStep(1, 1), 0);
  near(engine.progress, 0, "start");
  engine.tick(15);
  near(engine.progress, 0.25, "a quarter in");
  engine.pause(30);
  near(engine.progress, 0.5, "paused halfway");
  engine.resume(100);
  engine.nextStage(100);
  near(engine.progress, 0, "the next step starts afresh");
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
  engine.setPresent(false, 7);
  engine.cancelConfirmation(9);
  equal(engine.phase, "paused", "paused");
});

check("a pause counts as practice only while the practitioner is here", () => {
  const engine = stageEngine();
  engine.begin(perStep(1, 1), 0);
  engine.pause(10);
  engine.resume(40);
  equal(engine.activeSeconds, 40, "30 s paused with the step");
  equal(engine.remainingSeconds, 50, "the step's own time waited");
  engine.pause(50);
  engine.setPresent(false, 60);
  equal(engine.isPresent, false, "away");
  engine.setPresent(true, 500);
  engine.resume(520);
  equal(engine.activeSeconds, 80, "time away never counts");
  engine.tick(530);
  engine.setPresent(false, 530.1);
  equal(engine.phase, "paused", "leaving pauses a running practice");
  engine.setPresent(true, 900);
  engine.resume(905);
  equal(engine.activeSeconds, 95, "nothing counted until back");
  engine.requestConfirmation("restart", 910);
  engine.cancelConfirmation(950);
  engine.tick(960);
  equal(engine.activeSeconds, 110, "a confirmation is not practice");
  engine.pause(970);
  engine.requestConfirmation("end", 980);
  engine.cancelConfirmation(1000);
  engine.resume(1010);
  equal(engine.activeSeconds, 140, "paused either side of the question");
  engine.setPresent(false, 1020);
  engine.reset();
  engine.begin(perStep(1, 1), 1030);
  equal(engine.isPresent, false, "presence outlasts the practice");
});

check("freestyle has no timer", () => {
  const free = Config.freestyle(3);
  equal(free.timing, FREESTYLE, "timing");
  equal(free.isTimed, false, "untimed");
  equal(perStep(1, 1).isTimed, true, "per step is timed");
  equal(free.stepCount, 15, "steps");
  equal(free.secondsPerStage, 0, "per step");
  equal(free.plannedSeconds, 0, "planned");
  equal(Config.minuteRange(FREESTYLE)[1], 0, "no minutes");
  equal(Config.make(0, FREESTYLE, 0), null, "zero cycles");
  equal(Config.make(1, FREESTYLE, 0, 5), null, "no time allowed");
  equal(Config.make(1, "other", 1), null, "unknown timing");
  equal(perStep(3, 1).expressed(FREESTYLE).timing, FREESTYLE, "to freestyle");
  equal(perStep(3, 1).expressed(FREESTYLE).cycles, 3, "keeps cycles");
  equal(free.expressed(PER_STEP), free, "stays freestyle");
});

check("a freestyle step lasts until the practitioner moves on", () => {
  const engine = new SessionEngine();
  engine.begin(Config.freestyle(2), 0);
  equal(engine.tick(2.9), false, "card still showing");
  equal(engine.tick(3), false, "the cycle card gives way to step 1's card");
  equal(engine.tick(6), true, "the cards end after three seconds each");
  equal(engine.tick(4000), false, "a step never ends by itself");
  equal(engine.stageIndex, 0, "still step 1");
  equal(engine.progress, 0, "no progress to show");
  equal(engine.activeSeconds, 3994, "all of it practiced");
  equal(engine.nextStage(4010), true, "Space moves on");
  equal(engine.stageIndex, 1, "step 2");
  equal(engine.isIntroducingStage, true, "its card first");
  equal(engine.tick(4013), true, "the card lasts three seconds");
  for (const time of [4020, 4030, 4040]) {
    engine.nextStage(time);
    equal(engine.tick(time + 3), true, "each card ends by itself");
  }
  engine.nextStage(4050);
  equal(engine.isIntroducingCycle, true, "cycle 2 card");
  engine.tick(4056);
  engine.pause(4060);
  engine.resume(4100);
  for (const time of [4110, 4120, 4130, 4140]) {
    engine.nextStage(time);
    engine.tick(time + 3);
  }
  engine.nextStage(4150);
  equal(engine.phase, "complete", "complete");
  equal(engine.activeSeconds, 4074, "practiced; no pause or card counted");
  equal(JSON.stringify(engine.stepSeconds), "[[4004,7,7,7,7],[14,7,7,7,7]]", "step by step");
});

check("freestyle pauses never count as practice", () => {
  const engine = stageEngine();
  engine.begin(Config.freestyle(1), 0);
  engine.pause(10);
  equal(engine.tick(20), false, "paused timer stays stopped");
  equal(engine.nextStage(30), false, "Space does not advance a pause");
  engine.resume(40);
  equal(engine.activeSeconds, 10, "manual pause excluded");
  equal(JSON.stringify(engine.stepSeconds), "[[10,0,0,0,0]]", "step excludes pause too");

  engine.pause(50);
  engine.setPresent(false, 60);
  equal(engine.activeSeconds, 20, "pause before leaving excluded");
  engine.setPresent(true, 500);
  engine.resume(520);
  equal(engine.activeSeconds, 20, "absence and pause after returning excluded");

  engine.tick(530);
  engine.setPresent(false, 530.1);
  engine.setPresent(true, 900);
  engine.resume(905);
  equal(engine.activeSeconds, 30, "automatically paused time excluded");

  engine.requestConfirmation("restart", 910);
  engine.cancelConfirmation(950);
  equal(engine.phase, "running", "running confirmation cancelled");
  engine.tick(960);
  equal(engine.activeSeconds, 45, "confirmation excluded");
  engine.pause(970);
  engine.requestConfirmation("end", 980);
  equal(engine.activeSeconds, 55, "pause before confirmation excluded");
  engine.cancelConfirmation(1000);
  equal(engine.phase, "paused", "paused confirmation cancelled");
  engine.resume(1010);
  equal(engine.activeSeconds, 55, "pause after confirmation excluded");

  engine.tick(1015);
  engine.tick(1100, 2.5);
  equal(engine.phase, "paused", "unobserved gap pauses");
  engine.resume(1200);
  equal(engine.activeSeconds, 60, "gap and following pause excluded");
  for (const time of [1205, 1210, 1215, 1220, 1225]) engine.nextStage(time);
  equal(engine.phase, "complete", "completed after resuming");
  equal(engine.activeSeconds, 85, "only running time practiced");
  equal(JSON.stringify(engine.stepSeconds), "[[65,5,5,5,5]]", "each step excludes pauses");
  equal(engine.stepSeconds.flat().reduce((sum, seconds) => sum + seconds, 0), engine.activeSeconds, "steps add to total");

  const cards = new SessionEngine();
  cards.begin(Config.freestyle(1), 0);
  cards.pause(1.5);
  cards.resume(100);
  cards.tick(105);
  equal(cards.activeSeconds, 5, "pause on opening cards excluded");
  equal(JSON.stringify(cards.stepSeconds), "[[5,0,0,0,0]]", "first step excludes opening pause");
});

check("freestyle keeps the time last entered", () => {
  const stored = new Map();
  const write = (key, value) => stored.set(key, value);
  const read = (key) => stored.get(key) ?? null;
  savePreferences(perStep(3, 1, 30), write);
  savePreferences(Config.freestyle(2), write);
  const loaded = loadPreferences(read);
  equal(loaded.timing, FREESTYLE, "freestyle");
  equal(loaded.cycles, 2, "cycles");
  const timed = loadTimedPreferences(read);
  equal(timed.timing, PER_STEP, "time kept");
  equal(timed.enteredSeconds, 90, "1:30 per step");
  savePreferences(total(4, 20), write);
  equal(loadPreferences(read).timing, TOTAL, "a timer again");
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
