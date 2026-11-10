# Implementation verification

Validated on this Mac with macOS 27.2, Apple Silicon, and Swift 6.3.3. The app's deployment target is macOS 13.0. The delivered bundle is version 1.2.0 (build 6), a local, ad-hoc-signed release build for Apple Silicon. Version 1.2.0 changes stage 4's context to संगम युग में, adds a cycle counter above the step counter, orders the shortcut hints like their buttons, adds total-time entry, opens every cycle with a three-second card, and lets meditation run in an ordinary window: the standard window buttons are shown, leaving full screen (green button, View ▸ Exit Full Screen, ⌃⌘F) keeps the meditation open, and an "Open in full screen" setting (on by default) decides how it opens. The native full-screen smoke test has been updated for these changes, including new checks for leaving full screen and for the setting, but was not re-run on 1.2.0, because it takes over the display for about 45 seconds; its last passing run was on version 1.1.1. The GitHub release workflow has not yet run on GitHub; its packaging steps were run locally.

| Check | Result |
| --- | --- |
| Deterministic session engine and settings | 37 checks, 537 assertions, zero failures |
| Packaged release native integration | 43 checks passed on version 1.1.1; updated for cycle cards and total time in 1.2.0, not yet re-run |
| Total time | Shared equally by every step; the planned total stays exact for uneven splits (10 minutes for 7 cycles); minimum of 1 second per step, 600-minute maximum, mode switching that keeps the practice, and saved-setting fallback covered |
| Cycle cards | Every cycle opens with a card that uses no practice time; Space begins the first step early, pausing begins the cycle with a full first step, a key press at the card's end is coalesced, and the last cycle ends in completion |
| Native full screen | Window style and system state both confirm native full-screen mode; `NSMenu.menuBarVisible()` confirms the menu bar is hidden; Dock auto-hide is enabled (1.1.1 run). Leaving full screen into an ordinary window and the "Open in full screen" setting are covered by the updated smoke test, not yet run |
| Window lifecycle | Close exits full screen and restores menu-bar-only operation; reopening preserves the exact paused timer; reopening during an exit transition also passes |
| Focus and absence | Actual key-window transfer pauses practice; local sleep notification and the lock handler pass |
| Packaged release live timer | All four 1.2.0 checks passed: practice opens with the Cycle 1 card, the card lasts three seconds before a full first step, 12 seconds per step advances exactly once, and the next step receives a fresh full countdown |
| Release packaging | The workflow's zip and SHA-256 steps run locally; the checksum verifies and the unzipped app's signature passes `codesign --verify --deep --strict` |
| Input validation | Invalid cycles, zero-length steps, blank values, negatives, decimals, and out-of-range components rejected |
| Per-step timing | Minutes and seconds are assigned in full to every step; cycle and session totals are calculated automatically |
| Saved settings | Exact legacy conversion (including 7 minutes per cycle → 1:24 per step), new-setting precedence, persistence, and invalid-value fallback covered |
| Space and cycle boundaries | Single-stage advance, held-key rejection, stale event rejection, both timer/key race orderings, and final Stage 5 completion covered |
| Pause and confirmation | Exact remaining time preserved; paused Space ignored; restart/end/quit and cancellation covered |
| Original artwork | All five embedded images match the supplied files byte for byte |
| Supplied branding | Bundled `Branding/icon.png` matches the owner's original exactly; the header, dialogs, menu bar, and application icon use that supplied image |
| System app icon (1.1.2) | Actual macOS icon renders inspected at 32 px and 256 px; the chakra is larger with a narrower white rim, and the release signature passes |
| Bundled resources | Release app successfully decoded all five images from its own Contents/Resources directory |
| Local code signature | `codesign --verify --deep --strict` passed for the release bundle |
| Native layout captures | Twenty-four screens rendered, including all five active pictures, setup, pause, completion, confirmation, invalid input, long duration totals, cycle cards, total time (even and uneven splits, and a too-short total), and a paused second cycle |
| Display sizes inspected | 1440×900, 1280×800, 1024×640, 2560×1080, and 900×1440 points |
| Artwork presentation | Active pictures fill the entire window with proportional scaling and centered cropping; overlays remain visible in compact, wide, and portrait layouts |

Reproduce the checks with the commands in [README.md](README.md). Current layout captures are in `.artifacts/v1.2-previews`; the successful packaged-release integration run, including the live-timer checks and actual menu-bar visibility result, is in `.artifacts/release-fullscreen-smoke.log`. Interactive testing requires an unlocked desktop. Layout captures render the app's content; native full-screen and menu-bar behavior are verified separately by the integration run.

Before/after system icon captures are `.artifacts/icon-before-32.png`, `.artifacts/icon-after-32.png`, `.artifacts/icon-before-256.png`, and `.artifacts/icon-after-256.png`. These are rendered through `NSWorkspace.icon(forFile:)` from the app bundles, including macOS's icon treatment.

Physical sleep/wake, physical screen locking, multi-monitor hardware changes, and a full VoiceOver walkthrough were not performed. macOS 13 compatibility is set in the build and app metadata but has not been exercised on a separate macOS 13 machine. Reduce Motion is handled through SwiftUI's accessibility environment; no global accessibility preferences were changed during verification.
