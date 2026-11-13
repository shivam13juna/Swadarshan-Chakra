// Swadarshan Chakra in the browser. The practice logic lives in engine.js (a port of
// MeditationCore); this file mirrors the Mac app's SessionModel, its SwiftUI views, and
// AppMain's keyboard and lifecycle handling.
import {
  STAGES, stageLabel, PER_STEP, SessionConfiguration, SessionEngine, TimeText,
  loadPreferences, savePreferences,
} from "./engine.js";

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
const model = {
  cyclesText: String(saved.cycles),
  timingMode: saved.timing,
  minutesText: String(saved.enteredMinutes),
  secondsText: pad2(saved.enteredSecondsComponent),
  pauseReason: PAUSED,
  opensInFullScreen: storage.read("opensInFullScreen") !== "false",
};

const cycles = () => SessionConfiguration.integer(model.cyclesText, SessionConfiguration.cycleRange);
const cycleTitle = () => `Cycle ${engine.currentCycle} of ${engine.configuration.cycles}`;

function configuration() {
  const cycleCount = cycles();
  const minutes = SessionConfiguration.integer(model.minutesText, SessionConfiguration.minuteRange(model.timingMode));
  const seconds = SessionConfiguration.integer(model.secondsText, SessionConfiguration.secondRange);
  if (cycleCount == null || minutes == null || seconds == null) return null;
  return SessionConfiguration.make(cycleCount, model.timingMode, minutes, seconds);
}

/// Why the entered time cannot be used, or null. An invalid cycle count is reported by its own field.
function durationProblem() {
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

/// Switching only changes how the time is entered: the fields are converted so the practice stays the same.
function setTimingMode(mode) {
  if (mode === model.timingMode) return;
  const converted = configuration()?.expressed(mode);
  if (converted) {
    model.minutesText = String(converted.enteredMinutes);
    model.secondsText = pad2(converted.enteredSecondsComponent);
  }
  model.timingMode = mode;
}

// MARK: Actions

function begin() {
  const chosen = configuration();
  if (!chosen || engine.phase !== "ready") return;
  savePreferences(chosen, storage.write);
  preloadArtwork();
  if (model.opensInFullScreen) enterFullScreen();
  engine.begin(chosen, now());
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

function pause(reason = PAUSED, away = false) {
  const wasActive = engine.phase === "running" || engine.phase === "confirming";
  if (away) engine.pauseAtLastSample();
  else engine.pause(now());
  if (wasActive) model.pauseReason = reason;
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
  engine.confirm(now());
  update();
}

function practiceAgain() {
  engine.reset();
  update();
}

function escape() {
  if (engine.phase === "running") pause();
  else if (engine.phase === "confirming") cancelConfirmation();
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
const views = { overview: byId("overview"), card: byId("cycle-card"), stage: byId("stage") };

const orbit = byId("orbit");
const ring = byId("ring");
const ringDashed = byId("ring-dashed");
const orbitChakra = byId("orbit-chakra");
const orbitFocus = byId("orbit-focus");
const activeFocus = byId("active-focus");
const completionFocus = byId("completion-focus");
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
const cyclesCompleted = byId("cycles-completed");
const runningControls = byId("running-controls");
const pausedControls = byId("paused-controls");
const pauseReason = byId("pause-reason");
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
  const complete = engine.phase === "complete";
  const cardWidth = Math.min(202, Math.max(102, Math.min(width * 0.225, height * 0.275)));
  const cardHeight = cardWidth * 0.565 + 61;
  const radiusX = Math.max(60, (width - cardWidth - 22) / (2 * SIN_72));
  const radiusY = Math.max(60, (height - cardHeight - 16) / (1 + COS_36));
  const centerY = (height + radiusY * (1 - COS_36)) / 2;
  // The lower cards sit to either side of the center; that open space holds a larger focus image.
  const extraFocusHeight = complete ? 0 : 20;
  let focusHeight = Math.max(126, radiusY * (1 + COS_36) - cardHeight - 30) + extraFocusHeight;
  let focusWidth = Math.min(width * 0.44, 420);
  let focusCenterY = height / 2 + extraFocusHeight / 2;

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
  if (crowded && complete) {
    focusWidth = width;
    focusHeight = height;
    focusCenterY = height / 2;
  }

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
  orbitFocus.classList.toggle("is-short", focusHeight < 280);
  orbitFocus.style.setProperty("--focus-image-height", `${Math.max(65, focusHeight - (compact ? 92 : 113))}px`);
}

// MARK: Rendering

let shownView = "overview";
let wasIntroducing = false;
let shownArt = null;
let confirmationShown = false;

function targetView() {
  if (engine.phase === "ready" || engine.phase === "complete") return "overview";
  return engine.isIntroducingCycle ? "card" : "stage";
}

function render() {
  const target = targetView();
  app.dataset.phase = engine.phase;
  // A view that is fading out keeps what it showed: the last picture must not turn into the next cycle's first.
  if (target === "overview") renderOverview();
  else if (target === "card") renderCard();
  else renderStage();
  renderConfirmation();
  showView(target);
}

function showView(target) {
  const introducing = engine.isIntroducingCycle;
  const fade = introducing !== wasIntroducing && !reducedMotion.matches;
  wasIntroducing = introducing;
  const confirming = engine.phase === "confirming";
  for (const [name, view] of Object.entries(views)) {
    view.inert = name !== target || (name === "stage" && confirming);
  }
  if (target === shownView) return;
  for (const [name, view] of Object.entries(views)) {
    // The overview leaves and returns at once; the cycle card and the pictures cross-fade.
    view.classList.toggle("is-instant", !fade || name === "overview");
    view.classList.toggle("is-visible", name === target);
  }
  if (target === "card") turnChakra();
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

function renderOverview() {
  const ready = engine.phase === "ready";
  setText(statusLabel, ready ? "Ready when you are" : "Practice complete");
  orbit.classList.toggle("is-preview", ready);
  orbit.classList.toggle("is-complete", !ready);
  cards.forEach((card, index) => card.classList.toggle("is-active", ready && index === engine.stageIndex));
  activeFocus.hidden = !ready;
  completionFocus.hidden = ready;
  if (ready) {
    const stage = engine.currentStage;
    setText(focusEyebrow, `Form ${pad2(stage.id)} / 05`);
    const art = `art/form-${stage.id}-small.jpg`;
    if (focusArt.getAttribute("src") !== art) focusArt.setAttribute("src", art);
    focusArt.alt = stageLabel(stage);
    setText(focusTitle, stage.title);
    setText(focusContext, stage.context || " ");
    setShortcut("Space", "Next step during practice");
    renderSetup();
  } else {
    const count = engine.completedCycles;
    setText(byId("completed-cycles"), `${count} ${count === 1 ? "cycle" : "cycles"} completed`);
    setText(byId("practiced-time"), TimeText.elapsed(engine.activeSeconds));
    setText(byId("planned-time"), TimeText.elapsed(engine.configuration.plannedSeconds));
    setShortcut("Return", "Practice again");
  }
  layoutOrbit();
}

function syncInputs() {
  if (cyclesInput.value !== model.cyclesText) cyclesInput.value = model.cyclesText;
  if (minutesInput.value !== model.minutesText) minutesInput.value = model.minutesText;
  if (secondsInput.value !== model.secondsText) secondsInput.value = model.secondsText;
  if (timingSelect.value !== model.timingMode) timingSelect.value = model.timingMode;
}

function renderSetup() {
  const perStep = model.timingMode === PER_STEP;
  const cycleCount = cycles();
  cyclesBox.classList.toggle("is-invalid", cycleCount == null);
  cyclesInput.setAttribute("aria-invalid", String(cycleCount == null));
  cyclesError.hidden = cycleCount != null;

  const problem = durationProblem();
  durationBox.classList.toggle("is-invalid", problem != null);
  for (const input of [minutesInput, secondsInput]) input.setAttribute("aria-invalid", String(problem != null));
  durationError.hidden = problem == null;
  setText(durationError, problem ?? "");
  minutesInput.setAttribute("aria-label", perStep ? "Minutes per step" : "Total minutes");
  secondsInput.setAttribute("aria-label", perStep ? "Additional seconds per step" : "Additional total seconds");
  let hint = "For each form";
  if (!perStep) hint = cycleCount == null ? "For all cycles" : cycleCount === 1 ? "For 1 cycle" : `For all ${cycleCount} cycles`;
  setText(durationHint, hint);

  // The two amounts the practitioner did not enter, calculated from the one they did.
  const chosen = configuration();
  const values = perStep
    ? [["Per cycle", chosen && TimeText.duration(chosen.secondsPerCycle)],
       ["Planned time", chosen && TimeText.duration(chosen.plannedSeconds)]]
    : [["Per step", chosen && TimeText.approximateDuration(chosen.secondsPerStage)],
       ["Per cycle", chosen && TimeText.approximateDuration(chosen.secondsPerCycle)]];
  values.forEach(([label, value], index) => {
    setText(summary[index].label, label);
    setText(summary[index].value, value || "—");
  });
  beginButton.disabled = chosen == null;
  setText(setupNote, perStep
    ? "Each step gets this full time. Space moves to the next step early."
    : "This time is shared equally by every step. Space moves to the next step early.");
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
function renderStepMeter() {
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
  else announce(stageLabel(engine.currentStage));
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
  // receives the key, so the exit stands in for it.
  if (!purposeful && now() - lastEscapeKey > 0.5) escape();
}

document.addEventListener("fullscreenchange", fullScreenChanged);
document.addEventListener("webkitfullscreenchange", fullScreenChanged);

// MARK: Input

cyclesInput.addEventListener("input", () => { model.cyclesText = cyclesInput.value; renderSetup(); });
minutesInput.addEventListener("input", () => { model.minutesText = minutesInput.value; renderSetup(); });
secondsInput.addEventListener("input", () => { model.secondsText = secondsInput.value; renderSetup(); });

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
    default: break;
  }
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

// MARK: Absence (AppMain.pauseForAbsence)

let absenceCheck = null;

window.addEventListener("blur", () => {
  window.clearTimeout(absenceCheck);
  // Switching to another window or app pauses; a passing focus change does not.
  absenceCheck = window.setTimeout(() => {
    if (!document.hasFocus()) pause(AWAY, true);
  }, 250);
});

document.addEventListener("visibilitychange", () => {
  if (document.hidden) pause(AWAY, true);
  else updateWakeLock();
});

window.addEventListener("pagehide", () => pause(AWAY, true));

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
byId("confirm-hint").textContent = `Esc to keep practicing · ${isMac ? "⌘Return" : "Ctrl+Enter"} to confirm`;
syncInputs();
render();
new ResizeObserver(() => layoutOrbit()).observe(orbit);

// Fetch the full pictures once the page is idle, unless the visitor has asked to save data.
if (!navigator.connection?.saveData) {
  (window.requestIdleCallback ?? ((callback) => window.setTimeout(callback, 1500)))(preloadArtwork);
}
