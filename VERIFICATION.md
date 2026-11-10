# Implementation verification

Validated on this Mac with macOS 27.2, Apple Silicon, and Swift 6.3.3. The app's deployment target is macOS 13.0. The delivered bundle is version 1.1.2 (build 5), a local, ad-hoc-signed release build for Apple Silicon. This update adjusts only the application icon composition and preserves the packaged icon when the app launches; the session and full-screen checks below passed on version 1.1.1.

| Check | Result |
| --- | --- |
| Deterministic session engine and settings | 28 checks, 367 assertions, zero failures |
| Packaged release native integration | 43 checks passed on version 1.1.1; session and full-screen code unchanged in 1.1.2 |
| Native full screen | Window style and system state both confirm native full-screen mode; `NSMenu.menuBarVisible()` confirms the menu bar is hidden; Dock auto-hide is enabled |
| Window lifecycle | Close exits full screen and restores menu-bar-only operation; reopening preserves the exact paused timer; reopening during an exit transition also passes |
| Focus and absence | Actual key-window transfer pauses practice; local sleep notification and the lock handler pass |
| Packaged release live timer | Both checks passed: 12 seconds per step advances exactly once, and the next step receives a fresh full countdown |
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
| Native layout captures | Seventeen screens rendered, including all five active pictures, setup, pause, completion, confirmation, invalid input, and long duration totals |
| Display sizes inspected | 1440×900, 1280×800, 1024×640, 2560×1080, and 900×1440 points |
| Artwork presentation | Active pictures fill the entire window with proportional scaling and centered cropping; overlays remain visible in compact, wide, and portrait layouts |

Reproduce the checks with the commands in [README.md](README.md). Current layout captures are in `.artifacts/native-fullscreen-previews`; the successful packaged-release integration run, including the live-timer checks and actual menu-bar visibility result, is in `.artifacts/release-fullscreen-smoke.log`. Interactive testing requires an unlocked desktop. Layout captures render the app's content; native full-screen and menu-bar behavior are verified separately by the integration run.

Before/after system icon captures are `.artifacts/icon-before-32.png`, `.artifacts/icon-after-32.png`, `.artifacts/icon-before-256.png`, and `.artifacts/icon-after-256.png`. These are rendered through `NSWorkspace.icon(forFile:)` from the app bundles, including macOS's icon treatment.

Physical sleep/wake, physical screen locking, multi-monitor hardware changes, and a full VoiceOver walkthrough were not performed. macOS 13 compatibility is set in the build and app metadata but has not been exercised on a separate macOS 13 machine. Reduce Motion is handled through SwiftUI's accessibility environment; no global accessibility preferences were changed during verification.
