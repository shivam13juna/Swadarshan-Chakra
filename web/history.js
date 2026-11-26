// The practice history, ported from Sources/MeditationCore (PracticeHistory.swift and
// PracticeInsights.swift). The Mac app and the web version read and write the same backup file, so
// keep the two in step: Tests/web/history-checks.mjs and the Swift core checks share Tests/fixtures.
import { STAGES, SessionConfiguration, PER_STEP, TOTAL, FREESTYLE } from "./engine.js";

const pad2 = (value) => String(value).padStart(2, "0");
const div = (a, b) => Math.trunc(a / b);

// MARK: Dates

/// A date on the practitioner's own calendar. Days are counted from 1 January 1970 as plain numbers,
/// so the Mac app and the web version agree exactly, whatever time zone either runs in.
export const CivilDate = {
  daysInMonth(month, year) {
    if (month === 2) return year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0) ? 29 : 28;
    return [4, 6, 9, 11].includes(month) ? 30 : 31;
  },

  isValid(year, month, day) {
    return year >= 1970 && year <= 9999 && month >= 1 && month <= 12 && day >= 1
      && day <= CivilDate.daysInMonth(month, year);
  },

  /// Days since 1 January 1970 (Howard Hinnant's days_from_civil).
  dayNumber(year, month, day) {
    const shiftedYear = month <= 2 ? year - 1 : year;
    const era = div(shiftedYear >= 0 ? shiftedYear : shiftedYear - 399, 400);
    const yearOfEra = shiftedYear - era * 400;
    const dayOfYear = div(153 * (month > 2 ? month - 3 : month + 9) + 2, 5) + day - 1;
    const dayOfEra = yearOfEra * 365 + div(yearOfEra, 4) - div(yearOfEra, 100) + dayOfYear;
    return era * 146097 + dayOfEra - 719468;
  },

  /// The date a day number names (Howard Hinnant's civil_from_days).
  fromDayNumber(dayNumber) {
    const z = dayNumber + 719468;
    const era = div(z >= 0 ? z : z - 146096, 146097);
    const dayOfEra = z - era * 146097;
    const yearOfEra = div(dayOfEra - div(dayOfEra, 1460) + div(dayOfEra, 36524) - div(dayOfEra, 146096), 365);
    const dayOfYear = dayOfEra - (365 * yearOfEra + div(yearOfEra, 4) - div(yearOfEra, 100));
    const shiftedMonth = div(5 * dayOfYear + 2, 153);
    const day = dayOfYear - div(153 * shiftedMonth + 2, 5) + 1;
    const month = shiftedMonth < 10 ? shiftedMonth + 3 : shiftedMonth - 9;
    return { year: yearOfEra + era * 400 + (month <= 2 ? 1 : 0), month, day };
  },

  /// 0 is Sunday, 6 is Saturday. 1 January 1970 was a Thursday.
  weekday(dayNumber) {
    return ((dayNumber % 7) + 11) % 7;
  },
};

/// When a practice began, on the clock where it happened, to the second: "2026-11-18T06:42:10+05:30",
/// or "2026-11-18T01:12:10Z" in UTC. Returns { year, month, day, hour, minute, second, offset, dayNumber,
/// instant }, offset in minutes ahead of UTC, or null when the text isn't one.
export function parsePracticeTime(text) {
  if (typeof text !== "string" || (text.length !== 20 && text.length !== 25)) return null;
  const digits = (start, count) => {
    let value = 0;
    for (let index = start; index < start + count; index += 1) {
      const code = text.charCodeAt(index);
      if (code < 48 || code > 57) return null;
      value = value * 10 + (code - 48);
    }
    return value;
  };
  if (text[4] !== "-" || text[7] !== "-" || text[10] !== "T" || text[13] !== ":" || text[16] !== ":") return null;
  const [year, month, day, hour, minute, second] = [[0, 4], [5, 2], [8, 2], [11, 2], [14, 2], [17, 2]]
    .map(([start, count]) => digits(start, count));
  if ([year, month, day, hour, minute, second].includes(null)) return null;
  if (!CivilDate.isValid(year, month, day) || hour > 23 || minute > 59 || second > 59) return null;
  let offset = 0;
  if (text.length === 20) {
    if (text[19] !== "Z") return null;
  } else {
    const hours = digits(20, 2);
    const minutes = digits(23, 2);
    if ((text[19] !== "+" && text[19] !== "-") || text[22] !== ":" || hours == null || minutes == null
        || hours > 14 || minutes > 59) return null;
    offset = (hours * 60 + minutes) * (text[19] === "-" ? -1 : 1);
  }
  return practiceTime(year, month, day, hour, minute, second, offset);
}

function practiceTime(year, month, day, hour, minute, second, offset) {
  const dayNumber = CivilDate.dayNumber(year, month, day);
  return Object.freeze({
    year, month, day, hour, minute, second, offset, dayNumber,
    /// Seconds since 1970 in UTC, which orders practices begun in different time zones.
    instant: dayNumber * 86400 + hour * 3600 + minute * 60 + second - offset * 60,
  });
}

/// A moment on this device's clock.
export function practiceTimeAt(moment = new Date()) {
  return practiceTime(moment.getFullYear(), moment.getMonth() + 1, moment.getDate(), moment.getHours(),
    moment.getMinutes(), moment.getSeconds(), -moment.getTimezoneOffset());
}

export function practiceTimeText(time) {
  const clock = `${String(time.year).padStart(4, "0")}-${pad2(time.month)}-${pad2(time.day)}T${pad2(time.hour)}:${pad2(time.minute)}:${pad2(time.second)}`;
  if (time.offset === 0) return `${clock}Z`;
  const size = Math.abs(time.offset);
  return `${clock}${time.offset < 0 ? "-" : "+"}${pad2(div(size, 60))}:${pad2(size % 60)}`;
}

/// Today's day number on this device's clock.
export function todayNumber(moment = new Date()) {
  return CivilDate.dayNumber(moment.getFullYear(), moment.getMonth() + 1, moment.getDate());
}

// MARK: Practices

/// A practice is kept once it has a minute of practice, or a whole cycle.
export const MINIMUM_SECONDS = 60;
const MAXIMUM_SECONDS = 10_000_000;
const TIMINGS = [PER_STEP, TOTAL, FREESTYLE];
const [MINIMUM_CYCLES, MAXIMUM_CYCLES] = SessionConfiguration.cycleRange;

const isCount = (value, high) => Number.isInteger(value) && value >= 0 && value <= high;

/// One practice, as kept in the history and written to backups: { id, start, seconds, cycles, planned,
/// timing, steps, device, time }, `time` being the parsed start. Null when any field is wrong.
export function makeRecord({ id, start, seconds, cycles, planned, timing, steps = null, device = null, manual = false }) {
  const time = parsePracticeTime(start);
  if (typeof id !== "string" || id.length < 1 || id.length > 100 || !time || !isCount(seconds, MAXIMUM_SECONDS)
      || !Number.isInteger(planned) || planned < MINIMUM_CYCLES || planned > MAXIMUM_CYCLES
      || !isCount(cycles, planned) || !TIMINGS.includes(timing)) return null;
  if (steps != null && (!Array.isArray(steps) || steps.length !== STAGES.length
      || !steps.every((value) => isCount(value, MAXIMUM_SECONDS)))) return null;
  if (device != null && (typeof device !== "string" || device.length < 1 || device.length > 40)) return null;
  if (typeof manual !== "boolean" || (manual && (cycles !== planned || seconds < 1 || seconds > 86400 || steps != null))) return null;
  return Object.freeze({ id, start, seconds, cycles, planned, timing, steps: steps && Object.freeze([...steps]), device, manual, time });
}

/// A completed practice elsewhere. Only its aggregate time is known; individual form times are not.
/// Freestyle keeps version-one backups compatible: no app timer was used for this session.
export function manuallyAddedRecord(id, start, seconds, cycles) {
  return makeRecord({ id, start, seconds, cycles, planned: cycles, timing: FREESTYLE, manual: true });
}

export const averageSecondsPerStep = record => record.manual && record.cycles > 0 ? record.seconds / (record.cycles * STAGES.length) : null;

/// The practice under way or just ended, as the engine has counted it.
export function recordFromEngine(id, start, engine, device) {
  const steps = STAGES.map((_, step) => Math.round(engine.stepSeconds.reduce((sum, cycle) => sum + cycle[step], 0)));
  return makeRecord({
    id, start: practiceTimeText(start), seconds: Math.round(engine.activeSeconds), cycles: engine.completedCycles,
    planned: engine.configuration.cycles, timing: engine.configuration.timing, steps, device,
  });
}

/// Whether the practice so far is worth keeping: a minute of practice, or a whole cycle.
export const isWorthKeeping = (engine) => engine.activeSeconds >= MINIMUM_SECONDS || engine.completedCycles >= 1;

/// A whole number, as JSON writes it: not a fraction, and not true or false.
const integer = (value) => (typeof value === "number" && Number.isInteger(value) && Math.abs(value) < 1e15 ? value : null);

/// One entry of a backup's "practices". Null when any field is wrong.
export function recordFromJSON(value) {
  if (typeof value !== "object" || value === null || Array.isArray(value)) return null;
  const seconds = integer(value.seconds);
  const cycles = integer(value.cycles);
  const planned = integer(value.planned);
  if (typeof value.id !== "string" || typeof value.start !== "string" || typeof value.timing !== "string"
      || seconds == null || cycles == null || planned == null) return null;
  let steps = null;
  if (value.steps != null) {
    if (!Array.isArray(value.steps)) return null;
    steps = value.steps.map(integer);
    if (steps.includes(null)) return null;
  }
  let device = null;
  if (value.device != null) {
    if (typeof value.device !== "string") return null;
    device = value.device;
  }
  if ("manual" in value && typeof value.manual !== "boolean") return null;
  return makeRecord({ id: value.id, start: value.start, seconds, cycles, planned, timing: value.timing, steps, device, manual: value.manual ?? false });
}

/// One line of JSON, its fields in a fixed order.
export function recordJSON(record) {
  const fields = { id: record.id, start: record.start, seconds: record.seconds, cycles: record.cycles,
    planned: record.planned, timing: record.timing };
  if (record.steps) fields.steps = record.steps;
  if (record.device != null) fields.device = record.device;
  if (record.manual) fields.manual = true;
  return JSON.stringify(fields);
}

export const isCompleted = (record) => record.cycles >= record.planned;

const isOrdered = (first, second) => (first.time.instant !== second.time.instant
  ? first.time.instant < second.time.instant
  : first.id < second.id);
const compare = (first, second) => (isOrdered(first, second) ? -1 : isOrdered(second, first) ? 1 : 0);

/// Why a file couldn't be read: "unreadable" (not JSON, or not an object), "notABackup", or "newerVersion".
export class HistoryReadError extends Error {
  constructor(kind, version = null) {
    super(kind);
    this.kind = kind;
    this.version = version;
  }
}

/// Every practice kept on this device, oldest first, each once.
export class PracticeHistory {
  /// What a backup file says it is, and the newest layout this version reads.
  static format = "swadarshan-chakra-history";
  static version = 1;

  constructor(records = []) {
    this.records = [];
    this.merge(records);
  }

  get isEmpty() { return this.records.length === 0; }

  /// Saves the practice under way, replacing what was kept of it before.
  upsert(record) {
    this.records = this.records.filter((kept) => kept.id !== record.id);
    const position = this.records.findIndex((kept) => isOrdered(record, kept));
    this.records.splice(position === -1 ? this.records.length : position, 0, record);
  }

  /// Adds practices this device doesn't have yet. A practice it has already is kept as it is, unless
  /// the other copy is the longer one: a practice saved partway and finished later.
  merge(incoming) {
    const result = { added: 0, updated: 0, unchanged: 0 };
    const index = new Map();
    this.records.forEach((record, position) => { if (!index.has(record.id)) index.set(record.id, position); });
    for (const record of incoming) {
      const position = index.get(record.id);
      if (position !== undefined) {
        if (record.seconds > this.records[position].seconds) {
          this.records[position] = record;
          result.updated += 1;
        } else {
          result.unchanged += 1;
        }
      } else {
        index.set(record.id, this.records.length);
        this.records.push(record);
        result.added += 1;
      }
    }
    if (result.added + result.updated > 0) this.records.sort(compare);
    return result;
  }

  recordsOn(day) { return this.records.filter((record) => record.time.dayNumber === day); }

  /// The backup file, or the history kept in this browser: a small JSON document, one practice per line.
  document(exported = null) {
    const lines = ["{", `  "format": "${PracticeHistory.format}",`, `  "version": ${PracticeHistory.version},`,
      '  "app": "Swadarshan Chakra",'];
    if (exported) lines.push(`  "exported": "${practiceTimeText(exported)}",`);
    if (this.records.length === 0) {
      lines.push('  "practices": []');
    } else {
      lines.push('  "practices": [');
      this.records.forEach((record, index) => {
        lines.push(`    ${recordJSON(record)}${index === this.records.length - 1 ? "" : ","}`);
      });
      lines.push("  ]");
    }
    lines.push("}");
    return `${lines.join("\n")}\n`;
  }

  /// What a backup's file name should be: "Swadarshan Chakra backup 2026-11-18.json".
  static backupName(day) {
    const { year, month, day: date } = CivilDate.fromDayNumber(day);
    return `Swadarshan Chakra backup ${String(year).padStart(4, "0")}-${pad2(month)}-${pad2(date)}.json`;
  }

  /// Reads a backup or history file. Practices that can't be read are left out and counted.
  static read(text) {
    let object;
    try { object = JSON.parse(text); } catch { throw new HistoryReadError("unreadable"); }
    if (typeof object !== "object" || object === null || Array.isArray(object)) throw new HistoryReadError("unreadable");
    if (object.format !== PracticeHistory.format || !Array.isArray(object.practices)) {
      throw new HistoryReadError("notABackup");
    }
    if (integer(object.version) == null || object.version < 1) throw new HistoryReadError("notABackup");
    if (object.version > PracticeHistory.version) throw new HistoryReadError("newerVersion", object.version);
    const records = object.practices.map(recordFromJSON).filter(Boolean);
    return { history: new PracticeHistory(records), skipped: object.practices.length - records.length };
  }
}

/// What an import did, in a sentence or two (PracticeHistory.Merge.summary).
export function importSummary({ added, updated, unchanged }, file, skipped) {
  const parts = [];
  if (added === 0 && updated === 0) {
    parts.push(`Everything in “${file}” was already here.`);
  } else {
    if (added > 0) parts.push(`Added ${HistoryText.count(added, "practice")} from “${file}”.`);
    if (updated > 0) parts.push(`Brought ${HistoryText.count(updated, "practice")} up to date${added > 0 ? "" : ` from “${file}”`}.`);
    if (unchanged > 0) parts.push(`${unchanged} ${unchanged === 1 ? "was" : "were"} already here.`);
  }
  if (skipped > 0) parts.push(`${skipped} couldn't be read and ${skipped === 1 ? "was" : "were"} left out.`);
  return parts.join(" ");
}

/// Why a file couldn't be imported (PracticeHistory.ReadError.message).
export function readErrorMessage(error, file) {
  if (error.kind === "notABackup") return `“${file}” isn't a Swadarshan Chakra backup.`;
  if (error.kind === "newerVersion") {
    return `“${file}” comes from a newer version of Swadarshan Chakra. Update this one to import it.`;
  }
  return `“${file}” couldn't be read. Choose a backup saved by Swadarshan Chakra.`;
}

// MARK: Insights (PracticeInsights.swift)

/// Parts of the day, by the hour a practice begins.
export const BANDS = ["lateNight", "earlyMorning", "morning", "afternoon", "evening", "night"];

export function bandOf(hour) {
  if (hour <= 3) return "lateNight";
  if (hour <= 6) return "earlyMorning";
  if (hour <= 11) return "morning";
  if (hour <= 16) return "afternoon";
  if (hour <= 20) return "evening";
  return "night";
}

const PHRASES = {
  lateNight: "late at night",
  earlyMorning: "in the early morning",
  morning: "in the morning",
  afternoon: "in the afternoon",
  evening: "in the evening",
  night: "at night",
};

const SUGGESTIONS = {
  earlyMorning: "Your early mornings are quiet. Amrit vela, before dawn, is a gentle time to begin.",
  morning: "Your mornings are quiet. A cycle before the day gets busy could set its tone.",
  afternoon: "Your afternoons are quiet. A short cycle after lunch could carry the calm through the day.",
  evening: "Your evenings are quiet. A cycle as the day winds down could help you settle.",
  night: "Your nights are quiet. A cycle before sleep could close the day gently.",
  lateNight: "Your nights are quiet. A cycle before sleep could close the day gently.",
};

const emptyTotals = () => ({ seconds: 0, practices: 0, cycles: 0 });

/// What the history says, as the journey screen shows it: totals, streaks, the trend over recent weeks,
/// and the hours of the week the practitioner tends to practice. `firstWeekday`: 0 is Sunday.
export class PracticeInsights {
  static weeksShown = 12;
  /// The hours of the week are read from the last twelve weeks.
  static rhythmDays = 84;

  constructor(history, today, firstWeekday) {
    this.today = today;
    this.firstWeekday = ((firstWeekday % 7) + 7) % 7;
    const days = new Map();
    const all = emptyTotals();
    const heat = Array.from({ length: 7 }, () => Array(24).fill(0));
    let rhythmPractices = 0;
    const amritVela = new Set();
    for (const record of history.records) {
      const day = record.time.dayNumber;
      if (!days.has(day)) days.set(day, emptyTotals());
      const totals = days.get(day);
      totals.seconds += record.seconds;
      totals.practices += 1;
      totals.cycles += record.cycles;
      all.seconds += record.seconds;
      all.practices += 1;
      all.cycles += record.cycles;
      if (day >= today - PracticeInsights.rhythmDays + 1 && day <= today) {
        heat[CivilDate.weekday(day)][record.time.hour] += record.seconds;
        rhythmPractices += 1;
      }
      if (day >= today - 29 && day <= today && (record.time.hour === 3 || record.time.hour === 4)) amritVela.add(day);
    }
    this.days = days;
    this.all = all;
    /// Seconds practiced in practices begun in each hour of each weekday, over the last twelve weeks:
    /// heat[weekday][hour], Sunday first.
    this.heat = heat;
    this.rhythmPractices = rhythmPractices;
    /// Mornings of the last 30 with a practice begun between 3 and 5 am.
    this.amritVelaMornings = amritVela.size;
    this.firstDay = history.records.length
      ? history.records.reduce((first, record) => Math.min(first, record.time.dayNumber), Infinity)
      : null;
    this.activeDays = days.size;
    this.todayTotals = days.get(today) ?? emptyTotals();

    const span = (from, to) => {
      let sum = 0;
      for (let day = from; day <= to; day += 1) sum += days.get(day)?.seconds ?? 0;
      return sum;
    };
    this.last7 = span(today - 6, today);
    this.last7Cycles = Array.from({ length: 7 }, (_, offset) => days.get(today - offset)?.cycles ?? 0)
      .reduce((sum, count) => sum + count, 0);
    this.previous7 = span(today - 13, today - 7);
    this.last30 = span(today - 29, today);
    this.previous30 = span(today - 59, today - 30);
    this.recent28 = span(today - 27, today);
    this.previous28 = span(today - 55, today - 28);
    if (this.recent28 === 0 && this.previous28 === 0) this.trend = "resting";
    else if (this.previous28 === 0) this.trend = "beginning";
    else {
      const change = (this.recent28 - this.previous28) / this.previous28;
      this.trend = change > 0.1 ? "rising" : change < -0.1 ? "easing" : "steady";
    }

    // A streak lives on through today until the day is over.
    let streak = 0;
    for (let day = days.has(today) ? today : today - 1; days.has(day); day -= 1) streak += 1;
    this.currentStreak = streak;
    let best = 0;
    let run = 0;
    let previous = null;
    for (const active of [...days.keys()].sort((a, b) => a - b)) {
      run = previous != null && active === previous + 1 ? run + 1 : 1;
      best = Math.max(best, run);
      previous = active;
    }
    this.bestStreak = best;

    const thisWeek = this.weekStart(today);
    /// The first day of each of the last twelve weeks, oldest first; the last is this week.
    this.weekStarts = Array.from({ length: PracticeInsights.weeksShown },
      (_, index) => thisWeek - 7 * (PracticeInsights.weeksShown - 1 - index));
    this.weekTotals = this.weekStarts.map((start) => span(start, start + 6));

    // The part of the day with the most practice, and the waking part with the least.
    const bands = Object.fromEntries(BANDS.map((band) => [band, 0]));
    for (const row of heat) row.forEach((seconds, hour) => { bands[bandOf(hour)] += seconds; });
    this.peak = null;
    this.quiet = null;
    this.busiestWeekday = null;
    this.quietIsQuiet = false;
    if (rhythmPractices >= 3) {
      let peak = "lateNight";
      for (const band of BANDS) if (bands[band] > bands[peak]) peak = band;
      let quiet = null;
      for (const band of ["afternoon", "evening", "morning", "earlyMorning", "night"]) {
        if (band !== peak && (quiet == null || bands[band] < bands[quiet])) quiet = band;
      }
      // The weekday with the most practice in that part of the day.
      const peakHours = Array.from({ length: 24 }, (_, hour) => hour).filter((hour) => bandOf(hour) === peak);
      const weekdayTotals = heat.map((row) => peakHours.reduce((sum, hour) => sum + row[hour], 0));
      let busiest = 0;
      for (let weekday = 1; weekday < 7; weekday += 1) if (weekdayTotals[weekday] > weekdayTotals[busiest]) busiest = weekday;
      this.peak = peak;
      this.quiet = quiet;
      this.busiestWeekday = busiest;
      this.quietIsQuiet = quiet != null && bands[quiet] * 100 <= bands[peak] * 15;
    }

    // The 90th percentile of the last year's days with practice, and never under a minute.
    const year = [...days].filter(([day]) => day >= today - 364 && day <= today).map(([, totals]) => totals.seconds)
      .sort((a, b) => a - b);
    /// The daily time that shows in full gold: most days of the last year with practice reach it.
    this.fullDay = year.length ? Math.max(MINIMUM_SECONDS, year[div(9 * year.length + 9, 10) - 1]) : 0;
    this.mostHeat = Math.max(0, ...heat.flat());
  }

  totals(day) { return this.days.get(day) ?? emptyTotals(); }

  /// How brightly a day shows on the calendar, from 0 (no practice) to 4 (a full day).
  level(day) {
    const { seconds } = this.totals(day);
    if (seconds <= 0 || this.fullDay <= 0) return 0;
    return seconds >= this.fullDay ? 4 : 1 + div(3 * seconds, this.fullDay);
  }

  /// How brightly an hour of the week shows, from 0 to 4 (the hour with the most practice).
  heatLevel(weekday, hour) {
    const seconds = this.heat[weekday][hour];
    if (seconds <= 0 || this.mostHeat <= 0) return 0;
    return 1 + div(3 * seconds, this.mostHeat);
  }

  /// The day this week begins.
  weekStart(day) { return day - ((CivilDate.weekday(day) - this.firstWeekday + 7) % 7); }

  /// The seven weekdays in calendar order, starting with the first.
  get weekdayOrder() { return Array.from({ length: 7 }, (_, index) => (this.firstWeekday + index) % 7); }

  // MARK: Words

  get todayDetail() {
    if (this.todayTotals.practices === 0) return "Not yet today";
    return `${HistoryText.count(this.todayTotals.practices, "practice")} · ${HistoryText.count(this.todayTotals.cycles, "cycle")}`;
  }

  get weekComparison() { return compareSpans(this.last7, this.previous7, "7 days"); }
  get monthComparison() { return compareSpans(this.last30, this.previous30, "30 days"); }

  get streakValue() { return HistoryText.count(this.currentStreak, "day"); }
  get streakDetail() {
    if (this.currentStreak === 0) {
      return this.bestStreak > 0 ? `Best: ${HistoryText.count(this.bestStreak, "day")}` : "Practice on days in a row";
    }
    if (this.todayTotals.practices === 0) return "Practice today to keep it";
    return this.currentStreak >= this.bestStreak ? "Your longest yet" : `Best: ${HistoryText.count(this.bestStreak, "day")}`;
  }

  /// Total practice time divided by completed cycles in practices begun today or in the six
  /// preceding calendar days. Includes manual and ended-early practices; no cycles means no average.
  get averageCycleSeconds() {
    return this.last7Cycles > 0 ? Math.round(this.last7 / this.last7Cycles) : null;
  }

  get trendTitle() {
    return { rising: "Rising", steady: "Steady", easing: "Easing off", beginning: "Beginning", resting: "Resting" }[this.trend];
  }

  get trendDetail() {
    const recent = HistoryText.minutes(this.recent28);
    if (this.trend === "rising" || this.trend === "easing") {
      const change = Math.abs((this.recent28 - this.previous28) / this.previous28);
      return `${recent} in the last four weeks, ${this.trend === "rising" ? "up" : "down"} ${Math.round(change * 100)}% on the four before.`;
    }
    if (this.trend === "steady") return `${recent} in the last four weeks, much as in the four before.`;
    if (this.trend === "beginning") return `${recent} in the last four weeks, your first. Keep going, and your trend will show here.`;
    return "No practice in the last eight weeks. A single cycle begins again.";
  }

  /// A few plain sentences about when the practitioner practices, and when they might.
  get rhythmNotes() {
    if (this.peak == null || this.busiestWeekday == null) {
      return ["Practice a few more times, and the hours you favor will show here."];
    }
    const notes = [`You practice most ${PHRASES[this.peak]}, especially on ${HistoryText.weekdays[this.busiestWeekday]}s.`];
    notes.push(this.quiet != null && this.quietIsQuiet ? SUGGESTIONS[this.quiet] : "Your practice is spread across the day.");
    if (this.amritVelaMornings > 0) notes.push(`Amrit vela, 3 to 5 am: ${this.amritVelaMornings} of the last 30 mornings.`);
    return notes;
  }
}

/// How a total compares with the same span just before it: { direction: "up" | "down" | "same" | "none", text }.
function compareSpans(current, previous, span) {
  if (previous === 0) {
    return current === 0
      ? { direction: "none", text: `None in the ${span} before either` }
      : { direction: "up", text: `Up from none in the ${span} before` };
  }
  const change = Math.round((Math.abs(current - previous) / previous) * 100);
  if (change === 0) return { direction: "same", text: `The same as the ${span} before` };
  return { direction: current > previous ? "up" : "down", text: `${current > previous ? "Up" : "Down"} ${change}% on the ${span} before` };
}

/// Words and numbers for the history, the same on the Mac and on the web.
export const HistoryText = {
  months: ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October",
    "November", "December"],
  /// Sunday first.
  weekdays: ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"],

  /// Whole minutes: "45 min", "2 hr 10 min", "2 hr"; "< 1 min" for a few seconds, "0 min" for none.
  minutes(seconds) {
    const minutes = Math.round(Math.max(0, seconds) / 60);
    if (minutes === 0) return seconds > 0 ? "< 1 min" : "0 min";
    if (minutes < 60) return `${minutes} min`;
    return minutes % 60 === 0 ? `${div(minutes, 60)} hr` : `${div(minutes, 60)} hr ${minutes % 60} min`;
  },

  /// The shortest form, for a calendar day beside its cycles: "45m", "2h10", "2h"; "<1m" for a few
  /// seconds; empty for none.
  compact(seconds) {
    const minutes = Math.round(Math.max(0, seconds) / 60);
    if (minutes === 0) return seconds > 0 ? "<1m" : "";
    if (minutes < 60) return `${minutes}m`;
    return minutes % 60 === 0 ? `${div(minutes, 60)}h` : `${div(minutes, 60)}h${String(minutes % 60).padStart(2, "0")}`;
  },

  count(number, singular) {
    return `${number} ${singular}${number === 1 ? "" : "s"}`;
  },

  /// "18 November 2026"
  date(day) {
    const { year, month, day: date } = CivilDate.fromDayNumber(day);
    return `${date} ${HistoryText.months[month - 1]} ${year}`;
  },

  /// "Tuesday, 18 November"
  dayTitle(day) {
    const { month, day: date } = CivilDate.fromDayNumber(day);
    return `${HistoryText.weekdays[CivilDate.weekday(day)]}, ${date} ${HistoryText.months[month - 1]}`;
  },

  /// "18 Nov"
  shortDate(day) {
    const { month, day: date } = CivilDate.fromDayNumber(day);
    return `${date} ${HistoryText.months[month - 1].slice(0, 3)}`;
  },

  /// "6:42 am"
  time(hour, minute) {
    return `${hour % 12 === 0 ? 12 : hour % 12}:${pad2(minute)} ${hour < 12 ? "am" : "pm"}`;
  },

  /// The marks along the hours of the day: "12a", "3a", … "9p".
  hourMark(hour) {
    return `${hour % 12 === 0 ? 12 : hour % 12}${hour < 12 ? "a" : "p"}`;
  },
};
