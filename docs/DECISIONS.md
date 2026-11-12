# desarray. — Decision log

Legend: **Fact** = observed on hardware below. **Hypothesis** = untested, do not rely on it.

## Environment (2026-11-12)

- macOS 27.0.1 (26A434), Xcode 27.2 (27B52), Swift 6.4.2, arm64.
- Display: one built-in Liquid Retina XDR, 1800×1169 pt @2x. **No external display available** — multi-display, mixed-scale, negative-origin, rotation and hot-plug cases are untested.
- Project generated with XcodeGen (`project.yml`); `.xcodeproj` is a build artifact.

## D1 — Minimum macOS: 14.0 (Hypothesis, provisional)

Needs `@Observable` (14) and `MenuBarExtra` (13). Nothing used in Phase 1 needs newer. Only tested on 27.0.1; revisit after testing on 14.

## D2 — Canonical geometry: global top-left logical points

Same space as CoreGraphics display bounds and AX. Cocoa (bottom-left) is converted at the rendering boundary only, via `ScreenSpace` in `DesarrayGeometry`.

- **Fact (spike `Spikes/coords.swift`):** `NSScreen.frame` flipped by primary-screen height == `CGDisplayBounds`; flipped `NSEvent.mouseLocation` == `CGEvent.location`; AX `kAXPositionAttribute` frame contained the CG pointer (AXScrollArea in Claude.app). Single display only.
- Pixel conversion uses the selection's own display `backingScaleFactor`, never the main display's.

## D3 — Cross-display selections: clipped to the display where the drag began

Disclosed in the inspector ("clipped to <display>"). Per-display segments deferred until multi-display hardware is available to test.

## D4 — App lifecycle: `LSUIElement` menu-bar app (`MenuBarExtra`)

No Dock icon. Inspector and overlay are AppKit `NSPanel`s.

## D5 — Global shortcut: Carbon `RegisterEventHotKey`, default ⌥⇧D

No Input Monitoring / event-tap permission required (Hypothesis based on API docs; confirm on clean machine). Registration failure (e.g. `eventHotKeyExistsErr`) is shown in the menu; menu item always works. User-configurable shortcut: not in Phase 1.

## D6 — Overlay input: one borderless `NSPanel` per screen, shown only during an active session

Panels are ordered out when the session ends, so nothing intercepts input while inactive. Escape: first clears selection, second ends session.

## D7 — Permissions (spike)

- **Fact:** `AXIsProcessTrusted()` and `CGPreflightScreenCaptureAccess()` both true for the spike — but trust is inherited from the host process. desarray.app's own onboarding is **untested**; Phase 1 requests neither.

## D8 — Distribution: undecided

Not tested. No signing, notarization, or sandbox claims made. Phase 1 build is unsigned/ad-hoc for local use.

## D9 — Packages

One local package `Packages/DesarrayCore` with two library targets: `DesarrayDomain` (evidence/provenance/selection models, Foundation only) and `DesarrayGeometry` (rects, transforms, metrics, grid). Other packages from the spec are created when their phase starts.

## Phase 0 spikes not done yet

- Screen capture + self-window exclusion (needs ScreenCaptureKit stream with desarray's windows; do at Phase 3 start).
- AX across Finder / SwiftUI app / browser matrix and `AXObserver` support (Phase 2 start).
- Clean-machine permission onboarding, signed build, distribution route.

## Phase 1 verification (2026-11-12, single built-in Retina display, macOS 27.0.1)

- `swift test --package-path Packages/DesarrayCore` — 14 tests / 4 suites pass (flip, negative origins, reverse drags, clipping, 4pt vs 4px, alignment tolerance, provenance round-trip).
- In-app self-test (DEBUG only): `desarray.app/Contents/MacOS/desarray -selftest <dir>` drives the real overlay view with synthetic events — reverse drag, off-edge clip, click-clears, move, nudge/resize, Esc×2, 30 start/stop cycles with 0 stuck overlays — and captures `overlay.png` + `inspector.png`. All PASS. It caught one real bug (a plain click kept the previous selection), now fixed.
- **Not verified:** ⌥⇧D hotkey via real keyboard, real pointer delivery through the window server, multi-display, Spaces/full-screen apps, sleep/wake, VoiceOver pass, latency targets (no Instruments run yet).

## D10 — Live x-ray + capture window (2026-11-12), replaces the floating inspector

- **Live x-ray:** while a frame is on screen, `AXProbe.snapshot` reads the topmost *foreign* window under it (CG window list, own PID skipped), walks its AX tree pruned to the frame (budget 2500 nodes / 150 ms / 50 ms per IPC), and `xrayLayout` derives boxes, insets and gaps. Polled at 8 Hz, one query in flight, only during an active session (justified: AX notifications don't cover hover/animation repaint across apps). Stops on exit.
- **Spacing rules (INFERRED):** inset = child edge → parent edge with no sibling between; gap = edge → nearest overlapping sibling below/right; 2–64 pt shown; wrappers with identical frames collapsed.
- **Chromium/Electron:** `AXManualAccessibility=true` is set on the target app; the web tree builds lazily (~0.5–1.5 s on first touch). Fact: Claude.app went 9 → 97 nodes after warm-up.
- **Capture (⏎ / HUD button):** full-budget AX snapshot + `SCScreenshotManager` one-shot with desarray excluded via `SCContentFilter(excludingApplications:)`. Opens a window: screenshot + x-ray, element tree, details with OBSERVED/INFERRED badges, Copy PNG / Save PNG / Copy JSON (schemaVersion 1, per-value evidence + method + limitation). Nothing persisted.
- **Signing:** Apple Development identity (stable designated requirement) so TCC grants survive rebuilds.
- **Verified:** 18 unit tests; `desarray-probe` CLI on Claude.app (Electron); in-app self-test all PASS incl. HUD placement, G/X keys, capture window opening with real image + AX tree (`capture.png`).
- **Not verified:** desarray launched from Finder with its *own* AX/Screen Recording grants (self-test inherits the host's); native AppKit/SwiftUI targets (Finder, System Settings) and Safari; live hover/animation tracking by eye; multi-display.

## D11 — Declutter for dense UIs (2026-11-12)

`declutter()` thins labels only (boxes and JSON export keep everything): repeats with the same kind/axis/value in the same lane show once (top-most); each distinct W×H pill shows once; label budget ≈ 1 per 1600 pt²; the focused element (hover in live mode, list selection in the capture window) is outlined and always gets all its spacings. Unit-tested on a 12-row list (48+ raw spacings → one "4", one "2", one "24×24"). Real dense list not yet checked by eye.
