// The practice logic, ported from Sources/MeditationCore so the web version behaves exactly like the
// Mac app. Keep the two in step: Tests/web/engine-checks.mjs mirrors the Swift core checks.

/// The owner's five pictures, in order.
export const STAGES = Object.freeze([
  { id: 1, title: "बीज रूप", context: "परमधाम में", transliteration: "Beej roop paramdham me" },
  { id: 2, title: "विश्व महाराजन", context: "सतयुग में", transliteration: "Vishwa Maharajan satyug me" },
  { id: 3, title: "पूज्य स्वरूप", context: "द्वापर युग में", transliteration: "Pujya Swaroop dwapar yug me" },
  { id: 4, title: "परम पवित्र ब्राह्मण", context: "संगम युग में", transliteration: "Param Pavitra Brahmin Sangam Yug me" },
  { id: 5, title: "फरिश्ता स्वरूप", context: "", transliteration: "Farishta swaroop" },
].map((stage) => Object.freeze(stage)));

export const stageLabel = (stage) => (stage.context ? `${stage.title} — ${stage.context}` : stage.title);

/// How time is entered: for one step, or for the whole practice, shared equally by every step.
export const PER_STEP = "perStep";
export const TOTAL = "total";

const within = (value, [low, high]) => Number.isInteger(value) && value >= low && value <= high;

export class ValidationError extends Error {}

export class SessionConfiguration {
  static cycleRange = [1, 108];
  static secondRange = [0, 59];
  /// Seconds for one step, as entered in per-step mode.
  static durationRange = [1, 7200];
  /// Ten hours. With one cycle this is exactly the two-hour per-step maximum for each step.
  static maximumTotalSeconds = 36000;

  static minuteRange(timing) {
    return timing === PER_STEP ? [0, 120] : [0, 600];
  }

  constructor(cycles, timing, minutes, seconds = 0) {
    if (!within(cycles, SessionConfiguration.cycleRange)) throw new ValidationError("cycles");
    if (!within(minutes, SessionConfiguration.minuteRange(timing))) throw new ValidationError("minutes");
    if (!within(seconds, SessionConfiguration.secondRange)) throw new ValidationError("seconds");
    const entered = minutes * 60 + seconds;
    if (timing === PER_STEP) {
      if (!within(entered, SessionConfiguration.durationRange)) throw new ValidationError("duration");
    } else if (timing === TOTAL) {
      // At least one second for every step, and no more than the ten-hour total.
      if (entered < cycles * STAGES.length || entered > SessionConfiguration.maximumTotalSeconds) {
        throw new ValidationError("duration");
      }
    } else {
      throw new ValidationError("timing");
    }
    this.cycles = cycles;
    this.timing = timing;
    /// Whole seconds as entered: one step's time, or the time for all cycles together.
    this.enteredSeconds = entered;
    Object.freeze(this);
  }

  /// The configuration, or null when the values can't make a practice.
  static make(cycles, timing, minutes, seconds = 0) {
    try {
      return new SessionConfiguration(cycles, timing, minutes, seconds);
    } catch {
      return null;
    }
  }

  get stepCount() { return this.cycles * STAGES.length; }
  get enteredMinutes() { return Math.floor(this.enteredSeconds / 60); }
  get enteredSecondsComponent() { return this.enteredSeconds % 60; }

  /// Equal for every step. A shared total may divide into fractions of a second.
  get secondsPerStage() {
    return this.timing === PER_STEP ? this.enteredSeconds : this.enteredSeconds / this.stepCount;
  }

  get secondsPerCycle() {
    return this.timing === PER_STEP ? this.secondsPerStage * STAGES.length : this.enteredSeconds / this.cycles;
  }

  get plannedSeconds() {
    return this.timing === PER_STEP ? this.enteredSeconds * this.stepCount : this.enteredSeconds;
  }

  /// The same practice, entered the other way. A total that does not divide evenly rounds each
  /// step to the nearest second; a per-step practice longer than ten hours becomes the ten-hour total.
  expressed(timing) {
    if (timing === this.timing) return this;
    const seconds = timing === TOTAL
      ? Math.min(this.enteredSeconds * this.stepCount, SessionConfiguration.maximumTotalSeconds)
      : Math.max(1, Math.round(this.secondsPerStage));
    return new SessionConfiguration(this.cycles, timing, Math.floor(seconds / 60), seconds % 60);
  }

  /// ASCII digits only: a decimal, sign, blank, or embedded whitespace is not a whole number.
  static integer(text, range) {
    if (typeof text !== "string" || !/^[0-9]+$/.test(text)) return null;
    const value = Number(text);
    return within(value, range) ? value : null;
  }

  static standard = new SessionConfiguration(1, PER_STEP, 1, 0);
}

const pad = (value) => String(value).padStart(2, "0");

function clock(seconds) {
  if (seconds >= 3600) {
    return `${Math.floor(seconds / 3600)}:${pad(Math.floor(seconds / 60) % 60)}:${pad(seconds % 60)}`;
  }
  return `${pad(Math.floor(seconds / 60))}:${pad(seconds % 60)}`;
}

export const TimeText = {
  countdown(seconds) {
    return clock(Math.ceil(Math.max(0, seconds)));
  },

  elapsed(seconds) {
    // A millisecond of tolerance keeps floating-point sums of a full 10:00 from reading 09:59.
    return clock(Math.floor(Math.max(0, seconds) + 0.001));
  },

  duration(seconds) {
    const whole = Math.trunc(Math.max(0, seconds));
    if (whole < 60) return `${whole} sec`;
    const minutes = Math.floor(whole / 60);
    const remainder = whole % 60;
    if (minutes < 60) return remainder === 0 ? `${minutes} min` : `${minutes} min ${remainder} sec`;
    const parts = [`${Math.floor(minutes / 60)} hr`];
    if (minutes % 60 > 0) parts.push(`${minutes % 60} min`);
    if (remainder > 0) parts.push(`${remainder} sec`);
    return parts.join(" ");
  },

  /// Rounded to the nearest second, marked "≈" when a shared total does not divide evenly.
  approximateDuration(seconds) {
    const rounded = Math.round(seconds);
    const text = TimeText.duration(rounded);
    return Math.abs(seconds - rounded) < 0.0005 ? text : `≈ ${text}`;
  },
};

/// A deterministic state machine. All timestamps are seconds from the same monotonic clock.
export class SessionEngine {
  /// Every cycle opens with a short "Cycle N" title card. It is not practice time: the first
  /// step's countdown starts only when the card ends, so no step is ever shortened by it.
  static standardIntroduction = 3;
  /// Coalesce a physical key press and a timer expiration delivered at the same boundary.
  static boundaryTolerance = 0.15;

  constructor(introductionDuration = SessionEngine.standardIntroduction) {
    this.introductionDuration = Math.max(0, introductionDuration);
    this.reset();
  }

  /// "ready", "running", "paused", "confirming", or "complete".
  reset() {
    this.phase = "ready";
    this.configuration = SessionConfiguration.standard;
    this.stageIndex = 0;
    this.completedCycles = 0;
    this.remainingSeconds = 60;
    this.introductionRemaining = 0;
    this.activeSeconds = 0;
    /// "restart", "end", or null.
    this.pendingConfirmation = null;
    this.transitionCount = 0;
    this.lastSample = 0;
    this.stageStartedAt = 0;
    this.lastAutomaticTransition = null;
    this.resumeOnCancel = false;
  }

  get currentStage() { return STAGES[this.stageIndex]; }
  get currentCycle() { return Math.min(this.completedCycles + 1, this.configuration.cycles); }
  get isIntroducingCycle() { return this.phase === "running" && this.introductionRemaining > 0; }

  begin(configuration, now) {
    this.reset();
    this.configuration = configuration;
    this.remainingSeconds = configuration.secondsPerStage;
    this.introductionRemaining = this.introductionDuration;
    this.lastSample = now;
    this.stageStartedAt = now;
    this.phase = "running";
  }

  /// One callback can leave at most one stage; a new stage always starts with its full time.
  /// A long unobserved gap is treated as absence, not permission to race through the artwork.
  tick(now, maximumGap = null) {
    if (this.phase !== "running") return false;
    if (maximumGap != null && now - this.lastSample > maximumGap) {
      this.pauseAtLastSample();
      return false;
    }
    if (this.introductionRemaining > 0) {
      this.introductionRemaining = Math.max(0, this.introductionRemaining - Math.max(0, now - this.lastSample));
      this.lastSample = Math.max(this.lastSample, now);
      if (this.introductionRemaining !== 0) return false;
      // The card has ended; the cycle's first step starts now with its full time.
      this.#restartClock(now, true);
      return true;
    }
    this.#accrue(now);
    if (this.remainingSeconds <= 0) {
      this.#advance(now, true);
      return true;
    }
    return false;
  }

  nextStage(now, { eventTime = now, isRepeat = false, maximumGap = null } = {}) {
    if (this.phase !== "running" || isRepeat) return false;
    // A queued key event belonging to a previous stage/session must not affect the new one.
    if (eventTime < this.stageStartedAt) return false;
    if (this.lastAutomaticTransition != null
        && eventTime <= this.lastAutomaticTransition + SessionEngine.boundaryTolerance) return false;
    // If expiration and this key press coincide, expiration consumes this single transition.
    if (this.tick(now, maximumGap)) return true;
    if (this.phase !== "running") return false;
    if (this.introductionRemaining > 0) {
      // Space on a title card begins that cycle's first step immediately, with its full time.
      this.introductionRemaining = 0;
      this.#restartClock(now, false);
      return true;
    }
    this.#advance(now, false);
    return true;
  }

  pause(now) {
    if (this.phase === "confirming") {
      this.resumeOnCancel = false;
      return;
    }
    if (this.phase !== "running") return;
    if (this.introductionRemaining > 0) {
      // Pausing on a title card begins its cycle; the first step waits with its full time.
      this.introductionRemaining = 0;
    } else {
      // Pausing never traverses a stage, even if its deadline has just passed.
      this.#accrue(now);
    }
    this.phase = "paused";
  }

  pauseAtLastSample() {
    if (this.phase === "confirming") this.resumeOnCancel = false;
    if (this.phase === "running") {
      this.introductionRemaining = 0;
      this.phase = "paused";
    }
  }

  resume(now) {
    if (this.phase !== "paused") return;
    this.lastSample = now;
    // Reject events queued while the page was hidden or the session was paused.
    this.stageStartedAt = now;
    this.lastAutomaticTransition = null;
    this.phase = "running";
  }

  requestConfirmation(action, now) {
    if (this.phase !== "running" && this.phase !== "paused") return;
    const wasRunning = this.phase === "running";
    this.pause(now);
    this.resumeOnCancel = wasRunning;
    this.pendingConfirmation = action;
    this.phase = "confirming";
  }

  cancelConfirmation(now) {
    if (this.phase !== "confirming") return;
    const shouldResume = this.resumeOnCancel;
    this.pendingConfirmation = null;
    this.resumeOnCancel = false;
    this.phase = "paused";
    if (shouldResume) this.resume(now);
  }

  /// Returns the confirmed action, or null.
  confirm(now) {
    if (this.phase !== "confirming" || this.pendingConfirmation == null) return null;
    const action = this.pendingConfirmation;
    if (action === "restart") {
      this.begin(this.configuration, now);
    } else {
      this.reset();
    }
    return action;
  }

  #accrue(now) {
    const delta = Math.max(0, now - this.lastSample);
    const practiced = Math.min(this.remainingSeconds, delta);
    this.activeSeconds += practiced;
    this.remainingSeconds = Math.max(0, this.remainingSeconds - practiced);
    this.lastSample = Math.max(this.lastSample, now);
  }

  #advance(now, automatic) {
    this.transitionCount += 1;
    if (this.stageIndex === STAGES.length - 1) {
      this.completedCycles += 1;
      if (this.completedCycles === this.configuration.cycles) {
        this.remainingSeconds = 0;
        this.phase = "complete";
        return;
      }
      this.stageIndex = 0;
      this.introductionRemaining = this.introductionDuration;
    } else {
      this.stageIndex += 1;
    }
    this.remainingSeconds = this.configuration.secondsPerStage;
    this.#restartClock(now, automatic);
  }

  #restartClock(now, automatic) {
    this.lastSample = now;
    this.stageStartedAt = now;
    this.lastAutomaticTransition = automatic ? now : null;
  }
}

/// Saved settings. `read(key)` returns a string or null.
export function loadPreferences(read) {
  const integer = (key) => {
    const value = Number.parseInt(read(key) ?? "", 10);
    return Number.isFinite(value) ? value : 0;
  };
  const savedCycles = integer("cycles");
  const cycles = within(savedCycles, SessionConfiguration.cycleRange) ? savedCycles : 1;
  if (read("timingMode") === TOTAL) {
    const total = integer("totalDurationSeconds");
    const configuration = SessionConfiguration.make(cycles, TOTAL, Math.floor(total / 60), total % 60);
    if (configuration) return configuration;
  }
  const savedDuration = integer("stepDurationSeconds");
  const duration = within(savedDuration, SessionConfiguration.durationRange)
    ? savedDuration
    : SessionConfiguration.standard.enteredSeconds;
  return new SessionConfiguration(cycles, PER_STEP, Math.floor(duration / 60), duration % 60);
}

/// `write(key, value)` stores one setting.
export function savePreferences(configuration, write) {
  write("cycles", String(configuration.cycles));
  write("timingMode", configuration.timing);
  write(configuration.timing === PER_STEP ? "stepDurationSeconds" : "totalDurationSeconds",
    String(configuration.enteredSeconds));
}
