// Checks that web/history.js reads, writes, and sums the history exactly as MeditationCore does: the
// Swift checks (PracticeHistoryTests.swift) assert the same numbers and words on the same fixture.
// Run: node Tests/web/history-checks.mjs
import { readFileSync } from "node:fs";
import { SessionConfiguration, SessionEngine, PER_STEP } from "../../web/engine.js";
import {
  CivilDate, parsePracticeTime, practiceTimeAt, practiceTimeText, makeRecord, recordFromEngine, isWorthKeeping,
  PracticeHistory, HistoryReadError, PracticeInsights, HistoryText, importSummary, readErrorMessage,
} from "../../web/history.js";

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
  const [a, e] = [JSON.stringify(actual), JSON.stringify(expected)];
  if (a !== e) throw new Error(`${what}: expected ${e}, got ${a}`);
}
function throwsKind(body, kind, version = null, what = "error") {
  try {
    body();
  } catch (error) {
    if (!(error instanceof HistoryReadError)) throw error;
    equal(error.kind, kind, what);
    equal(error.version, version, `${what} version`);
    return;
  }
  throw new Error(`${what}: expected ${kind}, nothing was thrown`);
}

const fixture = readFileSync(new URL("../fixtures/history-v1.json", import.meta.url), "utf8");
const TODAY = 20775; // Wednesday, 18 November 2026
const MONDAY = 1;
const record = (id, start, seconds, cycles = 1, planned = cycles) =>
  makeRecord({ id, start, seconds, cycles, planned, timing: PER_STEP });

check("calendar days", () => {
  equal(CivilDate.dayNumber(1970, 1, 1), 0, "1 January 1970");
  equal(CivilDate.dayNumber(2026, 11, 18), TODAY, "18 November 2026");
  equal(CivilDate.weekday(0), 4, "a Thursday");
  equal(CivilDate.weekday(TODAY), 3, "a Wednesday");
  equal(CivilDate.daysInMonth(2, 2024), 29, "2024 is a leap year");
  equal(CivilDate.daysInMonth(2, 2100), 28, "2100 is not");
  equal(CivilDate.daysInMonth(2, 2000), 29, "2000 is");
  for (let day = 0; day < 40000; day += 37) {
    const { year, month, day: date } = CivilDate.fromDayNumber(day);
    equal(CivilDate.dayNumber(year, month, date), day, `day ${day} round trip`);
  }
  equal(CivilDate.fromDayNumber(20513), { year: 2026, month: 3, day: 1 }, "after February");
});

check("practice times", () => {
  const india = parsePracticeTime("2026-11-18T06:42:10+05:30");
  equal([india.dayNumber, india.hour, india.minute, india.second, india.offset], [TODAY, 6, 42, 10, 330], "parts");
  equal(india.instant, TODAY * 86400 + 6 * 3600 + 42 * 60 + 10 - 330 * 60, "instant");
  equal(parsePracticeTime("2026-11-18T01:12:10Z").instant, india.instant, "the same moment in UTC");
  equal(parsePracticeTime("2026-10-25T06:30:00-07:00").offset, -420, "behind UTC");
  for (const bad of ["2026-11-18T06:42:10", "2026-11-18 06:42:10Z", "2026-13-01T00:00:00Z", "2026-11-18T24:00:00Z",
    "2026-11-18T06:42:10+15:00", "2026-02-29T00:00:00Z", "1969-12-31T23:59:59Z", "2026-11-18T06:42:10.5Z",
    "2026-11-18T06:42:10+0530", "", null]) {
    equal(parsePracticeTime(bad), null, `rejects ${bad}`);
  }
  for (const text of ["2026-11-18T06:42:10+05:30", "2026-11-18T01:12:10Z", "2026-10-25T06:30:00-07:00",
    "2024-02-29T23:59:59+14:00"]) {
    equal(practiceTimeText(parsePracticeTime(text)), text, `${text} round trip`);
  }
  const moment = new Date(Date.UTC(2026, 10, 18, 1, 12, 10));
  const local = practiceTimeAt(moment);
  equal(local.instant, moment.getTime() / 1000, "this device's clock");
  equal(parsePracticeTime(practiceTimeText(local)).instant, local.instant, "written and read back");
});

check("reading the shared backup", () => {
  const { history, skipped } = PracticeHistory.read(fixture);
  equal(skipped, 12, "unreadable practices left out");
  equal(history.records.map((kept) => kept.id).join(" "),
    "a20 a19 a18 b05 b06 b07 b08 b09 b10 a17 a09 a08 a07 a06 a05 a04 a03 a01 a02", "each once, oldest first");
  const byId = (id) => history.records.find((kept) => kept.id === id);
  equal([byId("a06").seconds, byId("a06").cycles], [900, 2], "a longer copy replaces the shorter");
  equal(byId("a03").seconds, 1500, "a shorter copy is ignored");
  equal([byId("a08").steps, byId("a08").device], [null, null], "steps and device are optional");
  equal(byId("a09").time.dayNumber, CivilDate.dayNumber(2026, 10, 25), "counted on its own local day");
  equal(history.recordsOn(TODAY).map((kept) => kept.id), ["a01", "a02"], "today's practices");
});

check("insights from the shared backup", () => {
  const insights = new PracticeInsights(PracticeHistory.read(fixture).history, TODAY, MONDAY);
  equal(insights.all, { seconds: 18150, practices: 19, cycles: 59 }, "in all");
  equal([insights.firstDay, insights.activeDays], [20393, 18], "first day and days practiced");
  equal(insights.todayTotals, { seconds: 1230, practices: 2, cycles: 4 }, "today");
  equal([insights.last7, insights.previous7, insights.last30, insights.previous30], [5430, 3600, 10950, 5400], "spans");
  equal([insights.currentStreak, insights.bestStreak], [4, 6], "streaks");
  equal([insights.recent28, insights.previous28, insights.trend], [10650, 5700, "rising"], "trend");
  equal(insights.weekStarts, [20696, 20703, 20710, 20717, 20724, 20731, 20738, 20745, 20752, 20759, 20766, 20773], "weeks");
  equal(insights.weekTotals, [0, 0, 1200, 0, 1800, 3600, 0, 1200, 720, 0, 5700, 3330], "week totals");
  equal([insights.rhythmPractices, insights.peak, insights.quiet, insights.busiestWeekday], [18, "earlyMorning", "afternoon", 1], "rhythm");
  equal([insights.amritVelaMornings, insights.fullDay], [2, 1800], "amrit vela and a full day");
  equal([insights.heat[1][6], insights.heat[0][1], insights.heat[2][21]], [2400, 720, 3600], "hours of the week");
  equal([insights.heatLevel(1, 6), insights.heatLevel(0, 1), insights.heatLevel(2, 21), insights.heatLevel(2, 2)], [3, 1, 4, 0], "heat levels");
  equal([TODAY, TODAY - 2, TODAY - 8, TODAY - 4].map((day) => insights.level(day)), [3, 2, 4, 0], "calendar levels");
  equal(insights.weekdayOrder, [1, 2, 3, 4, 5, 6, 0], "Monday first");
  equal(insights.todayDetail, "2 practices · 4 cycles", "today's words");
  equal(insights.weekComparison, { direction: "up", text: "Up 51% on the 7 days before" }, "the week");
  equal(insights.monthComparison, { direction: "up", text: "Up 103% on the 30 days before" }, "the month");
  equal([insights.streakValue, insights.streakDetail], ["4 days", "Best: 6 days"], "streak words");
  equal(insights.cyclesDetail, "49 more to a mala of 108", "cycles words");
  equal([insights.trendTitle, insights.trendDetail],
    ["Rising", "2 hr 58 min in the last four weeks, up 87% on the four before."], "trend words");
  equal(insights.rhythmNotes, [
    "You practice most in the early morning, especially on Mondays.",
    "Your afternoons are quiet. A short cycle after lunch could carry the calm through the day.",
    "Amrit vela, 3 to 5 am: 2 of the last 30 mornings.",
  ], "rhythm words");
  equal(new PracticeInsights(new PracticeHistory(), TODAY, 0).weekStart(TODAY), 20772, "Sunday first");
});

check("an empty history", () => {
  const insights = new PracticeInsights(new PracticeHistory(), TODAY, MONDAY);
  equal([insights.all.seconds, insights.currentStreak, insights.bestStreak, insights.firstDay], [0, 0, 0, null], "nothing yet");
  equal([insights.trend, insights.trendTitle], ["resting", "Resting"], "trend");
  equal(insights.weekTotals, Array(12).fill(0), "weeks");
  equal([insights.todayDetail, insights.streakDetail, insights.cyclesDetail],
    ["Not yet today", "Practice on days in a row", "108 more to a mala of 108"], "words");
  equal(insights.weekComparison, { direction: "none", text: "None in the 7 days before either" }, "the week");
  equal(insights.rhythmNotes, ["Practice a few more times, and the hours you favor will show here."], "rhythm");
  equal([insights.level(TODAY), insights.heatLevel(3, 6)], [0, 0], "levels");
});

check("trends and streaks", () => {
  const day = (offset, seconds, id = `d${offset}`) => {
    const { year, month, day: date } = CivilDate.fromDayNumber(TODAY - offset);
    return record(id, `${year}-${String(month).padStart(2, "0")}-${String(date).padStart(2, "0")}T07:00:00+05:30`, seconds);
  };
  const steady = new PracticeInsights(new PracticeHistory([day(3, 1000), day(40, 1050)]), TODAY, MONDAY);
  equal([steady.trend, steady.trendDetail], ["steady", "17 min in the last four weeks, much as in the four before."], "steady");
  const easing = new PracticeInsights(new PracticeHistory([day(3, 800), day(40, 1000)]), TODAY, MONDAY);
  equal([easing.trend, easing.trendTitle, easing.trendDetail],
    ["easing", "Easing off", "13 min in the last four weeks, down 20% on the four before."], "easing");
  const beginning = new PracticeInsights(new PracticeHistory([day(1, 600), day(2, 600)]), TODAY, MONDAY);
  equal([beginning.trend, beginning.currentStreak, beginning.streakDetail], ["beginning", 2, "Practice today to keep it"], "from yesterday");
  equal(beginning.trendDetail, "20 min in the last four weeks, your first. Keep going, and your trend will show here.", "beginning");
  const resting = new PracticeInsights(new PracticeHistory([day(80, 600)]), TODAY, MONDAY);
  equal([resting.trend, resting.currentStreak, resting.streakDetail], ["resting", 0, "Best: 1 day"], "resting");
  const lapsed = new PracticeInsights(new PracticeHistory([day(2, 600), day(3, 600)]), TODAY, MONDAY);
  equal(lapsed.currentStreak, 0, "a missed day ends the streak");
  const malas = new PracticeInsights(new PracticeHistory([record("m", "2026-11-18T06:00:00+05:30", 6000, 100, 108),
    record("n", "2026-11-17T06:00:00+05:30", 6000, 108, 108), record("o", "2026-11-16T06:00:00+05:30", 6000, 30, 108)]), TODAY, MONDAY);
  equal(malas.cyclesDetail, "2 malas of 108 · 22 toward the next", "malas");
});

check("merging another device's practices", () => {
  const incoming = PracticeHistory.read(fixture).history.records;
  const local = new PracticeHistory([record("a01", "2026-11-18T04:12:00+05:30", 600, 2, 3),
    record("local-1", "2026-11-14T06:00:00Z", 1200, 4)]);
  equal(local.merge(incoming), { added: 18, updated: 1, unchanged: 0 }, "first import");
  equal(local.records.length, 20, "all kept");
  equal(local.records.find((kept) => kept.id === "a01").seconds, 900, "the longer copy");
  equal(local.merge(incoming), { added: 0, updated: 0, unchanged: 19 }, "importing again changes nothing");
  local.upsert(record("a01", "2026-11-18T04:12:00+05:30", 300));
  equal([local.records.length, local.records.find((kept) => kept.id === "a01").seconds], [20, 300], "saving replaces");
  const india = record("i", "2026-11-18T06:00:00+05:30", 600);
  const utc = record("u", "2026-11-18T01:00:00Z", 600);
  equal(new PracticeHistory([utc, india]).records.map((kept) => kept.id), ["i", "u"], "ordered by the moment, across zones");
  equal(importSummary({ added: 18, updated: 1, unchanged: 0 }, "b.json", 12),
    "Added 18 practices from “b.json”. Brought 1 practice up to date. 12 couldn't be read and were left out.", "summary");
  equal(importSummary({ added: 0, updated: 0, unchanged: 19 }, "b.json", 0), "Everything in “b.json” was already here.", "nothing new");
  equal(importSummary({ added: 0, updated: 1, unchanged: 1 }, "b.json", 1),
    "Brought 1 practice up to date from “b.json”. 1 was already here. 1 couldn't be read and was left out.", "updates only");
  equal(PracticeHistory.backupName(TODAY), "Swadarshan Chakra backup 2026-11-18.json", "file name");
});

check("writing and reading a backup", () => {
  const { history } = PracticeHistory.read(fixture);
  const text = history.document(parsePracticeTime("2026-11-18T20:05:00+05:30"));
  equal(text.split("\n").slice(0, 6), ["{", '  "format": "swadarshan-chakra-history",', '  "version": 1,',
    '  "app": "Swadarshan Chakra",', '  "exported": "2026-11-18T20:05:00+05:30",', '  "practices": ['], "header");
  equal(text.split("\n")[6],
    '    {"id":"a20","start":"2025-11-01T06:00:00+05:30","seconds":600,"cycles":2,"planned":2,"timing":"perStep","steps":[120,120,120,120,120],"device":"mac"},',
    "one practice per line");
  const back = PracticeHistory.read(text);
  equal(back.skipped, 0, "nothing skipped");
  equal(back.history.records.map((kept) => [kept.id, kept.start, kept.seconds, kept.cycles, kept.planned, kept.timing, kept.steps, kept.device]),
    history.records.map((kept) => [kept.id, kept.start, kept.seconds, kept.cycles, kept.planned, kept.timing, kept.steps, kept.device]), "round trip");
  equal(new PracticeHistory().document(), '{\n  "format": "swadarshan-chakra-history",\n  "version": 1,\n  "app": "Swadarshan Chakra",\n  "practices": []\n}\n', "empty");
});

check("files that aren't backups", () => {
  throwsKind(() => PracticeHistory.read("not json"), "unreadable");
  throwsKind(() => PracticeHistory.read("[]"), "unreadable");
  throwsKind(() => PracticeHistory.read('{"format": "something-else", "version": 1, "practices": []}'), "notABackup");
  throwsKind(() => PracticeHistory.read('{"format": "swadarshan-chakra-history", "version": 1}'), "notABackup");
  throwsKind(() => PracticeHistory.read('{"format": "swadarshan-chakra-history", "version": "1", "practices": []}'), "notABackup");
  throwsKind(() => PracticeHistory.read('{"format": "swadarshan-chakra-history", "version": 2, "practices": []}'), "newerVersion", 2);
  equal(PracticeHistory.read('{"format": "swadarshan-chakra-history", "version": 1, "practices": []}').history.records.length, 0, "empty");
  equal(readErrorMessage(new HistoryReadError("unreadable"), "b.json"),
    "“b.json” couldn't be read. Choose a backup saved by Swadarshan Chakra.", "unreadable message");
  equal(readErrorMessage(new HistoryReadError("notABackup"), "b.json"), "“b.json” isn't a Swadarshan Chakra backup.", "not a backup");
  equal(readErrorMessage(new HistoryReadError("newerVersion", 2), "b.json"),
    "“b.json” comes from a newer version of Swadarshan Chakra. Update this one to import it.", "newer version");
});

check("practices from the engine", () => {
  const engine = new SessionEngine(0);
  engine.begin(new SessionConfiguration(2, PER_STEP, 0, 30), 0);
  for (let now = 30; now <= 300; now += 30) engine.tick(now);
  equal(engine.phase, "complete", "finished");
  const start = parsePracticeTime("2026-11-18T06:00:00+05:30");
  const finished = recordFromEngine("x", start, engine, "web");
  equal([finished.seconds, finished.cycles, finished.planned, finished.timing, finished.steps, finished.device, finished.start],
    [300, 2, 2, PER_STEP, [60, 60, 60, 60, 60], "web", "2026-11-18T06:00:00+05:30"], "the record");
  const short = new SessionEngine(0);
  short.begin(new SessionConfiguration(3, PER_STEP, 1, 0), 0);
  short.tick(20);
  equal(isWorthKeeping(short), false, "twenty seconds aren't kept");
  short.tick(40);
  short.tick(60);
  equal([isWorthKeeping(short), recordFromEngine("y", start, short, "web").cycles], [true, 0], "a minute is");
  const quick = new SessionEngine(0);
  quick.begin(new SessionConfiguration(1, PER_STEP, 0, 2), 0);
  for (let now = 2; now <= 10; now += 2) quick.tick(now);
  equal([quick.phase, isWorthKeeping(quick)], ["complete", true], "so is a whole cycle");
});

check("words and numbers", () => {
  equal([0, 29, 30, 89, 90, 3600, 3630, 7800].map(HistoryText.minutes),
    ["0 min", "< 1 min", "1 min", "1 min", "2 min", "1 hr", "1 hr 1 min", "2 hr 10 min"], "minutes");
  equal([0, 20, 2700, 7800, 7200, 7500].map(HistoryText.compact), ["", "<1m", "45m", "2h10", "2h", "2h05"], "compact");
  equal([HistoryText.time(0, 5), HistoryText.time(12, 0), HistoryText.time(19, 40)], ["12:05 am", "12:00 pm", "7:40 pm"], "times");
  equal([0, 3, 12, 15].map(HistoryText.hourMark), ["12a", "3a", "12p", "3p"], "hour marks");
  equal([HistoryText.date(TODAY), HistoryText.dayTitle(TODAY), HistoryText.shortDate(20696)],
    ["18 November 2026", "Wednesday, 18 November", "31 Aug"], "dates");
  equal([HistoryText.count(1, "day"), HistoryText.count(2, "day")], ["1 day", "2 days"], "counts");
});

console.log(`${checks - failures}/${checks} web history checks passed`);
if (failures) process.exit(1);
