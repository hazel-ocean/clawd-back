# Plan: Claw-back focus across Spaces and external displays

Status: proposed
Bug: "External display focus" (Clawd Back)

## Problem

Clicking a notification often fails to bring you to the session's window when that window lives on another Mission Control Space or a second monitor. The app activates, but the screen does not travel to the window: you end up looking at whatever window of the terminal happens to be on the current Space, or nothing visibly changes.

Reproductions to confirm (see Phase 0), in rough order of likelihood:

- Target window is on a **different Space of the same display** (the user has "switch to a Space with open windows" turned off).
- Target window is on a **second monitor** with "Displays have separate Spaces" on, so that display has its own current Space distinct from the built-in.
- Target window is **full-screen** (a full-screen window is its own Space).

## Current mechanism (what we do today)

The claw-back is a list of shell steps assembled in `focusPlan` and run by `FocusPlan.runDetached` as **one detached `/bin/sh`**:

1. `sleep 0.3`
2. (zellij) `zellij --session S action focus-pane-id terminal_N`
3. `/usr/bin/open -b com.mitchellh.ghostty` (`TerminalApp.activationStep`)
4. `/usr/bin/osascript ghostty-focus.applescript <winId> <tabId>` which runs `activate window (window id ...)` + `select tab ...`

It runs detached **on purpose**: ClawdBack is launched by the notification click and self-terminates ~0.1s later (`AppDelegate.terminateApp`). If the focus ran in-process and the app then quit, the terminal would regain focus on our quit and reset to its previously-active tab, undoing the select. The detached shell waits out our quit (`sleep 0.3`) so the focus sticks. See the header comment in `Sources/Focus.swift`.

## Root cause

None of steps 3 or 4 can move the screen to a window on another Space:

- **`open -b` / `NSRunningApplication.activate` are advisory on macOS 14+.** `activateIgnoringOtherApps` was deprecated and no longer forces the front switch; activation became a cooperative *request* the current app can decline.
- **Whether activation follows a window to its Space is a user setting, not something the activation call controls.** System Settings > Desktop & Dock > Mission Control > "When switching to an application, switch to a Space with open windows for the application" (`com.apple.spaces AppleSpacesSwitchOnActivate`). Off => activation never changes Spaces. On => macOS picks *a* Space with *any* window of that app, not necessarily our target window/tab.
- **"Displays have separate Spaces" multiplies the problem.** Each display has its own current Space; a window on the external monitor is on that display's Space, a different managed Space from the built-in. A full-screen or tiled window is itself a dedicated Space.
- **AppleScript `activate window` / `select tab`** ride the same AppKit activation path, so they inherit every limitation above. They can pick the right window/tab by id but cannot travel to its Space.

In short: we can name the right window, but we have no call in the current stack that commands WindowServer to switch to that window's Space/display.

## What actually works (grounded in AltTab / yabai / Hammerspoon)

The switchers and window managers all converge on private **SkyLight** calls. The Accessibility API alone (`kAXRaiseAction`, `kAXMainAttribute`, `kAXFocusedAttribute`, `set frontmost`) only reorders windows *within* an app and does **not** cross Spaces, which is exactly our current failure. The load-bearing call is:

```
_SLPSSetFrontProcessWithOptions(&psn, cgWindowId, 0x200 /* userGenerated */)
```

Passing a specific `CGWindowID` fronts *that window* and, for an off-Space target, makes macOS switch to a Space showing it. AltTab's `Window.focus()` is the canonical sequence:

1. `_SLPSSetFrontProcessWithOptions(psn, wid, 0x200)` -- fronts the process + window, triggers the Space switch.
2. `makeKeyWindow(psn, wid)` -- posts a synthetic mouse down/up via `SLPSPostEventRecordTo` at `(-1,-1)` (just off the frame) to move *key* focus across apps, which no public API does.
3. `AXUIElementPerformAction(window, kAXRaiseAction)` -- fixes intra-app window stacking; retry with a freshly resolved element on `.invalidUIElement`.
4. cross-Space only: `SLSSpaceSetFrontPSN(cid, originSpaceId, originPsn)` to repair the Space we came from (otherwise the app we left "pops" a window).

Query helpers used to decide *what* to do: `CGSMainConnectionID`, `CGSCopySpacesForWindows` (is the target off the current Space?), `CGSCopyManagedDisplaySpaces` / `CGSManagedDisplayGetCurrentSpace` (per-display current Space; only correct with "Displays have separate Spaces" on).

Deliberately **not** using `CGSManagedDisplaySetCurrentSpace` / yabai-style "focus space": that path needs SIP partially disabled plus a Dock scripting addition. The `_SLPS...` route triggers the Space switch as a side effect and needs no SIP change, only Accessibility permission. That fits this app (ad-hoc signed, not sandboxed, already prompts for Ghostty Automation).

Tradeoffs: these symbols are undocumented and fragile across point releases (AltTab had to widen the `makeKeyWindow` event record buffer for macOS 14.7.4 to avoid a WindowServer SIGABRT). Acceptable here, but budget re-verification on major macOS bumps and keep AltTab's `SkyLight.framework.swift` as the reference for signatures and buffer sizes.

Sequencing / timing gotchas worth encoding:

- Order is specific: `_SLPS` front (carries you to the Space) -> make key -> AXRaise -> repair origin Space. AXRaise-first or public-activate-first fails.
- Un-minimize (`kAXMinimizedAttribute = false`) before raising.
- De-fullscreen (`kAXFullscreenAttribute = false`) needs ~1s for the animation to settle before the next action; Space transitions are async.
- A ~50ms post-focus settle is realistic; the switch is not instantaneous.
- Cross-Space "bounce-back" is a real OS bug (reproducible from the Dock); step 4 is the mitigation.

## Ghostty specifics

- Dictionary (1.3.0+): `application > windows > tabs > terminals`, each window and tab has an `id`. It exposes a `focus` verb ("focus a terminal and bring its window to front") in addition to `activate window` / `select tab`. But `focus`/`activate` are AppKit-based, so they are still subject to the Space limitation. Worth a cheap empirical test (Phase 1) before reaching for private APIs, but do not expect it to fix the cross-display case.
- Ghostty uses **native macOS tabs** (real `NSWindow` tab groups). Consequence: inactive tabs return no Space from `CGSCopySpacesForWindows`; resolve Space membership via the active-tab sibling of the window.
- Full-screen Ghostty window is its own Space; the `_SLPS` call enters it, or toggle `kAXFullscreenAttribute` off first with the ~1s settle.

## Architectural tension to resolve

The robust fix must run **in-process** (private C calls, a `ProcessSerialNumber`, an `AXUIElement`, Accessibility permission). That collides with today's detached-shell design, which exists so focus lands after ClawdBack quits.

Two ways out:

- **A. Do the SkyLight sequence in-process, then delay the quit.** Perform the raise in `handleNotificationResponse`, wait a short settle (~150-300ms) so the Space switch commits, then terminate. The old "quit resets the tab" concern was about AppleScript activation; with SkyLight we set window + key focus directly and, on our quit, macOS activates the app we just fronted (Ghostty), so focus should hold. **Recommended**; verify the no-reset assumption in Phase 0.
- **B. Ship a tiny focus helper binary** invoked from the detached shell with the `CGWindowID`. Preserves the run-after-quit property but a separate executable needs its **own** TCC Accessibility grant (permission is keyed per binary), a worse install/permission story. Only fall back to this if A shows a real reset problem.

We also need the target's **`CGWindowID`**, which we do not store today (we save Ghostty's AppleScript window id + tab id). Ghostty's AS window id is not the `CGWindowID`. Cleanest fix: **capture the `CGWindowID` at capture time**, when the terminal is frontmost (`capture` mode already runs then), via `CGWindowListCopyWindowInfo` for the Ghostty pid's frontmost on-screen window, and store it in the per-session locator next to the AS ids. Capture re-runs every prompt, so it stays fresh. This sidesteps AS-id -> `CGWindowID` mapping at click time. Keep the AS `select tab` step for the correct tab within the raised window.

## Proposed phased approach

### Phase 0: Reproduce and instrument
- Reproduce each variant above and record which ones fail.
- Add counters/logging around claw-back: target Space vs current Space (via `CGSCopySpacesForWindows`), display, full-screen state, whether the switch happened. Per personal convention, add counters (did the raise run? did the Space differ? did it land?).
- Confirm the current value of `AppleSpacesSwitchOnActivate` on the repro machine and note whether flipping it alone fixes the same-display case.
- Verify assumption for option A: does an in-process raise + delayed quit hold focus without a tab reset?

### Phase 1: Cheap wins (no private APIs)
- Try Ghostty's `focus` verb in place of / alongside `activate window`; measure.
- Revisit timing: the single `sleep 0.3` may be too short once a Space animation is involved.
- Decide whether to detect and surface the `AppleSpacesSwitchOnActivate` setting to the user (diagnostic only; do not silently flip a global user setting).
- Ship whatever of these measurably helps; they will not fully fix cross-display.

### Phase 2: In-process SkyLight raise (the real fix)
- Add a `CGWindowID` to `WindowFocusTarget`; capture it in `capture` mode.
- Add a SkyLight bridge (`@_silgen_name` declarations mirrored from AltTab) and a `raiseWindow(pid:cgWindowId:)` implementing the 4-step sequence, with the origin-Space repair for the cross-Space case.
- Rework focus to run in-process (option A): keep the zellij `focus-pane-id` and the Ghostty `select tab` steps (both fine to keep as shell/AppleScript), but replace `open -b` + `activate window` with the in-process raise; delay the quit past a short settle.
- This is Ghostty-only at first (only Ghostty is a `WindowFocus` conformer and we only have its `CGWindowID`). Baseline terminals keep degrading to activation.

### Phase 3: Full-screen and tab edge cases
- Handle minimized (`kAXMinimizedAttribute`) and full-screen (`kAXFullscreenAttribute` + ~1s settle) targets.
- Resolve Space membership via the active-tab sibling for native tabs.

## Risks
- Private SkyLight APIs are undocumented and can break on major macOS releases; isolate them behind one file and keep the AltTab reference handy.
- Accessibility permission is required; an ad-hoc re-sign on rebuild can reset the grant (README already notes the analogous Automation reset).
- Moving focus in-process changes the quit timing; watch for regressions in the common same-Space case, which works today.

## Verification
- Matrix: {same Space, other Space same display, other display, full-screen} x {zellij, no zellij} x {tab 1, tab N}. Each must land on the exact window and tab (and pane).
- Confirm skip-when-viewing (`isViewing`) still holds: no notification when already on the target window/pane.
- Confirm the same-Space happy path is unchanged.

## References
- AltTab focus sequence: https://github.com/lwouis/alt-tab-macos/blob/master/src/switcher/state/Window.swift
- AltTab SkyLight declarations + `makeKeyWindow`: https://github.com/lwouis/alt-tab-macos/blob/master/src/macos/api-wrappers/SkyLight.framework.swift
- macOS window internals (`_SLPSSetFrontProcessWithOptions`, `SLPSPostEventRecordTo`): https://cua.ai/blog/inside-macos-window-internals
- Hammerspoon synthetic-click origin: https://github.com/Hammerspoon/hammerspoon/issues/370
- NSRunningApplication.activate advisory on Sonoma: https://developer.apple.com/forums/thread/739524
- Cooperative activation / `yieldActivationToApplication`: https://developer.apple.com/forums/thread/793253
- `AppleSpacesSwitchOnActivate` setting: https://macos-defaults.com/mission-control/applespacesswitchonactivate.html
- yabai SIP requirement for space focus/move: https://github.com/koekeishiya/yabai/issues/1532
- Ghostty AppleScript features: https://ghostty.org/docs/features/applescript
