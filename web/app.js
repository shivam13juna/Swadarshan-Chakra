// Swadarshan Chakra in the browser. The practice logic lives in engine.js (a port of
// MeditationCore); this file mirrors the Mac app's SessionModel, its SwiftUI views, and
// AppMain's keyboard and lifecycle handling.
import {
  STAGES, stageLabel, PER_STEP, TOTAL, FREESTYLE, SessionConfiguration, SessionEngine, TimeText,
  loadPreferences, loadTimedPreferences, savePreferences,
} from "./engine.js";
import {
  CivilDate, PracticeHistory, PracticeInsights, HistoryReadError, HistoryText, practiceTimeAt, todayNumber,
  recordFromEngine, isWorthKeeping, isCompleted, importSummary, readErrorMessage,
} from "./history.js";

const MAXIMUM_UNOBSERVED_GAP = 2.5;
const TICK_MILLISECONDS = 200;
const PAUSED = "Your practice is paused.";
const AWAY = "Paused while you were away.";

const now = () => performance.now() / 1000;
const pad2 = (value) => String(value).padStart(2, "0");
const byId = (id) => document.getElementById(id);
const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
const isMac = /Mac|iPhone|iPad|iPod/i.test(navigator.userAgentData?.platform || navigator.platform || "");

function make(tag, className = "", text = null) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text != null) node.textContent = text;
  return node;
}

function setText(node, text) {
  if (node.textContent !== text) node.textContent = text;
}

const storage = {
  read(key) {
    try { return window.localStorage.getItem(key); } catch { return null; }
  },
  write(key, value) {
    try { window.localStorage.setItem(key, value); } catch { /* Settings then last for this visit only. */ }
  },
};

// MARK: Model (SessionModel.swift)

const engine = new SessionEngine();
const saved = loadPreferences(storage.read);
// With freestyle chosen, the time fields still hold the time last entered.
const savedTime = saved.isTimed ? saved : loadTimedPreferences(storage.read);
const model = {
  cyclesText: String(saved.cycles),
  /// Per step or for the whole practice, as the minutes and seconds are entered, or freestyle, with no timer.
  timingMode: saved.timing,
  /// How the minutes and seconds are entered: per step or in total. Freestyle leaves them as they are,
  /// so choosing a timer again brings the same time back.
  fieldTiming: savedTime.timing,
  minutesText: String(savedTime.enteredMinutes),
  secondsText: pad2(savedTime.enteredSecondsComponent),
  pauseReason: PAUSED,
  opensInFullScreen: storage.read("opensInFullScreen") !== "false",
  /// Whether each step shows the countdown bar along its bottom edge. Freestyle has no countdown to show.
  showsCountdownBar: storage.read("showsCountdownBar") !== "false",
  /// What the last export or import did, shown with the journey's backup buttons.
  backupMessage: null,
};

// MARK: History (SessionModel's history, PracticeStore.swift)

/// Every practice kept in this browser, in the backup file's format.
const HISTORY_KEY = "practiceHistory";
/// The locale's first day of the week (0 is Sunday); Monday where the browser doesn't say.
const firstWeekday = (() => {
  try {
    const locale = new Intl.Locale(navigator.language || "en");
    const info = locale.getWeekInfo?.() ?? locale.weekInfo;
    if (Number.isInteger(info?.firstDay)) return info.firstDay % 7;
  } catch { /* Monday, then. */ }
  return 1;
})();

function readHistory() {
  const text = storage.read(HISTORY_KEY);
  if (text == null) return null;
  try {
    return PracticeHistory.read(text).history;
  } catch {
    // Never write over a history that can't be read: set it aside and begin a new one.
    storage.write(`${HISTORY_KEY}.unreadable`, text);
    storage.write(HISTORY_KEY, new PracticeHistory().document());
    return new PracticeHistory();
  }
}

let history = readHistory() ?? new PracticeHistory();
let insights = new PracticeInsights(history, todayNumber(), firstWeekday);
const refreshInsights = () => { insights = new PracticeInsights(history, todayNumber(), firstWeekday); };

/// Changes the history as it's stored now, so a practice saved in another tab is never written over.
/// Where the browser keeps nothing, the history lasts for this visit.
function storeHistory(change) {
  const latest = readHistory() ?? history;
  const result = change(latest);
  history = latest;
  storage.write(HISTORY_KEY, history.document());
  refreshInsights();
  return result;
}

/// The practice under way: its own id, and when it began on this device's clock.
let practice = null;
/// Its steps, cycles, and pauses when it was last saved.
let savedState = null;

function startPractice() {
  const id = window.crypto?.randomUUID?.() ?? `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 12)}`;
  practice = { id, start: practiceTimeAt(new Date()) };
  savedState = null;
}

/// Each practice is saved as it goes, at every step, cycle, and pause, so little is lost if the page
/// goes; and once more as it ends, however it ends. It is kept once it has a minute of practice, or a
/// whole cycle. `force` saves the time so far even when nothing else has changed.
function savePractice({ ending = false, force = false } = {}) {
  if (!practice) return;
  const current = practice;
  const finished = ending || engine.phase === "complete";
  const state = `${engine.transitionCount}/${engine.completedCycles}/${engine.phase === "running" ? 1 : 0}`;
  if (finished) {
    practice = null;
    savedState = null;
  }
  if (!isWorthKeeping(engine) || (!finished && !force && state === savedState)) return;
  const record = recordFromEngine(current.id, current.start, engine, "web");
  if (!record) return;
  if (!finished) savedState = state;
  storeHistory((latest) => latest.upsert(record));
}

const cycles = () => SessionConfiguration.integer(model.cyclesText, SessionConfiguration.cycleRange);
const cycleTitle = () => `Cycle ${engine.currentCycle} of ${engine.configuration.cycles}`;

function configuration() {
  if (model.timingMode !== FREESTYLE) return enteredTime();
  const cycleCount = cycles();
  return cycleCount == null ? null : SessionConfiguration.freestyle(cycleCount);
}

/// The time as the fields hold it, per step or in total, even while freestyle is chosen.
function enteredTime() {
  const cycleCount = cycles();
  const minutes = SessionConfiguration.integer(model.minutesText, SessionConfiguration.minuteRange(model.fieldTiming));
  const seconds = SessionConfiguration.integer(model.secondsText, SessionConfiguration.secondRange);
  if (cycleCount == null || minutes == null || seconds == null) return null;
  return SessionConfiguration.make(cycleCount, model.fieldTiming, minutes, seconds);
}

/// Why the entered time cannot be used, or null. An invalid cycle count is reported by its own field.
function durationProblem() {
  if (model.timingMode === FREESTYLE) return null;
  const minuteRange = SessionConfiguration.minuteRange(model.timingMode);
  const minutes = SessionConfiguration.integer(model.minutesText, minuteRange);
  if (minutes == null) return `Enter whole minutes from 0 to ${minuteRange[1]}.`;
  const seconds = SessionConfiguration.integer(model.secondsText, SessionConfiguration.secondRange);
  if (seconds == null) return "Enter whole seconds from 0 to 59.";
  const entered = minutes * 60 + seconds;
  if (model.timingMode === PER_STEP) {
    const [low, high] = SessionConfiguration.durationRange;
    return entered >= low && entered <= high ? null : "Choose 1 second to 120 minutes per step.";
  }
  if (entered > SessionConfiguration.maximumTotalSeconds) return "Choose up to 600 minutes in total.";
  const cycleCount = cycles();
  if (cycleCount == null) return entered === 0 ? "Allow at least 1 second for each step." : null;
  const minimum = cycleCount * STAGES.length;
  if (entered >= minimum) return null;
  return `For ${cycleCount} ${cycleCount === 1 ? "cycle" : "cycles"}, allow at least ${TimeText.duration(minimum)} (1 sec per step).`;
}

/// Switching only changes how the time is entered: the fields are converted so the practice stays the
/// same. Freestyle leaves them as they are, so choosing a timer again brings the same time back.
function setTimingMode(mode) {
  if (mode === model.timingMode) return;
  if (mode !== FREESTYLE) {
    const converted = mode === model.fieldTiming ? null : enteredTime()?.expressed(mode);
    if (converted) {
      model.minutesText = String(converted.enteredMinutes);
      model.secondsText = pad2(converted.enteredSecondsComponent);
    }
    model.fieldTiming = mode;
  }
  model.timingMode = mode;
}

// MARK: Actions

function begin() {
  const chosen = configuration();
  if (!chosen || engine.phase !== "ready") return;
  // Freestyle saves the time fields too, for when a timer is chosen again.
  const time = chosen.isTimed ? null : enteredTime();
  if (time) savePreferences(time, storage.write);
  savePreferences(chosen, storage.write);
  preloadArtwork();
  if (model.opensInFullScreen) enterFullScreen();
  model.backupMessage = null;
  engine.begin(chosen, now());
  startPractice();
  update();
  announce(`Practice started. ${cycleTitle()}`);
}

function nextStage(eventTime = now(), isRepeat = false) {
  const wasRunning = engine.phase === "running";
  const transitioned = engine.nextStage(now(), { eventTime, isRepeat, maximumGap: MAXIMUM_UNOBSERVED_GAP });
  if (wasRunning && engine.phase === "paused") model.pauseReason = AWAY;
  update();
  if (transitioned) announceStage();
}

function pause(reason = PAUSED) {
  if (engine.phase === "running" || engine.phase === "confirming") model.pauseReason = reason;
  engine.pause(now());
  update();
}

/// Whether the practitioner is with the practice: the page is in front and has focus. Leaving pauses a
/// running practice; only timed modes count pauses while they're here (SessionModel.setPresent).
function setPresent(present) {
  const wasActive = engine.phase === "running" || engine.phase === "confirming";
  engine.setPresent(present, now());
  if (!present && wasActive) model.pauseReason = AWAY;
  update();
}

function resume() {
  engine.resume(now());
  update();
}

function request(action) {
  engine.requestConfirmation(action, now());
  update();
}

function cancelConfirmation() {
  engine.cancelConfirmation(now());
  update();
}

function confirm() {
  // Restarting and ending both end this practice; what was practiced is kept.
  if (engine.phase === "confirming") savePractice({ ending: true });
  if (engine.confirm(now()) === "restart") startPractice();
  update();
}

function practiceAgain() {
  savePractice({ ending: true });
  engine.reset();
  update();
}

/// Esc pauses a running practice and, pressed again, resumes it with the same time left
/// (SessionModel.escape). It also cancels a confirmation.
function escape() {
  if (engine.phase === "running") pause();
  else if (engine.phase === "paused") resume();
  else if (engine.phase === "confirming") cancelConfirmation();
}

/// The journey, below setup and beside a finished practice's time: scrolls to it (SessionModel.showJourney).
/// Not during a practice.
function showJourney() {
  if (engine.phase !== "ready" && engine.phase !== "complete") return;
  const behavior = reducedMotion.matches ? "auto" : "smooth";
  // On completion the journey scrolls on its own, except on a phone, where the page does.
  if (engine.phase === "complete" && getComputedStyle(journey).overflowY !== "visible") journey.scrollTo({ top: 0, behavior });
  else journey.scrollIntoView({ block: "start", behavior });
  journeyTitle.focus({ preventScroll: true });
}

/// Downloads every practice kept in this browser, to import on another device or in the Mac app.
function exportHistory() {
  const name = PracticeHistory.backupName(todayNumber());
  const url = URL.createObjectURL(new Blob([history.document(practiceTimeAt(new Date()))], { type: "application/json" }));
  const link = make("a");
  link.href = url;
  link.download = name;
  link.hidden = true;
  document.body.append(link);
  link.click();
  link.remove();
  window.setTimeout(() => URL.revokeObjectURL(url), 60_000);
  model.backupMessage = `Downloaded ${HistoryText.count(history.records.length, "practice")} as “${name}”.`;
  render();
}

/// Adds the practices in a backup, from this browser, another device, or the Mac app, that aren't here yet.
async function importHistory(file) {
  try {
    const { history: incoming, skipped } = PracticeHistory.read(await file.text());
    const merge = storeHistory((latest) => latest.merge(incoming.records));
    model.backupMessage = importSummary(merge, file.name, skipped);
  } catch (error) {
    model.backupMessage = readErrorMessage(error instanceof HistoryReadError ? error : new HistoryReadError("unreadable"), file.name);
  }
  journeyState.month = null;
  journeyState.selected = null;
  render();
}

// MARK: Timer and screen

let timer = null;

function pulse() {
  const changed = engine.tick(now(), MAXIMUM_UNOBSERVED_GAP);
  if (engine.phase === "paused") model.pauseReason = AWAY;
  update();
  if (changed) announceStage();
}

let wakeLock = null;
let wakeLockPending = false;

/// Keeps the screen on while the practice runs, so a long step isn't cut short by the display sleeping.
function updateWakeLock() {
  const wanted = engine.phase === "running" && !document.hidden;
  if (wanted && !wakeLock && !wakeLockPending && navigator.wakeLock) {
    wakeLockPending = true;
    navigator.wakeLock.request("screen").then((lock) => {
      wakeLockPending = false;
      if (engine.phase !== "running") {
        lock.release().catch(() => {});
        return;
      }
      wakeLock = lock;
      lock.addEventListener("release", () => { if (wakeLock === lock) wakeLock = null; });
    }, () => { wakeLockPending = false; });
  } else if (!wanted && wakeLock) {
    const lock = wakeLock;
    wakeLock = null;
    lock.release().catch(() => {});
  }
}

function update() {
  savePractice();
  if (engine.phase === "running") {
    timer ??= window.setInterval(pulse, TICK_MILLISECONDS);
  } else if (timer != null) {
    window.clearInterval(timer);
    timer = null;
  }
  updateWakeLock();
  render();
}

// MARK: Elements

const app = byId("app");
const views = {
  overview: byId("overview"), card: byId("cycle-card"), dial: byId("dial-card"), stage: byId("stage"),
};

const overviewScroll = byId("overview-scroll");
const journey = byId("journey");
const orbit = byId("orbit");
const ring = byId("ring");
const ringDashed = byId("ring-dashed");
const orbitChakra = byId("orbit-chakra");
const orbitFocus = byId("orbit-focus");
const focusEyebrow = byId("focus-eyebrow");
const focusArt = byId("focus-art");
const focusTitle = byId("focus-title");
const focusContext = byId("focus-context");
const statusLabel = byId("status-label");
const footerShortcut = byId("footer-shortcut");

const cyclesInput = byId("cycles-input");
const cyclesBox = byId("cycles-box");
const cyclesError = byId("cycles-error");
const timingSelect = byId("timing-mode");
const durationHint = byId("duration-hint");
const durationBox = byId("duration-box");
const minutesInput = byId("minutes-input");
const secondsInput = byId("seconds-input");
const durationError = byId("duration-error");
const summary = [1, 2].map((index) => ({ label: byId(`summary-label-${index}`), value: byId(`summary-value-${index}`) }));
const beginButton = byId("begin-button");
const setupNote = byId("setup-note");
const fullScreenCheckbox = byId("opens-full-screen");
const countdownBarSetting = byId("countdown-bar-setting");
const countdownBarCheckbox = byId("shows-countdown-bar");

const cardCycleCounter = byId("card-cycle-counter");
const cycleChakra = byId("cycle-chakra");
const cycleCardTitle = byId("cycle-card-title");

const stageArt = byId("stage-art");
const stageCycleCounter = byId("stage-cycle-counter");
const stepCounter = byId("step-counter");
const stepText = byId("step-text");
const pausedLabel = byId("paused-label");
const stageTitle = byId("stage-title");
const stageContext = byId("stage-context");
const remainingTime = byId("remaining-time");
const metaDivider = byId("meta-divider");
const cyclesCompleted = byId("cycles-completed");
const runningControls = byId("running-controls");
const pausedControls = byId("paused-controls");
const pauseReason = byId("pause-reason");
const stepMeter = byId("step-meter");
const stepMeterFill = byId("step-meter-fill");

const confirmation = byId("confirmation");
const confirmTitle = byId("confirm-title");
const confirmMessage = byId("confirm-message");
const confirmButton = byId("confirm-button");
const keepPracticing = byId("keep-practicing");
const announcer = byId("announcer");

const stepSpoken = make("span", "visually-hidden");
stepCounter.append(stepSpoken);

/// The five cards around the circle (OrbitView's StageCard).
const cards = STAGES.map((stage) => {
  const card = make("div", "stage-card");
  card.setAttribute("role", "img");
  card.setAttribute("aria-label", `Stage ${stage.id} of 5, ${stageLabel(stage)}`);
  const frame = make("div", "stage-card-frame");
  const image = make("img");
  image.src = `art/form-${stage.id}-small.jpg`;
  image.alt = "";
  image.decoding = "async";
  frame.append(image);
  const title = make("p", "stage-card-title");
  const name = make("span", "stage-card-name", stage.title);
  name.lang = "hi";
  title.append(make("span", "stage-card-number", pad2(stage.id)), name);
  const context = make("p", "stage-card-context", stage.context || " ");
  context.lang = "hi";
  const text = make("div", "stage-card-text");
  text.append(title, context);
  card.append(frame, text);
  orbit.insertBefore(card, orbitChakra);
  return card;
});

const SVG = "http://www.w3.org/2000/svg";
const chevrons = STAGES.map(() => {
  const chevron = document.createElementNS(SVG, "path");
  chevron.setAttribute("class", "chevron");
  chevron.setAttribute("d", "M-1.8 -3.6 1.8 0 -1.8 3.6");
  byId("chevrons").append(chevron);
  return chevron;
});

/// Each picture is shown at once from the small copy the page already has, then the full copy fades in.
const stageLayers = STAGES.map((stage) => {
  const layer = make("div", "stage-layer is-instant");
  const preview = make("img");
  preview.src = `art/form-${stage.id}-small.jpg`;
  preview.alt = "";
  const full = make("img", "stage-large");
  full.alt = "";
  full.decoding = "async";
  full.dataset.src = `art/form-${stage.id}.jpg`;
  full.addEventListener("load", () => full.classList.add("is-loaded"));
  layer.append(preview, full);
  stageArt.append(layer);
  return { layer, full };
});

function preloadArtwork() {
  for (const { full } of stageLayers) {
    if (!full.getAttribute("src")) full.setAttribute("src", full.dataset.src);
  }
}

// A scalloped seal, like the app's "checkmark.seal" symbol.
byId("seal-outline").setAttribute("d", Array.from({ length: 121 }, (_, index) => {
  const angle = (index / 120) * 2 * Math.PI;
  const radius = 16 + 1.3 * Math.cos(angle * 12);
  const x = 20 + radius * Math.cos(angle);
  const y = 20 + radius * Math.sin(angle);
  return `${index ? "L" : "M"}${x.toFixed(2)} ${y.toFixed(2)}`;
}).join("") + "Z");

// MARK: Orbit layout (OrbitView.swift)

const SIN_72 = Math.sin((2 * Math.PI) / 5);
const COS_36 = Math.cos(Math.PI / 5);

function layoutOrbit() {
  const width = orbit.clientWidth;
  const height = orbit.clientHeight;
  if (!width || !height) return;
  const cardWidth = Math.min(202, Math.max(102, Math.min(width * 0.225, height * 0.275)));
  const cardHeight = cardWidth * 0.565 + 61;
  const radiusX = Math.max(60, (width - cardWidth - 22) / (2 * SIN_72));
  const radiusY = Math.max(60, (height - cardHeight - 16) / (1 + COS_36));
  const centerY = (height + radiusY * (1 - COS_36)) / 2;
  // The lower cards sit to either side of the center; that open space holds a larger focus image.
  const extraFocusHeight = 20;
  const focusHeight = Math.max(126, radiusY * (1 + COS_36) - cardHeight - 30) + extraFocusHeight;
  const focusWidth = Math.min(width * 0.44, 420);
  const focusCenterY = height / 2 + extraFocusHeight / 2;

  orbit.style.setProperty("--card-image-height", `${cardWidth * 0.565}px`);
  const cardRects = cards.map((card, index) => {
    const angle = (index * 2 * Math.PI) / 5 - Math.PI / 2;
    const left = width / 2 + Math.cos(angle) * radiusX - cardWidth / 2;
    const top = centerY + Math.sin(angle) * radiusY - cardHeight / 2;
    card.style.left = `${left}px`;
    card.style.top = `${top}px`;
    card.style.width = `${cardWidth}px`;
    card.style.height = `${cardHeight}px`;
    card.classList.toggle("is-small", cardWidth < 145);
    return { left, top, right: left + cardWidth, bottom: top + cardHeight };
  });

  chevrons.forEach((chevron, index) => {
    const angle = (index * 2 * Math.PI) / 5 - Math.PI / 2 + Math.PI / 5;
    const x = width / 2 + Math.cos(angle) * radiusX;
    const y = centerY + Math.sin(angle) * radiusY;
    const rotation = (Math.atan2(radiusY * Math.cos(angle), -radiusX * Math.sin(angle)) * 180) / Math.PI;
    chevron.setAttribute("transform", `translate(${x.toFixed(1)} ${y.toFixed(1)}) rotate(${rotation.toFixed(1)})`);
  });
  for (const [ellipse, extra] of [[ring, 0], [ringDashed, 11]]) {
    ellipse.setAttribute("cx", width / 2);
    ellipse.setAttribute("cy", centerY);
    ellipse.setAttribute("rx", radiusX + extra);
    ellipse.setAttribute("ry", radiusY + extra);
  }

  // Phones and small windows leave no room for the focus between the cards.
  const focus = {
    left: (width - focusWidth) / 2,
    right: (width + focusWidth) / 2,
    top: focusCenterY - focusHeight / 2,
    bottom: focusCenterY + focusHeight / 2,
  };
  const crowded = cardRects.some((card) =>
    Math.min(card.right, focus.right) - Math.max(card.left, focus.left) > 12
    && Math.min(card.bottom, focus.bottom) - Math.max(card.top, focus.top) > 12);
  orbit.classList.toggle("is-crowded", crowded);

  const chakraSize = Math.max(56, Math.min(120, Math.min(radiusX, radiusY) * 0.62));
  orbitChakra.style.setProperty("--chakra-size", `${chakraSize}px`);
  orbitChakra.style.left = `${width / 2 - chakraSize / 2}px`;
  orbitChakra.style.top = `${centerY - chakraSize / 2}px`;

  orbitFocus.style.left = `${(width - focusWidth) / 2}px`;
  orbitFocus.style.top = `${focusCenterY - focusHeight / 2}px`;
  orbitFocus.style.width = `${focusWidth}px`;
  orbitFocus.style.height = `${focusHeight}px`;
  const compact = focusHeight < 240;
  orbitFocus.classList.toggle("is-compact", compact);
  orbitFocus.style.setProperty("--focus-image-height", `${Math.max(65, focusHeight - (compact ? 92 : 113))}px`);
}

// MARK: Rendering

let shownView = "overview";
let shownArt = null;
let confirmationShown = false;

function targetView() {
  if (engine.phase === "ready" || engine.phase === "complete") return "overview";
  if (engine.isIntroducingCycle) return "card";
  return engine.isIntroducingStage ? "dial" : "stage";
}

function render() {
  const target = targetView();
  app.dataset.phase = engine.phase;
  // A view that is fading out keeps what it showed: the last picture must not turn into the next cycle's first.
  if (target === "overview") renderOverview();
  else if (target === "card") renderCard();
  else if (target === "dial") renderDialCard();
  else renderStage();
  renderConfirmation();
  showView(target);
}

function showView(target) {
  const still = (name) => name === "overview";
  const fade = !still(target) && !reducedMotion.matches;
  const confirming = engine.phase === "confirming";
  for (const [name, view] of Object.entries(views)) {
    view.inert = name !== target || (name === "stage" && confirming);
  }
  if (target === shownView) return;
  for (const [name, view] of Object.entries(views)) {
    // The overview leaves and returns at once; the cards and the pictures cross-fade.
    view.classList.toggle("is-instant", !fade || still(name));
    view.classList.toggle("is-visible", name === target);
  }
  if (target === "card") turnChakra();
  if (target === "dial") turnDial();
  shownView = target;
}

function turnChakra() {
  cycleChakra.classList.remove("is-turning");
  void cycleChakra.offsetWidth;
  if (!reducedMotion.matches) cycleChakra.classList.add("is-turning");
}

function setShortcut(key, action) {
  const [kbd, label] = footerShortcut.children;
  setText(kbd, key);
  setText(label, action);
}

/// The overview's phase when last shown: a new one starts at the top of its page.
let shownPhase = null;

function renderOverview() {
  const ready = engine.phase === "ready";
  setText(statusLabel, ready ? "Ready when you are" : "Practice complete");
  // A page left open past midnight begins the new day.
  if (insights.today !== todayNumber()) refreshInsights();
  if (shownPhase !== engine.phase) {
    shownPhase = engine.phase;
    journeyState.month = null;
    journeyState.selected = null;
    for (const scroller of [overviewScroll, journey, views.overview]) scroller.scrollTop = 0;
  }
  if (ready) {
    cards.forEach((card, index) => card.classList.toggle("is-active", index === engine.stageIndex));
    const stage = engine.currentStage;
    setText(focusEyebrow, `Form ${pad2(stage.id)} / 05`);
    const art = `art/form-${stage.id}-small.jpg`;
    if (focusArt.getAttribute("src") !== art) focusArt.setAttribute("src", art);
    focusArt.alt = stageLabel(stage);
    setText(focusTitle, stage.title);
    setText(focusContext, stage.context || " ");
    setShortcut("Space", "Next step during practice");
    renderSetup();
    renderToday();
  } else {
    const count = engine.completedCycles;
    setText(byId("completed-cycles"), `${count} ${count === 1 ? "cycle" : "cycles"} completed`);
    // Timed practice includes pauses with a step; freestyle excludes pauses and has no planned time.
    setText(byId("practiced-time"), TimeText.elapsed(engine.activeSeconds));
    setText(byId("planned-time"), TimeText.elapsed(engine.configuration.plannedSeconds));
    byId("planned-divider").hidden = !engine.configuration.isTimed;
    byId("planned-summary").hidden = !engine.configuration.isTimed;
    setShortcut("Return", "Practice again");
    renderTimeSummary();
  }
  renderJourney();
  layoutOrbit();
}

// MARK: Today, in the setup header (MeditationView's todayButton)

const todayButton = byId("today-button");
const todayPractice = byId("today-practice");
const todayNone = byId("today-none");

/// Today's practice so far: its time and its cycles. It leads down to the journey.
function renderToday() {
  const today = insights.todayTotals;
  const any = today.practices > 0;
  todayPractice.hidden = !any;
  todayNone.hidden = any;
  if (any) {
    setText(byId("today-time"), HistoryText.minutes(today.seconds));
    setText(byId("today-cycles"), HistoryText.count(today.cycles, "cycle"));
  }
  todayButton.setAttribute("aria-label", any
    ? `Today: ${HistoryText.minutes(today.seconds)}, ${HistoryText.count(today.cycles, "cycle")} in ${HistoryText.count(today.practices, "practice")}. Show your journey.`
    : "Today: no practice yet. Show your journey.");
}

// MARK: The journey (JourneyView.swift)

const journeyTitle = byId("journey-title");
const journeySubtitle = byId("journey-subtitle");
const exportButton = byId("export-button");
const backupMessage = byId("backup-message");
const importFile = byId("import-file");
const journeyEmpty = byId("journey-empty");
const journeyContent = byId("journey-content");
const calendarMonth = byId("calendar-month");
const previousMonth = byId("previous-month");
const nextMonth = byId("next-month");
const dayDetail = byId("day-detail");
const trendArrow = byId("trend-arrow");
const trendMost = byId("trend-most");
const rhythmNotes = byId("rhythm-notes");
const BACKUP_NOTE = "Kept in this browser. A backup carries it to another device or the Mac app.";
/// The month on the calendar (its first day's number), and the day picked in it; null for today's.
const journeyState = { month: null, selected: null };

const tiles = Object.fromEntries(["today", "week", "month", "streak", "cycles"].map((name) =>
  [name, { value: byId(`tile-${name}`), detail: byId(`tile-${name}-detail`) }]));

for (const weekday of insights.weekdayOrder) {
  byId("calendar-weekdays").append(make("span", "", HistoryText.weekdays[weekday].slice(0, 3)));
}

/// "↻ 3": a turning arrow and the count of cycles (JourneyView's CycleCount), in blue.
const CYCLE_ICON = "M13.5 9.5a5.5 5.5 0 1 1-5.5-5.5h2.5M8.6 1.6 11 4l-2.4 2.4";
function cycleCount(text) {
  const count = make("span", "cycle-count");
  const icon = document.createElementNS(SVG, "svg");
  icon.setAttribute("class", "icon cycle-icon");
  icon.setAttribute("viewBox", "0 0 16 16");
  icon.setAttribute("aria-hidden", "true");
  const path = document.createElementNS(SVG, "path");
  path.setAttribute("d", CYCLE_ICON);
  icon.append(path);
  count.append(icon, make("span", "", text));
  return count;
}

/// "Saturday, 14 November: 1 hr 50 min, 5 cycles, 3 practices" (Journey.dayLabel)
function dayLabel(day, totals) {
  if (totals.practices === 0) return `${HistoryText.dayTitle(day)}: no practice`;
  return `${HistoryText.dayTitle(day)}: ${HistoryText.minutes(totals.seconds)}, ${HistoryText.count(totals.cycles, "cycle")}, ${HistoryText.count(totals.practices, "practice")}`;
}

/// Always six weeks, so the card keeps its height from month to month. A day: its number; then its
/// cycles, bottom left, in blue, and its time, bottom right.
const calendarCells = Array.from({ length: 42 }, () => {
  const cell = make("button", "day");
  cell.type = "button";
  cell.dataset.action = "select-day";
  const number = make("span", "day-number");
  const cycles = cycleCount("");
  cycles.classList.add("day-cycles");
  const time = make("span", "day-time");
  for (const part of [number, cycles, time]) part.setAttribute("aria-hidden", "true");
  cell.append(number, cycles, time);
  byId("calendar-days").append(cell);
  return { cell, number, cycles, cyclesText: cycles.lastElementChild, time };
});

const trendChart = byId("trend-chart");
const trendBars = Array.from({ length: PracticeInsights.weeksShown }, () => {
  const bar = make("div", "trend-bar");
  trendChart.append(bar);
  return bar;
});

const heatMap = byId("heat-map");
const heatCells = insights.weekdayOrder.map((weekday) => {
  heatMap.append(make("span", "heat-label", HistoryText.weekdays[weekday].slice(0, 3)));
  return Array.from({ length: 24 }, (_, hour) => {
    const cell = make("span", "heat-cell");
    heatMap.append(cell);
    return { cell, weekday, hour };
  });
}).flat();
heatMap.append(make("span"));
for (let mark = 0; mark < 24; mark += 3) heatMap.append(make("span", "heat-mark", HistoryText.hourMark(mark)));

/// The arrow inside the trend's circle (JourneyView's trend symbols).
const TREND_ARROWS = {
  rising: "M7 13 13 7M8.5 7H13v4.5",
  steady: "M5.5 10h9M11 6.5l3.5 3.5-3.5 3.5",
  easing: "M7 7l6 6M13 8.5V13H8.5",
  beginning: "M10 5.5v9M5.5 10h9",
  resting: "M12.5 6.5a4 4 0 1 0 1.5 6 3.2 3.2 0 0 1-1.5-6z",
};
const DIRECTION_ICONS = { up: "M4 12 12 4M5.5 4H12v6.5", down: "M4 4l8 8M12 5.5V12H5.5", same: "M3.5 6h9M3.5 10h9" };

function setTile(name, value, detail, direction = null) {
  setText(tiles[name].value, value);
  const box = tiles[name].detail;
  box.replaceChildren();
  if (direction && DIRECTION_ICONS[direction]) {
    const icon = document.createElementNS(SVG, "svg");
    icon.setAttribute("class", "icon");
    icon.setAttribute("viewBox", "0 0 16 16");
    icon.setAttribute("aria-hidden", "true");
    const path = document.createElementNS(SVG, "path");
    path.setAttribute("d", DIRECTION_ICONS[direction]);
    icon.append(path);
    box.append(icon);
  }
  box.append(make("span", "", detail));
  box.classList.toggle("is-up", direction === "up");
}

/// "6:42 am · 15 min · 3 cycles · Mac" (Journey.line)
function practiceLine(record) {
  const parts = [HistoryText.time(record.time.hour, record.time.minute), HistoryText.minutes(record.seconds),
    isCompleted(record) ? HistoryText.count(record.cycles, "cycle") : `${record.cycles} of ${record.planned} cycles`];
  if (record.timing === FREESTYLE) parts.push("freestyle");
  if (record.device) parts.push(record.device === "web" ? "Web" : record.device === "mac" ? "Mac" : record.device);
  return parts.join(" · ");
}

function renderJourney() {
  const empty = history.isEmpty;
  setText(journeySubtitle, empty ? "Nothing kept yet." : `${HistoryText.count(insights.all.practices, "practice")} since ${HistoryText.date(insights.firstDay)} · ${HistoryText.minutes(insights.all.seconds)} in all`);
  exportButton.disabled = empty;
  setText(backupMessage, model.backupMessage ?? BACKUP_NOTE);
  backupMessage.classList.toggle("is-result", model.backupMessage != null);
  journeyEmpty.hidden = !empty;
  journeyContent.hidden = empty;
  if (empty) return;

  setTile("today", HistoryText.minutes(insights.todayTotals.seconds), insights.todayDetail);
  setTile("week", HistoryText.minutes(insights.last7), insights.weekComparison.text, insights.weekComparison.direction);
  setTile("month", HistoryText.minutes(insights.last30), insights.monthComparison.text, insights.monthComparison.direction);
  setTile("streak", insights.streakValue, insights.streakDetail);
  setTile("cycles", String(insights.all.cycles), insights.cyclesDetail);
  renderCalendar();
  renderTrend();
  renderRhythm();
}

function renderCalendar() {
  const today = insights.today;
  const current = CivilDate.fromDayNumber(today);
  const first = journeyState.month ?? CivilDate.dayNumber(current.year, current.month, 1);
  const shown = CivilDate.fromDayNumber(first);
  const length = CivilDate.daysInMonth(shown.month, shown.year);
  const leading = (CivilDate.weekday(first) - insights.firstWeekday + 7) % 7;
  const earliest = CivilDate.fromDayNumber(insights.firstDay ?? today);
  const selected = journeyState.selected ?? today;
  setText(calendarMonth, `${HistoryText.months[shown.month - 1]} ${shown.year}`);
  previousMonth.disabled = shown.year * 12 + shown.month <= earliest.year * 12 + earliest.month;
  nextMonth.disabled = shown.year * 12 + shown.month >= current.year * 12 + current.month;
  calendarCells.forEach(({ cell, number, cycles, cyclesText, time }, index) => {
    const offset = index - leading;
    const inMonth = offset >= 0 && offset < length;
    cell.classList.toggle("is-blank", !inMonth);
    cell.tabIndex = inMonth ? 0 : -1;
    cell.setAttribute("aria-hidden", String(!inMonth));
    if (!inMonth) return;
    const day = first + offset;
    const totals = insights.totals(day);
    cell.dataset.day = String(day);
    cell.dataset.level = String(insights.level(day));
    cell.disabled = day > today;
    cell.classList.toggle("is-today", day === today);
    cell.classList.toggle("is-selected", day === selected);
    cell.setAttribute("aria-pressed", String(day === selected));
    setText(number, String(offset + 1));
    cycles.hidden = totals.practices === 0;
    setText(cyclesText, String(totals.cycles));
    setText(time, HistoryText.compact(totals.seconds));
    cell.setAttribute("aria-label", dayLabel(day, totals));
    cell.title = totals.practices === 0 ? "" : dayLabel(day, totals);
  });

  // The day picked: its time in gold, its cycles in blue, and how many practices.
  const totals = insights.totals(selected);
  const records = history.recordsOn(selected);
  const head = make("p", "day-detail-head");
  head.append(make("span", "day-detail-title", HistoryText.dayTitle(selected)));
  if (totals.practices > 0) {
    const sums = make("span", "day-detail-totals");
    sums.append(make("span", "day-detail-time", HistoryText.minutes(totals.seconds)), make("span", "", "·"),
      cycleCount(HistoryText.count(totals.cycles, "cycle")), make("span", "", "·"),
      make("span", "", HistoryText.count(totals.practices, "practice")));
    head.append(sums);
  }
  const lines = records.length === 0
    ? [make("p", "", selected === today ? "No practice yet today." : "No practice on this day.")]
    : records.slice(0, 3).map((record) => make("p", "", practiceLine(record)));
  if (records.length > 3) lines.push(make("p", "", `and ${records.length - 3} more`));
  dayDetail.replaceChildren(head, ...lines);
}

/// Another month: today stays picked in this one; in another, its last day with practice, or its first.
function stepMonth(months) {
  const current = CivilDate.fromDayNumber(journeyState.month ?? insights.today);
  const index = current.year * 12 + current.month - 1 + months;
  const year = Math.floor(index / 12);
  const month = (index % 12) + 1;
  const first = CivilDate.dayNumber(year, month, 1);
  const today = CivilDate.fromDayNumber(insights.today);
  journeyState.month = first;
  if (year === today.year && month === today.month) {
    journeyState.selected = null;
  } else {
    let picked = first;
    for (let day = first; day < first + CivilDate.daysInMonth(month, year); day += 1) {
      if (insights.totals(day).practices > 0) picked = day;
    }
    journeyState.selected = picked;
  }
  renderJourney();
}

function renderTrend() {
  setText(byId("trend-title"), insights.trendTitle);
  setText(byId("trend-detail"), insights.trendDetail);
  trendArrow.setAttribute("d", TREND_ARROWS[insights.trend]);
  sizeTrendBars();
  trendBars.forEach((bar, index) => {
    const seconds = insights.weekTotals[index];
    bar.classList.toggle("is-empty", seconds === 0);
    bar.classList.toggle("is-current", index === trendBars.length - 1);
    bar.title = `Week of ${HistoryText.shortDate(insights.weekStarts[index])}: ${HistoryText.minutes(seconds)}`;
  });
  const most = Math.max(1, ...insights.weekTotals);
  setText(trendMost, HistoryText.compact(most > 1 ? most : 0));
  setText(byId("trend-first"), HistoryText.shortDate(insights.weekStarts[0]));
  setText(byId("trend-middle"), HistoryText.shortDate(insights.weekStarts[6]));
  trendChart.setAttribute("aria-label", `Weekly practice, oldest first: ${insights.weekTotals.map((seconds, index) =>
    `week of ${HistoryText.shortDate(insights.weekStarts[index])}, ${HistoryText.minutes(seconds)}`).join("; ")}`);
}

/// The bars, in the chart's height: it grows when the card beside it is taller.
function sizeTrendBars() {
  const most = Math.max(1, ...insights.weekTotals);
  const tall = trendChart.clientHeight || 88;
  trendBars.forEach((bar, index) => {
    const seconds = insights.weekTotals[index];
    bar.style.height = `${seconds === 0 ? 2 : Math.max(4, (tall * seconds) / most)}px`;
  });
}

function renderRhythm() {
  for (const { cell, weekday, hour } of heatCells) cell.dataset.level = String(insights.heatLevel(weekday, hour));
  const notes = insights.rhythmNotes;
  rhythmNotes.replaceChildren(...notes.map((note) => make("li", "", note)));
  heatMap.setAttribute("aria-label", `The hours of the week you practice, over the last twelve weeks. ${notes.join(" ")}`);
}

// MARK: Your time (TimeSummaryPanel.swift)

const timeRows = byId("time-rows");
const timeAll = byId("time-all");
let shownSummary = null;

/// Like the practiced time, without the leading zero of the minutes ("1:05", "0:38"), so the numbers
/// stay clear of each other in narrow columns.
function clock(seconds) {
  const text = TimeText.elapsed(seconds);
  return text.length === 5 && text.startsWith("0") ? text.slice(1) : text;
}

/// One row of the table: the cycle (or "All"), each step's time, the average per step, and the total.
function timeRow(name, seconds, stepCount) {
  const total = seconds.reduce((sum, value) => sum + value, 0);
  const row = make("tr");
  const head = make("th", "", name);
  head.scope = "row";
  row.append(head);
  for (const value of seconds) row.append(make("td", "", clock(value)));
  row.append(make("td", "average", clock(total / stepCount)), make("td", "total", clock(total)));
  return row;
}

/// For each cycle, the time practiced in each of its steps, its total, and its average per step; then
/// all cycles together. Only timed modes count pauses with a step; cards and time away never count.
function renderTimeSummary() {
  const cycles = engine.stepSeconds;
  const key = JSON.stringify(cycles);
  if (key === shownSummary) return;
  shownSummary = key;
  timeRows.replaceChildren(...cycles.map((seconds, index) => timeRow(pad2(index + 1), seconds, STAGES.length)));
  const together = STAGES.map((_, step) => cycles.reduce((sum, seconds) => sum + seconds[step], 0));
  timeAll.replaceChildren(...(cycles.length > 1 ? [timeRow("All", together, STAGES.length * cycles.length)] : []));
}

function syncInputs() {
  if (cyclesInput.value !== model.cyclesText) cyclesInput.value = model.cyclesText;
  if (minutesInput.value !== model.minutesText) minutesInput.value = model.minutesText;
  if (secondsInput.value !== model.secondsText) secondsInput.value = model.secondsText;
  if (timingSelect.value !== model.timingMode) timingSelect.value = model.timingMode;
}

function renderSetup() {
  const perStep = model.timingMode === PER_STEP;
  const freestyle = model.timingMode === FREESTYLE;
  const cycleCount = cycles();
  cyclesBox.classList.toggle("is-invalid", cycleCount == null);
  cyclesInput.setAttribute("aria-invalid", String(cycleCount == null));
  cyclesError.hidden = cycleCount != null;

  // Freestyle has no time to enter; the fields keep theirs for when a timer is chosen again.
  durationBox.hidden = freestyle;
  countdownBarSetting.hidden = freestyle;
  const problem = durationProblem();
  durationBox.classList.toggle("is-invalid", problem != null);
  for (const input of [minutesInput, secondsInput]) input.setAttribute("aria-invalid", String(problem != null));
  durationError.hidden = problem == null;
  setText(durationError, problem ?? "");
  minutesInput.setAttribute("aria-label", perStep ? "Minutes per step" : "Total minutes");
  secondsInput.setAttribute("aria-label", perStep ? "Additional seconds per step" : "Additional total seconds");
  let hint = perStep ? "For each form" : "No timer, at your own pace";
  if (model.timingMode === TOTAL) {
    hint = cycleCount == null ? "For all cycles" : cycleCount === 1 ? "For 1 cycle" : `For all ${cycleCount} cycles`;
  }
  setText(durationHint, hint);

  // The two amounts the practitioner did not enter, calculated from the one they did. Freestyle has
  // no time to calculate, only steps.
  const chosen = configuration();
  let values = [["Per step", chosen && TimeText.approximateDuration(chosen.secondsPerStage)],
                ["Per cycle", chosen && TimeText.approximateDuration(chosen.secondsPerCycle)]];
  if (perStep) {
    values = [["Per cycle", chosen && TimeText.duration(chosen.secondsPerCycle)],
              ["Planned time", chosen && TimeText.duration(chosen.plannedSeconds)]];
  } else if (freestyle) {
    values = [["Per cycle", `${STAGES.length} steps`], ["In all", chosen && `${chosen.stepCount} steps`]];
  }
  values.forEach(([label, value], index) => {
    setText(summary[index].label, label);
    setText(summary[index].value, value || "—");
  });
  beginButton.disabled = chosen == null;
  let note = "This time is shared equally by every step. Space moves to the next step early.";
  if (perStep) note = "Each step gets this full time. Space moves to the next step early.";
  if (freestyle) note = "No timer: stay with each step as long as you like. Space moves to the next step.";
  setText(setupNote, note);
}

function setCapsule(capsule, visible, spoken) {
  if (!capsule.firstChild) {
    const shown = make("span");
    shown.setAttribute("aria-hidden", "true");
    capsule.append(shown, make("span", "visually-hidden"));
  }
  setText(capsule.children[0], visible);
  setText(capsule.children[1], spoken);
}

const cycleCapsule = () => `Cycle ${pad2(engine.currentCycle)} / ${pad2(engine.configuration.cycles)}`;

function renderCard() {
  setCapsule(cardCycleCounter, cycleCapsule(), cycleTitle());
  setText(cycleCardTitle, `Cycle ${engine.currentCycle}`);
}

// MARK: The card between two steps (DialCardView.swift, YugaDial.swift)

/// Where the hand points for each step, in degrees clockwise from twelve o'clock: the top, where the
/// Confluence Age meets Sat Yuga (step 1); the middle of Sat Yuga's quarter (2); the middle of Dwapar
/// Yuga's (3); the middle of the Confluence Age's wedge, 336° to 360° in the picture (4); and near
/// that wedge's end (5), 4° short of the top: the age is ending, but not yet over.
const DIAL_ANGLES = [0, 45, 225, 348, 356];
const DIAL_PLACES = ["the top, where the Confluence Age meets Sat Yuga", "Sat Yuga", "Dwapar Yuga",
  "the Confluence Age", "the end of the Confluence Age, just short of Sat Yuga"];
const dialCycleCounter = byId("dial-cycle-counter");
const yugaDial = byId("yuga-dial");
const dialHand = byId("yuga-dial-hand");

function renderDialCard() {
  setCapsule(dialCycleCounter, cycleCapsule(), cycleTitle());
  const turns = engine.stageIndex > 0;
  yugaDial.setAttribute("aria-label",
    `Step ${engine.stageIndex + 1} of 5. On the cycle of ages, the hand ${turns ? "turns" : "points"} to ${DIAL_PLACES[engine.stageIndex]}.`);
}

let dialTurn = null;

/// As the card comes into view, the hand stands where the step just finished does. Once the card has
/// faded in, it turns clockwise, as a clock does, to where the next step stands; a longer way takes a
/// little longer, and the longest ends well before the card does. Before a cycle's first step it simply
/// stands at the top, where that step is. A turn cut short by leaving the card early never carries
/// over to the next card.
function turnDial() {
  const from = DIAL_ANGLES[Math.max(0, engine.stageIndex - 1)];
  const to = DIAL_ANGLES[engine.stageIndex];
  dialTurn?.cancel();
  dialTurn = null;
  dialHand.style.transform = `rotate(${to}deg)`;
  if (reducedMotion.matches || from === to) return;
  dialTurn = dialHand.animate(
    [{ transform: `rotate(${from}deg)` }, { transform: `rotate(${to}deg)` }],
    { duration: (0.8 + (to - from) / 150) * 1000, delay: 400, easing: "ease-in-out", fill: "backwards" },
  );
}

function showStageArt(stage) {
  if (shownArt === stage.id) return;
  // Pictures cross-fade while the step screen is on view, and switch out of sight otherwise.
  const animate = shownView === "stage" && !reducedMotion.matches;
  stageLayers.forEach(({ layer }, index) => {
    layer.classList.toggle("is-instant", !animate);
    layer.classList.toggle("is-current", index === stage.id - 1);
  });
  stageArt.setAttribute("aria-label", stageLabel(stage));
  shownArt = stage.id;
}

function renderStage() {
  const stage = engine.currentStage;
  const running = engine.phase === "running";
  showStageArt(stage);
  setCapsule(stageCycleCounter, cycleCapsule(), cycleTitle());
  setText(stepText, `Step ${pad2(engine.stageIndex + 1)} / 05`);
  setText(stepSpoken, `Step ${engine.stageIndex + 1} of 5${running ? "" : ", paused"}`);
  pausedLabel.hidden = running;
  setText(stageTitle, stage.title);
  setText(stageContext, stage.context);
  stageContext.hidden = !stage.context;
  // Freestyle has no countdown: each step lasts until the practitioner moves on.
  remainingTime.hidden = !engine.configuration.isTimed;
  metaDivider.hidden = !engine.configuration.isTimed;
  setText(remainingTime, TimeText.countdown(engine.remainingSeconds));
  setText(cyclesCompleted, `${engine.completedCycles} / ${engine.configuration.cycles} cycles completed`);
  runningControls.hidden = !running;
  pausedControls.hidden = running;
  setText(pauseReason, model.pauseReason);
  renderStepMeter();
}

let meterStep = null;
let meterGlide = null;

/// StepMeter: the bar along the bottom empties as the step's time runs out and holds still while
/// paused. The browser runs the glide between ticks, on the compositor, with no work per frame.
/// It is left out in freestyle and when turned off in setup.
function renderStepMeter() {
  const shown = engine.configuration.isTimed && model.showsCountdownBar;
  stepMeter.hidden = !shown;
  if (!shown) {
    meterGlide?.cancel();
    meterGlide = null;
    meterStep = null;
    return;
  }
  const fraction = 1 - engine.progress;
  // A step coming into view, or the next step, starts the bar afresh, like a new StepMeterView.
  const fresh = shownView !== "stage" || meterStep !== engine.transitionCount;
  meterStep = engine.transitionCount;
  if (engine.phase !== "running") {
    meterGlide?.cancel();
    meterGlide = null;
    stepMeterFill.style.transform = `scaleX(${fraction})`;
  } else if (fresh || !meterGlide) {
    meterGlide?.cancel();
    stepMeterFill.style.transform = "scaleX(0)";
    meterGlide = stepMeterFill.animate(
      [{ transform: `scaleX(${fraction})` }, { transform: "scaleX(0)" }],
      { duration: Math.max(engine.remainingSeconds, 0.01) * 1000, easing: "linear" },
    );
  }
}

function renderConfirmation() {
  const confirming = engine.phase === "confirming";
  if (confirming) {
    const restart = engine.pendingConfirmation === "restart";
    setText(confirmTitle, restart ? "Begin this practice again?" : "End this practice?");
    setText(confirmMessage, restart
      ? "Your current progress will be cleared. You’ll return to the first form of the first cycle."
      : "Your current progress will be cleared. You can begin a new practice whenever you’re ready.");
    setText(confirmButton, restart ? "Restart practice" : "End practice");
  }
  if (confirming === confirmationShown) return;
  confirmationShown = confirming;
  confirmation.hidden = !confirming;
  if (confirming) keepPracticing.focus();
}

function announce(text) {
  announcer.textContent = "";
  window.setTimeout(() => { announcer.textContent = text; }, 60);
}

function announceStage() {
  if (engine.phase === "complete") announce("Meditation complete.");
  else if (engine.isIntroducingCycle) announce(cycleTitle());
  // The card between steps says where the hand turns; the step is announced as it begins.
  else if (!engine.isIntroducingStage) announce(stageLabel(engine.currentStage));
}

// MARK: Full screen

const fullScreenSupported = Boolean(document.fullscreenEnabled || document.webkitFullscreenEnabled);
const isFullScreen = () => Boolean(document.fullscreenElement || document.webkitFullscreenElement);
let leavingFullScreenOnPurpose = false;
let lastEscapeKey = -Infinity;

function enterFullScreen() {
  if (!fullScreenSupported || isFullScreen()) return;
  const root = document.documentElement;
  try {
    const request = root.requestFullscreen ? root.requestFullscreen({ navigationUI: "hide" }) : root.webkitRequestFullscreen();
    // In Chrome, Esc can then pause the practice as in the Mac app; holding Esc still leaves full screen.
    Promise.resolve(request).then(() => navigator.keyboard?.lock?.(["Escape"])).catch(() => {});
  } catch { /* The page stays in its window. */ }
}

function exitFullScreen() {
  if (!isFullScreen()) return;
  leavingFullScreenOnPurpose = true;
  navigator.keyboard?.unlock?.();
  try {
    const exit = document.exitFullscreen ? document.exitFullscreen() : document.webkitExitFullscreen();
    Promise.resolve(exit).catch(() => { leavingFullScreenOnPurpose = false; });
  } catch {
    leavingFullScreenOnPurpose = false;
  }
}

function fullScreenChanged() {
  const active = isFullScreen();
  document.documentElement.classList.toggle("is-fullscreen", active);
  for (const button of document.querySelectorAll('[data-action="fullscreen"]')) {
    button.setAttribute("aria-label", active ? "Exit full screen" : "Enter full screen");
    button.title = active ? "Exit full screen (F)" : "Full screen (F)";
  }
  if (active) return;
  navigator.keyboard?.unlock?.();
  const purposeful = leavingFullScreenOnPurpose;
  leavingFullScreenOnPurpose = false;
  // Esc is the pause key. When the browser spends it on leaving full screen, the page never
  // receives the key, so the exit stands in for it, though never to resume: the browser also
  // leaves full screen in other ways, and a paused practice carries on only when asked.
  if (!purposeful && now() - lastEscapeKey > 0.5 && engine.phase !== "paused") escape();
}

document.addEventListener("fullscreenchange", fullScreenChanged);
document.addEventListener("webkitfullscreenchange", fullScreenChanged);

// MARK: Input

cyclesInput.addEventListener("input", () => { model.cyclesText = cyclesInput.value; renderSetup(); });
minutesInput.addEventListener("input", () => { model.minutesText = minutesInput.value; renderSetup(); });
secondsInput.addEventListener("input", () => { model.secondsText = secondsInput.value; renderSetup(); });

// A click into a field selects its whole value, so typing replaces it (SetupPanel's selectWholeValueOfFocusedField).
// Tab already selects it; a click in a field that is already being edited still places the insertion point.
for (const input of [cyclesInput, minutesInput, secondsInput]) {
  let focusing = false;
  input.addEventListener("pointerdown", () => { focusing = document.activeElement !== input; });
  input.addEventListener("click", () => {
    if (focusing) input.setSelectionRange(0, input.value.length);
    focusing = false;
  });
}

timingSelect.addEventListener("change", () => {
  setTimingMode(timingSelect.value);
  syncInputs();
  renderSetup();
});

for (const button of document.querySelectorAll("[data-step]")) {
  button.addEventListener("click", () => {
    const [low, high] = SessionConfiguration.cycleRange;
    const current = cycles() ?? 1;
    model.cyclesText = String(Math.min(high, Math.max(low, current + Number(button.dataset.step))));
    syncInputs();
    renderSetup();
  });
}

fullScreenCheckbox.addEventListener("change", () => {
  model.opensInFullScreen = fullScreenCheckbox.checked;
  storage.write("opensInFullScreen", String(model.opensInFullScreen));
});

countdownBarCheckbox.addEventListener("change", () => {
  model.showsCountdownBar = countdownBarCheckbox.checked;
  storage.write("showsCountdownBar", String(model.showsCountdownBar));
});

byId("setup").addEventListener("submit", (event) => {
  event.preventDefault();
  begin();
});

document.addEventListener("click", (event) => {
  const button = event.target.closest("[data-action]");
  if (!button || button.disabled) return;
  switch (button.dataset.action) {
    case "pause": pause(); break;
    case "next": nextStage(); break;
    case "resume": resume(); break;
    case "restart": request("restart"); break;
    case "end": request("end"); break;
    case "cancel-confirmation": cancelConfirmation(); break;
    case "confirm": confirm(); break;
    case "practice-again": practiceAgain(); break;
    case "fullscreen": isFullScreen() ? exitFullScreen() : enterFullScreen(); break;
    case "journey": showJourney(); break;
    case "export-backup": exportHistory(); break;
    case "import-backup": importFile.click(); break;
    case "previous-month": stepMonth(-1); break;
    case "next-month": stepMonth(1); break;
    case "select-day":
      journeyState.selected = Number(button.dataset.day);
      renderJourney();
      break;
    default: break;
  }
});

importFile.addEventListener("change", () => {
  const [file] = importFile.files ?? [];
  importFile.value = "";
  if (file) importHistory(file);
});

// A practice kept in another tab shows here too.
window.addEventListener("storage", (event) => {
  if (event.key !== HISTORY_KEY && event.key !== null) return;
  history = readHistory() ?? new PracticeHistory();
  refreshInsights();
  if (engine.phase === "ready" || engine.phase === "complete") render();
});

const isTextField = (element) => element instanceof HTMLInputElement && element.type === "text";
const isToggle = (element) => element instanceof HTMLSelectElement
  || (element instanceof HTMLInputElement && element.type === "checkbox");
const isControl = (element) => element instanceof HTMLButtonElement || isToggle(element);

/// Event times share performance.now()'s clock; fall back to now for any that don't.
function eventTime(event) {
  const current = now();
  const stamp = event.timeStamp / 1000;
  return Number.isFinite(stamp) && stamp > 0 && Math.abs(current - stamp) < 60 ? stamp : current;
}

/// Space is only text in a setup field (or a toggle's own key); elsewhere it must not press a button.
const spaceBelongsTo = (target) => engine.phase !== "running" && (isTextField(target) || isToggle(target));

document.addEventListener("keydown", (event) => {
  if (event.isComposing) return;
  const target = event.target;
  const modified = event.metaKey || event.ctrlKey || event.altKey;

  if (event.key === "Escape") {
    if (modified) return;
    lastEscapeKey = now();
    if (!event.repeat) escape();
    if (engine.phase !== "ready" && engine.phase !== "complete") event.preventDefault();
    return;
  }

  if (event.key === " " || event.code === "Space") {
    if (modified) return;
    if (engine.phase === "running") {
      event.preventDefault();
      nextStage(eventTime(event), event.repeat);
    } else if (!spaceBelongsTo(target)) {
      event.preventDefault();
    }
    return;
  }

  if (event.key === "Enter") {
    if (event.altKey || event.shiftKey) return;
    if (event.metaKey || event.ctrlKey) {
      if (engine.phase === "confirming") {
        event.preventDefault();
        confirm();
      }
      return;
    }
    // A focused button or menu answers its own Return.
    if (isControl(target) || event.repeat) return;
    if (engine.phase === "ready") { event.preventDefault(); begin(); }
    else if (engine.phase === "paused") { event.preventDefault(); resume(); }
    else if (engine.phase === "complete") { event.preventDefault(); practiceAgain(); }
    return;
  }

  if (modified || event.repeat || isTextField(target)) return;
  const key = event.key.toLowerCase();
  if (key === "f" && fullScreenSupported) {
    event.preventDefault();
    if (isFullScreen()) exitFullScreen(); else enterFullScreen();
  } else if (key === "j" && (engine.phase === "ready" || engine.phase === "complete")) {
    event.preventDefault();
    showJourney();
  } else if (key === "r" && engine.phase === "paused") {
    event.preventDefault();
    request("restart");
  } else if (key === "e" && engine.phase === "paused") {
    event.preventDefault();
    request("end");
  }
});

// Buttons press on Space's release, so the release must be held back too.
document.addEventListener("keyup", (event) => {
  if ((event.key === " " || event.code === "Space") && !spaceBelongsTo(event.target)) event.preventDefault();
});

// MARK: Presence (AppMain.updatePresence)

let absenceCheck = null;
const inFront = () => !document.hidden && document.hasFocus();

window.addEventListener("blur", () => {
  window.clearTimeout(absenceCheck);
  // Switching to another window or app pauses; a passing focus change does not.
  absenceCheck = window.setTimeout(() => {
    if (!document.hasFocus()) setPresent(false);
  }, 250);
});

window.addEventListener("focus", () => {
  window.clearTimeout(absenceCheck);
  if (inFront()) setPresent(true);
});

document.addEventListener("visibilitychange", () => {
  if (document.hidden) setPresent(false);
  else {
    if (inFront()) setPresent(true);
    updateWakeLock();
  }
});

// Leaving the page pauses the practice, and keeps what was practiced.
window.addEventListener("pagehide", () => {
  setPresent(false);
  savePractice({ force: true });
});
window.addEventListener("pageshow", () => { if (inFront()) setPresent(true); });

// Leaving or reloading the page mid-practice asks first, as quitting the app does.
window.addEventListener("beforeunload", (event) => {
  if (engine.phase === "running" || engine.phase === "paused" || engine.phase === "confirming") {
    event.preventDefault();
    event.returnValue = "";
  }
});

// MARK: Start

if (!fullScreenSupported) document.documentElement.classList.add("no-fullscreen");
fullScreenCheckbox.checked = model.opensInFullScreen;
countdownBarCheckbox.checked = model.showsCountdownBar;
engine.setPresent(inFront(), now());
byId("confirm-hint").textContent = `Esc to keep practicing · ${isMac ? "⌘Return" : "Ctrl+Enter"} to confirm`;
syncInputs();
render();
new ResizeObserver(() => layoutOrbit()).observe(orbit);
new ResizeObserver(() => sizeTrendBars()).observe(trendChart);

// Fetch the full pictures once the page is idle, unless the visitor has asked to save data.
if (!navigator.connection?.saveData) {
  (window.requestIdleCallback ?? ((callback) => window.setTimeout(callback, 1500)))(preloadArtwork);
}
