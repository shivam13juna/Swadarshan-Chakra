# Product Requirements Document (PRD)

# Swadarshan Chakra — macOS Menu Bar Meditation App

**Version:** 2.0  
**Status:** Product and design specification; no application implementation  
**Platform:** macOS  
**Primary experience:** Full-screen Swadarshan Chakra meditation launched from a menu bar icon  
**Asset source:** Exactly five spiritual pictures, supplied by the product owner (one for each stage)

## Product-owner update — 10 November 2026

The following changes supersede the running-screen layout and timing-input requirements in the original specification below:

1. **Full-screen picture at each step:** While Running or Paused, show that step's supplied picture across the entire selected display. Scale proportionally and crop the excess at the edges to fill the screen. Keep the stage title, timing, and controls as small overlays. The circular five-picture layout is the setup/completion overview.
2. **Time per step:** The practitioner enters a duration for one step, rather than a total duration for all five steps. Use minutes and seconds, defaulting to one minute per step. Apply the same full duration to each of the five steps. Calculate `secondsPerCycle = secondsPerStep × 5` and `plannedSessionSeconds = secondsPerStep × 5 × cycles` automatically. Accept 1 second through 120 minutes per step; keep the cycle count range at 1–108.
3. **Existing settings:** Convert saved cycle durations to their exact per-step equivalent, including seconds, so updating does not unexpectedly change the practitioner's pace.
4. **Native macOS full screen:** Open meditation in a native full-screen Space with the menu bar and Dock hidden automatically, matching the behavior of Chrome or Terminal in full-screen mode. A display-sized window with Finder's menu bar still visible does not meet this requirement. This supersedes the original preference for avoiding a Space transition. Closing returns to the menu bar utility and preserves the paused session.
5. **Supplied branding:** Use the owner's `icon.png` beside the app title, in confirmation dialogs, for the menu bar item, and as the application icon. Replace the custom five-dot logo with the supplied gold chakra.

The fixed stage order, supplied-file mapping, Space behavior, pause/resume, confirmations, and offline operation still apply. The text below records the original v2.0 specification.

## 1. Product Overview

Swadarshan Chakra is a lightweight macOS menu bar application for practicing **Swadarshan Chakra Phirana** through five consecutive forms of spiritual self-awareness.

Clicking the menu bar icon opens a beautiful, immersive, full-screen window. The five stages appear in a **fixed clockwise circle**, with **one supplied picture associated with each stage**. The active stage is visually emphasized; its name and picture are easy to contemplate, while the timing and cycle counts remain unobtrusive.

Before starting, the user chooses:

1. **Number of cycles** to complete.
2. **Minutes per cycle** — the total time allocated to **all five stages together**, not to each stage individually.

The app divides the chosen cycle duration equally among the five stages, advances automatically when a stage's time runs out, and repeats the five-stage sequence until the desired number of cycles is complete.

**A press of the Space bar moves immediately to the next stage** without waiting for the timer. It skips only the current *step*, not the entire cycle. Thus users can move onward whenever they feel they have completed contemplating a particular form.

The overall visual tone should be spiritual, luminous, peaceful, polished, and distraction-free — not utilitarian, gamified, or visually busy.

## 2. Goals

1. Launch a full-screen meditation experience with one click from the macOS menu bar.
2. Keep the five spiritual stages in a clearly readable, fixed clockwise circle.
3. Display the **five user-provided pictures** prominently and correctly associate each picture with its stage.
4. Allow the user to choose both **cycle count** and **total minutes per cycle** before beginning.
5. Allocate the selected time **equally across the five stages**.
6. Advance stages automatically as their allotted time expires.
7. Allow **Space** to skip the remaining time of the current stage and move to the next stage immediately.
8. Correctly count completed cycles, including cycles in which some stages were advanced manually.
9. Show the current stage, remaining stage time, and completed/target cycle count discreetly.
10. Support simple pause, resume, restart, close, and session-completion behavior.
11. Run reliably as a lightweight, locally operating Mac application.

## 3. Spiritual Content and Stage Order

The **order and spiritual meaning of these five stages are fixed**. Preserve the product owner's preferred wording. The Hindi text below is a proposed display transcription to be confirmed before release.

| Position | Hindi display label | User-provided transliteration | Stage image |
|---|---|---|---|
| 1 | बीज रूप — परमधाम में | Beej roop paramdham me | Supplied picture 1 |
| 2 | विश्व महाराजन — सतयुग में | Vishwa Maharajan satyug me | Supplied picture 2 |
| 3 | पूज्य स्वरूप — द्वापर युग में | Pujya Swaroop dwapar yug me | Supplied picture 3 |
| 4 | परम पवित्र ब्राह्मण — कलियुग में | Param Pavitra Brahmin Kalyug me | Supplied picture 4 |
| 5 | फरिश्ता स्वरूप | Farishta swaroop | Supplied picture 5 |

The five positions follow **1 → 2 → 3 → 4 → 5 → 1**, clockwise, with Stage 1 at the top of the circle.

### 3.1 Images supplied by the product owner

- The product owner will provide **five pictures**, exactly one associated with each stage.
- **Do not generate, source, download, search for, or substitute spiritual pictures online.** No AI-generated images or online image services are part of this product.
- Until the actual files are available, design and development may use **clearly labeled local placeholders** only to verify spacing and image handling; those placeholders must not ship as stage artwork.
- Once provided, bundle the images with the macOS app so all five load locally and remain available offline.
- Preserve each image's content and aspect ratio. Prefer `aspect fit` / letterboxing over cropping out important spiritual imagery; any intentional crop should require review.
- Match images to stages explicitly (by asset name or manifest), not alphabetically or by an unreliable file listing.
- The app should not start a release build with any of the five image assignments missing or mixed up.
- If the supplied images have different shapes or resolutions, adapt their presentation consistently without distorting them.
- The same supplied picture may appear as a small circle thumbnail and, when active, in a larger central focus region. These are **two views of the same file**, not additional images.

**Suggested asset mapping (filenames are placeholders until files are received):**

| Logical asset ID | Stage |
|---|---|
| `stage_01` | Beej Roop — Paramdham |
| `stage_02` | Vishwa Maharajan — Satyug |
| `stage_03` | Pujya Swaroop — Dwapar Yug |
| `stage_04` | Param Pavitra Brahmin — Kalyug |
| `stage_05` | Farishta Swaroop |

### 3.2 Text treatment

- The active stage's Hindi name should be prominent and easy to read at a distance.
- All five stage labels should remain visible in the circular layout, subject to sensible adaptive placement on smaller displays.
- Romanized labels may serve as design references; the primary display text is Hindi unless the product owner requests otherwise.
- Do not invent prayers, affirmations, narration, or explanatory passages as replacements for the five names.

## 4. Core User Journey

### 4.1 Open the app

1. The app is accessible from a persistent **macOS menu bar icon**.
2. Clicking that icon opens the meditation interface **occupying the entire selected screen**, rather than a small dropdown/popover.
3. The first view is a **Ready / Setup** state featuring the five-stage circular composition and two inputs:
   - **Cycles:** number of five-stage rounds.
   - **Minutes per cycle:** total planned duration for one full five-stage round.
4. The setup view immediately shows the derived **time per stage** and **maximum planned session duration**.
5. The user selects **Begin Meditation** to start Stage 1.

The app remains available in the menu bar after the full-screen view closes.

### 4.2 Configure cycles and duration

**Input A — Number of cycles**

- Positive integer; default **1**.
- Recommended initial valid range: **1–108** cycles, matching the original specification.

**Input B — Minutes per cycle**

- Positive number of **whole minutes**; default **5 minutes** per cycle.
- Recommended initial valid range: **1–120 minutes** per cycle; this is a UI guardrail, not a spiritual limitation.
- A five-minute cycle provides **one minute per stage**.
- A ten-minute cycle provides **two minutes per stage**.
- Other values are supported using the same equal-allocation rule.

**Derivation:**

```text
stagesPerCycle = 5
minutesPerCycle = user input
secondsPerStage = (minutesPerCycle * 60) / 5
plannedSessionSeconds = cycleCount * minutesPerCycle * 60
```

Because whole minutes are accepted, `secondsPerStage = 12 × minutesPerCycle` is always an integer: no timer rounding or uneven stage allocation is needed.

**Examples:**

| Cycles | Minutes per cycle | Time per stage | Maximum planned session time |
|---:|---:|---:|---:|
| 1 | 5 | 1:00 | 5:00 |
| 3 | 5 | 1:00 | 15:00 |
| 3 | 10 | 2:00 | 30:00 |
| 2 | 7 | 1:24 | 14:00 |
| 1 | 1 | 0:12 | 1:00 |

**Important:** The displayed planned session time assumes **no stages are skipped**. If the user presses Space to advance early, the actual practice will finish sooner. Remaining unused seconds are **not** redistributed to subsequent stages or cycles.

- Inputs validate positive integers within their supported ranges.
- Invalid or empty entries cannot start a session; show an inline correction message.
- Both preferences may be remembered locally and prefilled next time.

### 4.3 Begin and automatically advance

- On **Begin Meditation**, enter the Running state at **Stage 1, Cycle 1**.
- Highlight Stage 1, show its corresponding picture, and start the countdown at the configured **seconds per stage**.
- When the current stage reaches zero, automatically advance to the next stage, restarting the countdown with the full stage duration.
- Stages advance **clockwise** through the circle, without rearranging their positions.
- When Stage 5 ends, increment the completed-cycle count by one.
- If more cycles remain, transition back to Stage 1 of the next cycle.
- When the final Stage 5 ends in the final requested cycle, transition to the completion state.

### 4.4 Space bar: advance the current step

**Primary manual shortcut: `Space` = Next Stage.**

- While the meditation is **Running**, one Space bar press immediately advances **one stage** and discards only the unused time of that stage.
- The next stage starts with a **fresh full-duration countdown**.
- Example: in a five-minute cycle, Stage 1 begins with `01:00`. After `00:20` have elapsed, the user presses Space. The app immediately highlights **Stage 2**, starting its timer at `01:00`.
- **Do not interpret Space as “Skip Current Cycle.”** It always moves by exactly one stage, not directly to the next round.
- On **Stage 5**, Space completes the current five-stage round. If another round remains, Stage 1 of the next round begins; otherwise, the session completes. This is the normal stage boundary, not a skip-cycle command.
- A manually advanced stage still counts as *visited*. Completed cycles increase only after the progression has passed through **Stage 5**, either by timer expiry or a deliberate Space press.
- No unused time is carried over to the next stage.

**Keyboard interaction safeguards:**

- React to the **initial key press**, not key-repeat events caused by holding Space; one physical key press must never jump through multiple stages.
- Space is active as **Next Stage only while Running**. On the Ready, Paused, confirmation, or Complete screens, it must not advance meditation stages.
- When an input field is active on the setup screen, Space must not accidentally start/advance meditation.
- Provide a discreet visible cue such as **`Space · Next stage`** so the action is discoverable.
- If a keyboard event coincides with automatic timer expiry, handle the transition atomically: do not double-advance.
- Avoid excessively sensitive clicks or button behavior that might unexpectedly advance an extra stage.

**Examples of manual progression:**

```text
Stage 1 -- Space --> Stage 2
Stage 2 -- Space --> Stage 3
Stage 3 -- time expires --> Stage 4
Stage 4 -- Space --> Stage 5
Stage 5 -- Space --> Cycle completed; next cycle or session end
```

### 4.5 Pause, resume, restart, and close

- **Pause:** freeze the countdown on the current stage and preserve all progress.
- **Resume:** continue from the exact remaining time.
- **Restart session:** return to Stage 1 of Cycle 1, restore the full stage countdown, and reset completed cycles to 0. Confirm before discarding an ongoing session.
- **End session:** allow leaving before completing the requested cycles; confirm if progress would be discarded.
- **Escape:** while Running, pause and reveal subtle controls; do not immediately abandon the session.
- **Close/hide full-screen window:** pause automatically. Clicking the menu bar icon again should restore the paused session.
- **Space while paused:** does not advance; use Resume first.
- When the Mac sleeps, locks, or the window loses focus, prefer **pausing** rather than silently progressing while the practitioner is away.

### 4.6 Session completion

After all requested cycles have been traversed:

- Stop the countdown and show a quiet **Meditation Complete** state.
- Display **completed cycles** and **actual active meditation time**.
- Optionally distinguish the **planned duration** from the **actual time practiced** when manual advances shortened the session (for example, `Practiced 12:40 · Planned 15:00`). Do not label the shorter time as an error.
- Offer **Practice Again** and **Close**.
- Closing returns to the menu bar utility, not a terminated app.

## 5. Full-Screen Visual Design

### 5.1 Visual direction

The design should feel **spiritual, beautiful, serene, and contemplative**. Favor softly luminous gold/ivory elements, deep indigo or midnight-blue backgrounds, gentle gradients, very subtle glows, and large amounts of visual breathing room.

- **Use the five user-provided pictures as the primary visual content.**
- The background can be created with **native gradients, simple vector ornamentation, and soft light effects**. It must not depend on fetching or generating images online.
- Subtle motion is acceptable for active-stage transitions, but **do not rotate the actual stage positions** or create constant distracting animation.
- Use attractive, legible Devanagari typography. Spiritual character should come from composition, restraint, color, and imagery — not at the expense of readability.

### 5.2 Suggested composition

- The five stage cards sit on a true circular/elliptical orbit as needed for the display's proportions.
- **Stage 1 is at 12 o'clock**, followed by Stages 2–5 clockwise at equal angular intervals.
- Each card includes the **supplied picture**, a short stage label, and a clear active/inactive treatment.
- The active card gets a subtle halo or brighter frame. Inactive cards remain recognizable but visually subdued.
- A central **focus area** may show an enlarged view of the active supplied picture plus the active stage name, provided it does not obscure the ring. Reuse the supplied image rather than requiring additional artwork.
- Keep a discreet information strip in a corner or near the bottom: `Stage 2 / 5 · 00:47 left · Cycles 1 / 3`.
- Controls remain minimal and visually subordinate; the active meditation should be the focal point.

**Conceptual structure (not exact geometry):**

```text
                           [1 + PICTURE]

            [5 + PICTURE]                 [2 + PICTURE]

                          ACTIVE PICTURE
                          ACTIVE STAGE

            [4 + PICTURE]                 [3 + PICTURE]

      Stage 2 / 5       00:47 remaining       Cycles 1 / 3
                   Space · Next stage
```

This is a rough *content placement* illustration. Actual implementation must use equal angular spacing, stable stage order, and a layout that remains readable on a laptop screen.

### 5.3 Pictures and image treatment

- Avoid heavy filters that change the meaning or appearance of the supplied spiritual art.
- Preserve picture aspect ratio; use consistent containers and a refined frame/background as needed.
- Avoid aggressive blur or darkening over the active picture. Inactive images may have restrained opacity changes.
- Show a graceful, short image transition when the active stage changes, without flicker or blank frames.
- Preload the five bundled pictures so Space presses and timer transitions feel instantaneous.
- Test with the actual supplied pictures before approving final color, typography, cropping, and layout.

### 5.4 Typography and accessibility

- Use a high-quality readable Devanagari typeface with proper glyph shaping and a redistribution-compatible license.
- Provide sufficient contrast and comfortable type sizes on common MacBook and external-monitor resolutions.
- Keep focus states, shortcuts, and all setup controls keyboard-accessible.
- Respect macOS **Reduce Motion** by replacing decorative movement with static highlight changes.
- Do not use brightness/color alone to identify the active stage; reinforce with border, emphasis, or active title.

## 6. Status Information

The following information is visible but intentionally inconspicuous during Running and Paused states:

| Information | Example | Behavior |
|---|---|---|
| Current step | `Stage 2 / 5` | Changes on timer expiry or Space. |
| Remaining stage time | `00:47` | Counts down only while Running; resets when entering the next stage. |
| Completed cycles / target | `1 / 3 cycles` | Increments only after leaving Stage 5. |
| Manual shortcut hint | `Space · Next stage` | Small, readable, never dominates the composition. |

A progress arc or ring may reinforce the countdown; it must not compete with the five pictures. Avoid adding prominently displayed statistics or extra widgets.

## 7. Functional Requirements and Acceptance Criteria

| ID | Priority | Requirement | Acceptance criteria |
|---|---|---|---|
| FR-01 | P0 | Menu bar entry | Clicking the menu bar icon opens the full-screen experience. |
| FR-02 | P0 | Full-screen setup | Ready screen includes cycle count, minutes per cycle, computed time per stage, and Begin. |
| FR-03 | P0 | Five fixed stages | Stages 1–5 occupy a clockwise circular layout, starting at 12 o'clock. |
| FR-04 | P0 | Five supplied images | Exactly the five assigned product-owner images appear with their correct stages; no online image sourcing is required. |
| FR-05 | P0 | Cycle count input | User can choose a valid positive whole number of cycles; invalid input cannot start. |
| FR-06 | P0 | Minutes-per-cycle input | User can choose total whole minutes for a cycle; not minutes per stage. |
| FR-07 | P0 | Equal stage durations | Every stage receives `minutesPerCycle × 12` seconds at the start of that stage. |
| FR-08 | P0 | Automatic advance | When a running stage expires, precisely one next-stage transition occurs. |
| FR-09 | P0 | Space to next stage | One Space press during Running advances exactly one stage immediately, with no duration carryover. |
| FR-10 | P0 | Space at Stage 5 | Space on Stage 5 completes that cycle and starts Stage 1 of the next cycle, or ends the session if it was the final cycle. |
| FR-11 | P0 | Key-repeat and race protection | Holding Space or pressing it at timer expiry never causes accidental multi-stage jumps. |
| FR-12 | P0 | Repeat and completion | Session ends only after Stage 5 of the target cycle is traversed, whether automatically or manually. |
| FR-13 | P0 | Discreet progress | Current step, remaining stage time, and completed/target cycles are accurate and visible. |
| FR-14 | P0 | Pause and resume | Remaining time and stage position remain unchanged while paused. |
| FR-15 | P0 | Safe close/reopen | Hiding the window pauses the session; reopening restores it. |
| FR-16 | P0 | Restart and end | Explicit controls work, with confirmation before discarding progress. |
| FR-17 | P0 | Local images and offline use | All five bundled images and timer features work without network access. |
| FR-18 | P0 | Completion view | Reports cycles completed and actual active practice time, which may be shorter than planned due to Space presses. |
| FR-19 | P1 | Local preferences | Cycle count and minutes-per-cycle values may be remembered across launches. |
| FR-20 | P1 | Responsive, accessible UI | Stage images and names are readable across common screen sizes; Reduced Motion is respected. |

**Priorities:** P0 = necessary for the first functional release; P1 = polish expected for the first finished release.

## 8. Timing, Counting, and State Logic

### 8.1 Definitions

```text
targetCycles          = selected positive integer
minutesPerCycle       = selected positive integer
stagesPerCycle        = 5
stageDurationSeconds  = minutesPerCycle * 12
plannedSessionSeconds = targetCycles * minutesPerCycle * 60
completedCycles       = 0 initially
currentStage          = 1 initially
actualActiveSeconds   = elapsed time during Running only
```

### 8.2 Transition rules

1. Entering a stage always initializes its remaining time to `stageDurationSeconds`.
2. A transition occurs from either **timer expiration** or **one deliberate Space press**.
3. Both event types share the same transition function; process at most one stage transition for the same boundary/event.
4. For Stages 1–4, advance to the next stage without changing `completedCycles`.
5. On leaving Stage 5, increment `completedCycles` by 1.
6. If `completedCycles < targetCycles`, begin Stage 1 of the next cycle.
7. Otherwise, end the meditation session and show Complete.
8. If a stage is manually advanced early, its unused duration is **discarded**. Do not transfer it to another stage or subtract it from a later stage's fresh countdown.
9. While Paused, no elapsed time is accumulated and Space cannot move the current stage.
10. Time during app sleep, screen lock, and app absence is not counted as active meditation.

The timer should use a **monotonic clock** with pause-aware elapsed time rather than depending on UI update callbacks firing at precise one-second intervals. Update the display at least once each second, without negative countdown values or inconsistent cycle counts.

### 8.3 Session states

| State | Display | Valid actions |
|---|---|---|
| Ready | Circular preview, images, cycle input, minutes-per-cycle input, calculated duration | Begin, Close |
| Running | Five-stage ring, active image/title, countdown, cycle count, Space hint | Space (next stage), Pause, reveal controls |
| Paused | Same stage and frozen countdown, restrained pause indication | Resume, Restart, End, Close |
| Confirming | Confirmation before discarding active progress | Confirm, Cancel |
| Complete | Calm completion message, cycles, actual time | Practice Again, Close |

## 9. macOS Product Behavior

- Prefer **SwiftUI** for the interface, with **AppKit** where required for menu bar and full-screen window handling.
- The normal entry point is a menu bar status item; avoid depending on a permanent standard Dock window.
- Opening from the status item must show a true full-display meditation window, not a small `NSPopover`.
- If feasible, use a full-screen borderless window on the current desktop instead of causing a disruptive macOS Space transition.
- Use sensible display selection for multi-monitor setups and preserve control accessibility on smaller screens.
- Provide a clear way to close the full-screen view and to quit the utility itself.
- Image files and preferences are kept locally. The five pictures are packaged with the app.
- The minimum supported macOS version is a technical implementation decision; set it before development.

## 10. Quality Requirements

**Reliability:** Stage progression, skipping, and cycle counting must be correct even when a key press happens near a timer boundary. A dropped animation frame must not corrupt timing.

**Performance:** Remain lightweight while idle in the menu bar. Load the five pictures once; avoid unnecessarily heavy continuous animation.

**Presentation:** Artwork must remain sharp, appropriately scaled, and unobstructed. Text must not overlap pictures or become microscopic on common display sizes.

**Responsiveness:** Space should visibly switch to the next stage promptly. Do not delay state transitions for a decorative animation.

**Privacy and autonomy:** The session runs locally without requiring network connectivity. The app uses the pictures the product owner provides, not web-fetched imagery.

## 11. User Stories

- As a practitioner, I want to open the meditation from the menu bar so I can begin without navigating through other apps.
- As a practitioner, I want to choose **how many cycles** to complete.
- As a practitioner, I want to choose **how many minutes one full cycle lasts**, with that time divided evenly across all five forms.
- As a practitioner, I want to see the **five pictures I have supplied**, arranged in their correct spiritual order.
- As a practitioner, I want the active picture and name emphasized so my attention naturally rests on the form being contemplated.
- As a practitioner, I want the timer to advance automatically when I do nothing.
- As a practitioner, I want to press **Space** when I finish a stage early and immediately move to the *next stage*, not skip the whole cycle.
- As a practitioner, I want unobtrusive time and completed-cycle indicators so I can orient myself without distraction.
- As a practitioner, I want to pause and later resume at the same stage and remaining time.

## 12. Acceptance Test Scenarios

| # | Setup/action | Expected result |
|---|---|---|
| 1 | 1 cycle; 5 minutes per cycle; no manual skips | 5 stages × 60 seconds; completion after 5:00 active time. |
| 2 | 3 cycles; 10 minutes per cycle; no manual skips | 15 stages × 2:00; completion after 30:00 active time. |
| 3 | 2 cycles; 7 minutes per cycle | Each stage receives 1:24; planned session is 14:00. |
| 4 | Stage 1 has run for 20 seconds of a 60-second allocation; press Space | Stage 2 appears immediately at 1:00; no remaining Stage 1 time is carried over. |
| 5 | During Stage 3, press Space once | Stage 4 starts; completed-cycle count does not change. |
| 6 | During Stage 5 of Cycle 1 of 3, press Space | Completed cycles becomes 1; Stage 1 of Cycle 2 starts. |
| 7 | During Stage 5 of the final cycle, press Space | Completed-cycle count reaches the target; session completes immediately. |
| 8 | Hold down the Space bar | Only the initial non-repeat keydown advances one stage; repeated keydowns do not cascade through stages. |
| 9 | Press Space at almost the exact instant a stage expires | Exactly one transition is accepted, not two. |
| 10 | Pause with 0:37 left; wait; resume | The same stage resumes with approximately 0:37 left, subject only to display rounding. |
| 11 | Hide, then reopen, the full-screen window | The same session reappears paused with its progress intact. |
| 12 | Complete a session with some early Space advances | Completed cycles equals target, and actual active time is less than or equal to planned time. |
| 13 | Disconnect from the internet | Full session, including all five supplied images, functions normally. |
| 14 | Verify the supplied five-image asset map | Each stage shows exactly its matching picture; no online image is displayed or downloaded. |
| 15 | Enter 0/negative/blank/non-integer cycle or minute values | Begin is blocked and a readable validation message appears. |
| 16 | Switch apps, lock the screen, or put the Mac to sleep mid-stage | No unattended stage progression; the user returns to a paused state. |
| 17 | Enable Reduce Motion and use a smaller laptop display | Stages remain distinguishable and readable, with nonessential motion suppressed. |

## 13. Deliverables and Release Readiness

The first implementation is ready when it supports:

- A dependable **menu bar → full-screen** opening flow.
- A beautiful, readable **five-picture circular display** using the product owner's actual supplied images.
- Two setup inputs: **number of cycles** and **minutes per cycle**.
- Equal timer allocation to each of the five stages.
- Automatic stage progression and automatic cycle repetition.
- Reliable **Space = next stage** behavior (including Stage 5 and key-repeat safeguards).
- Accurate, unobtrusive status counters and simple pause/resume/end interactions.
- Correct final completion behavior, even if the user manually advanced some stages.
- Fully local operation and a polished experience on common Mac displays.

**Definition of success:** A user can begin a chosen number of Swadarshan Chakra rounds, contemplate the five supplied pictures one by one, let the timer guide the transition, or advance a single stage with Space whenever ready — all without the interface becoming the center of attention.

## 14. Items to Confirm Before Implementation

These are limited to details that genuinely depend on supplied materials or final product decisions:

1. **The five image files:** Receive the actual pictures and confirm which file corresponds to each of the five stages. Evaluate aspect ratios and resolution with the final visual layout.
2. **Exact Hindi display spelling:** Confirm the final five names as they should appear in the app.
3. **Visual layout with real pictures:** Finalize image sizes, center-focus treatment, and gradient colors after seeing the actual art.
4. **Maximum input values:** The proposed guardrails of 1–108 cycles and 1–120 whole minutes per cycle may be adjusted if preferred.
5. **Minimum macOS version:** Choose based on the native menu bar and full-screen UI implementation.

## 15. Engineering Handoff Summary

Build a **native macOS menu bar meditation app** whose menu bar icon opens a **full-screen, spiritual five-picture circular interface**. The five pictures are **provided by the product owner** and bundled locally; never fetch or generate stage pictures online. The user selects **number of cycles** and **total minutes per cycle**. Divide each cycle's duration **equally among the five stages**. Start at Stage 1 and advance automatically as each timer expires. During Running, **Space advances exactly one stage immediately**, discarding the unused seconds for that stage without carrying them over. Passing through Stage 5 completes one cycle; the session repeats until the selected number of cycles is finished. Keep the stage name, countdown, and cycle count subtle. Preserve pause/resume and safe window behavior. Make the presentation peaceful, aesthetically refined, responsive, and reliable.

**This document specifies the product only. It does not include application source code or an implementation.**
