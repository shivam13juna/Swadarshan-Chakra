# Swadarshan Chakra

A native macOS menu bar meditation app, implemented from [prd_v2.md](prd_v2.md) and the product updates recorded at its top. During each step, its supplied picture fills the entire display, scaled proportionally and cropped to fit. A small Hindi title, timer, and controls sit over the picture's edges. The five-picture circle remains the overview before and after practice.

## Open the app

The built application is at **`dist/Swadarshan Chakra.app`**. Double-click it in Finder, or run:

```sh
open "dist/Swadarshan Chakra.app"
```

The first launch opens setup in native macOS full-screen mode, in its own Space. The menu bar and Dock hide automatically, as they do in other full-screen Mac apps. Later, click the supplied gold chakra icon in the menu bar to reopen it. Close the window with its × button or **⌘W**; the app exits the full-screen Space, stays in the menu bar, and preserves an ongoing practice in a paused state. Right-click the menu bar icon to quit.

Choose **1–108 cycles** and **Time per step**, entered as minutes and seconds. Every one of the five forms receives that full duration. The app calculates the cycle and session totals automatically: **1 minute per step → 5 minutes per cycle**; **3 cycles at 2 minutes per step → 30 minutes planned**. A step can last from 1 second to 120 minutes. Your valid selections are remembered when you begin.

Saved settings from the earlier version retain their original pace. For example, an old five-minute cycle becomes `1 min : 00 sec` per step; an old seven-minute cycle becomes `1 min : 24 sec` per step.

| Control | Action |
| --- | --- |
| Return in setup | Begin meditation |
| Space while running | Move exactly one stage forward, with a fresh full countdown |
| Esc while running | Pause and show session controls |
| Return while paused | Resume |
| ⌘R while paused | Request a restart |
| ⌘E while paused | Request an end |
| Esc in a confirmation | Keep the current practice |
| ⌘Return in a confirmation | Confirm restart/end/quit |
| ⌘W / ⌘H | Close or hide, preserving a paused session |
| ⌘Q | Quit; an unfinished practice requires confirmation |
| Return after completion | Return to setup for another practice |

Holding Space does not repeatedly advance. Space is inactive in setup, pause, confirmation, and completion. Switching apps, losing the window's focus, sleeping, or locking pauses progress. Resume is always deliberate. Completion shows completed cycles, actual active time, and the originally planned time.

## Build

Requires **macOS 13 or newer** and **Swift 5.9 or newer**. Apple Command Line Tools are sufficient; there are no third-party dependencies, package downloads, web views, or servers.

```sh
./scripts/build-app.sh --launch
```

This builds a release executable for the current Mac's architecture, creates the `.app` in `dist`, embeds all five pictures, packages the supplied `icon.png` as the app icon, and applies a local ad-hoc signature. The Finder/Dock icon places the chakra at 95% of a rounded tile's width, leaving a narrow neutral rim instead of macOS adding a wider frame around the circular artwork. The original transparent PNG is used in the app header, confirmation dialogs, and menu bar; its bundled copy is verified against the original. The app bundle can be moved to Applications. For a debug build, add `--debug`. The build is signed in a staging directory before replacing the previous bundle; a copy of the previous build stays in the hidden `dist/.app-build.*` directory.

This is a local build. Developer ID signing and Apple notarization for public distribution are separate release steps.

## Verify

```sh
./scripts/check.sh
```

This verifies the original artwork and supplied icon, runs **28 deterministic core checks / 367 assertions**, and compiles the app. The standalone check runner avoids an XCTest dependency, so full Xcode is not needed. Its scenarios cover per-step timing and automatic totals, saved-setting migration, complete automatic sessions, manual steps, Stage 5 boundaries, key repeat, both orderings of timer/key collisions, stale keyboard events, pause/resume, confirmations, absence, validation, and actual practice time.

The app also provides development checks:

```sh
# Verify that a packaged app can decode its own embedded pictures.
"dist/Swadarshan Chakra.app/Contents/MacOS/SwadarshanChakra" --verify-resources

# Verify the live 12-second per-step timer without opening a window.
"dist/Swadarshan Chakra.app/Contents/MacOS/SwadarshanChakra" --verify-timer

# Exercise the actual full-screen window, keyboard event loop, live 12-second timer,
# menu bar/Dock hiding, reopening, lifecycle handlers, and completion. Takes about 30 seconds.
# Requires an unlocked Mac. This opens a test window and uses isolated preferences. The long timer
# probe runs independently so switching apps does not interrupt that probe.
"dist/Swadarshan Chakra.app/Contents/MacOS/SwadarshanChakra" --smoke-test

# Capture native SwiftUI/AppKit screens, including smaller layouts and validation.
"dist/Swadarshan Chakra.app/Contents/MacOS/SwadarshanChakra" --render-previews .artifacts/native-fullscreen-previews
```

## Artwork and wording

| Logical ID | Original file | Stage |
| --- | --- | --- |
| `stage_01` | `5_pictures/pic_1.png` | बीज रूप — परमधाम में |
| `stage_02` | `5_pictures/pic_2.jpg` | विश्व महाराजन — सतयुग में |
| `stage_03` | `5_pictures/pic_3.png` | पूज्य स्वरूप — द्वापर युग में |
| `stage_04` | `5_pictures/pic_4.png` | परम पवित्र ब्राह्मण — कलियुग में |
| `stage_05` | `5_pictures/pic_5.png` | फरिश्ता स्वरूप |

The numbered files are mapped explicitly in `Sources/MeditationCore/Stage.swift`. The Hindi names preserve the PRD's spelling. Copies in `Sources/SwadarshanChakra/Resources/Artwork` are byte-identical to the originals; packaging fails if a file is missing, added, or changed. During running and paused steps, the active image uses centered aspect fill: it covers the display without stretching, with excess edges cropped as needed for the screen's proportions. Overview thumbnails use aspect fit. Images are decoded once at up to 4096 pixels without modifying the bundled originals. The app uses macOS's Kohinoor Devanagari font and respects Reduce Motion for image transitions.

## Implementation

- `Sources/MeditationCore`: validated configuration, immutable stage catalog, and a deterministic session state machine.
- `Sources/SwadarshanChakra/SessionModel.swift`: the main-actor UI adapter, monotonic uptime clock, local preferences, and a timer that exists only while running.
- `Sources/SwadarshanChakra/AppMain.swift`: the AppKit status item, current-display borderless window, native keyboard handling, and lifecycle observations.
- `Sources/SwadarshanChakra/FullScreenStageView.swift`: the active image filling the display, with small controls and local edge shading for readability.
- `Sources/SwadarshanChakra/*View.swift`: native SwiftUI layout, active artwork, progress, and confirmation states.
- `Tests/MeditationCoreTests`: executable core checks with no external test framework.

The window enters a native full-screen Space on the selected display using AppKit's full-screen transition. AppKit owns the menu bar and Dock presentation for that Space, and the controls respect the display's top safe area. The app uses regular activation while its window is open and returns to accessory activation when closed, so it remains a menu bar utility while idle. Closing and reopening wait for the native transition to finish, preserving the paused session. Session progress is kept in memory until explicitly ended, restarted, or the utility quits; it is not a persistent session history.

Every progression event goes through one serialized transition function. A 150 ms window coalesces Space with automatic expiry at the same boundary, while deliberate successive manual presses remain possible. A stage always receives its full allocation on entry. If the event loop goes unobserved for more than 2.5 seconds, the practice pauses at its last observed time instead of progressing unattended. Normal small callback delays are measured with the monotonic clock; a stage's active-time contribution is capped at its allocation.

Native framework references: Apple's [NSStatusItem](https://developer.apple.com/documentation/appkit/nsstatusitem), [full-screen windows](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/fullscreenprimary), [full-screen presentation options](https://developer.apple.com/documentation/appkit/nswindowdelegate/window(_:willusefullscreenpresentationoptions:)), and [NSWorkspace](https://developer.apple.com/documentation/appkit/nsworkspace).
