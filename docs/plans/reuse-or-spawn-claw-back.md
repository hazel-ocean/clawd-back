# Plan: Reuse-or-spawn claw-back for detached / moved Zellij sessions

## Context

ClawdBack notifies you when a Claude Code session needs attention and, on click, "claws" you back to the exact terminal window/tab and Zellij pane where that session lives. Today the click handler is brittle: for a Zellij target it runs `zellij --session X action focus-pane-id terminal_P` (invisible when nothing is attached to session X) and then AppleScripts `activate window W` + `select tab T`. If the captured Ghostty window `W` no longer displays session `X` - because you detached `X`, attached a different session in `W`, or closed `W` entirely - the raise lands on the wrong surface or the AppleScript throws, and nothing useful happens. This is common for anyone who runs many Zellij sessions through one or a few Ghostty windows.

Goal: when the captured window no longer shows the session, **open the session in a fresh Ghostty surface** instead of failing. New tab when the reference window is fullscreen, new window otherwise. This is the behavior confirmed with the user (spawn a fresh surface rather than hijack an occupied window; fullscreen -> tab, else -> window).

Out of scope (captured in `ROADMAP.md`): a configuration UI and making these behaviors user-configurable. This change hard-codes the chosen defaults.

## Empirically validated against the running Ghostty (2.x AppleScript dictionary)

- `exists window id W` returns a boolean, no throw when absent.
- `new surface configuration` + `set command of cfg to "..."` + `new window with configuration cfg` opens a window running that command. `new tab in (window id W) with configuration cfg` works too.
- Ghostty runs the surface `command` via a login shell (`/usr/bin/login -flp <user> /bin/bash --noprofile --norc -c exec -l <command>`); a spawned surface stays open with a "Press any key to close" prompt if the command exits (fine for a long-running `zellij attach`).
- Ghostty's window class exposes **no** fullscreen property; fullscreen must come from System Events `AXFullScreen`. `close window (window id W)` and `close tab` are the disposal verbs; tab ids must be qualified `... of window id W`.
- `zellij action switch-session` exists but is NOT used - the chosen design never switches an occupied window's session, so we avoid that whole problem.

## Design

At click time, for a Zellij target `(session X, pane P)` with captured window `W`, tab `T`, decide between two paths using read-only probes:

| Condition | Action |
| --- | --- |
| `windowExists(W)` **and** `sessionAttached(X)` | **Healthy reuse** (unchanged): `focus-pane-id X:P`, `activate window W`, `select tab T` |
| otherwise | **Spawn**: open a surface running `zellij attach X`, then settle, then `focus-pane-id X:P` |

Spawn placement uses fullscreen captured at capture time (see below), not a live probe:

| At click time | Placement |
| --- | --- |
| `W` exists **and** saved `windowFullscreen == true` | `new tab in W` |
| otherwise (`W` gone, or not fullscreen) | `new window` |

Rationale for capturing fullscreen at capture time rather than probing at click time: System Events cannot address a Ghostty window by its Ghostty id, only the front window. Capture runs only when Ghostty is frontmost and fires from `SessionStart` / `UserPromptSubmit` (activity in Claude's own window), so at that instant the System Events front window IS `W` and its `AXFullScreen` read is exact. This inherits the identical precondition window-id capture already relies on - if Ghostty isn't frontmost, the whole capture is skipped and prior state is kept, so id, tab, and fullscreen are always captured together or not at all.

## Files and changes

### 1. `Sources/StateStore.swift`
- Add `var windowFullscreen: Bool?` to `SessionState`. Keep it **off** `WindowFocusTarget` - that struct is compared by `==` in `isViewing` (skip-when-viewing) and must not gain fields `frontTarget()` can't populate.
- `isEmpty` stays keyed on `terminal`/`multiplexer` only (fullscreen alone is not a meaningful capture).
- Legacy migration untouched (new field decodes as nil).

### 2. `Sources/Ghostty/` - three new argv-based AppleScripts
Argv-based to preserve the existing no-interpolation / no-injection pattern (see `ghostty-focus.applescript`). The justfile already globs `*.applescript` (justfile:35), so these bundle automatically.
- `ghostty-capture.applescript` - single script that reads the front window in one shot to avoid a two-call race: `tell application "Ghostty"` for `id of front window` + `id of selected tab of front window`, then `tell application "System Events"` for `AXFullScreen of window 1`. Emits `window \t tab \t fullscreen`. Replaces `ghostty-front-target.applescript` (fold its logic in) so capture is one osascript call carrying all three fields.
- `ghostty-window-exists.applescript` - argv: window id -> prints `true`/`false`.
- `ghostty-spawn.applescript` - argv: `mode` ("tab"|"window"), `windowId`, `command`. Builds a `new surface configuration`, sets `command`, then `new tab in (window id windowId)` when mode is "tab" and windowId non-empty, else `new window`.

### 3. `Sources/Terminal.swift`
- Add `func windowExists(_ window: String) -> Bool` to the `WindowFocus` protocol.
- Add a new capability protocol `TerminalSpawn: TerminalApp` with `func spawnSteps(command: String, inWindow window: String?, fullscreen: Bool) -> [String]`.
- Extend `frontTarget()`'s contract to also surface fullscreen, OR add `func captureState() -> (target: WindowFocusTarget?, fullscreen: Bool?)` on `WindowFocus` so the single capture script populates both. (Prefer the latter: one method, one osascript call.)

### 4. `Sources/Ghostty/Ghostty.swift`
- Conform `Ghostty` to the new `windowExists` and `TerminalSpawn` requirements, and to the new combined capture method, each driving the matching script via the existing `bundledResource` + `runProcess` helpers (`Sources/Shell.swift`).
- `spawnSteps` emits `/usr/bin/osascript <ghostty-spawn.applescript> <mode> <windowId> <command>` with `shq`-quoted argv.

### 5. `Sources/Multiplexer.swift`
- Add to the `MultiplexerFocus` protocol:
  - `func isAttached(_ target: MultiplexerFocusTarget) -> Bool` - true when `zellij action list-clients --session X` has >=1 client row (reuse the parsing shape already in `isFocused`).
  - `func attachCommand(for target: MultiplexerFocusTarget) -> String?` - the Ghostty surface `command`, e.g. `"<zellij-abs-path> attach <X>"`. This is a login-shell command string (NOT a `/bin/sh` step), so no `shq`; use `findZellijPath()`.
- Implement both on `Zellij`.

### 6. `Sources/Focus.swift`
- `focusPlan(...)`: add the reuse-vs-spawn branch. Call the probe methods through the protocols (so tests inject fakes). Healthy-reuse ordering is unchanged. Spawn path: `sleep 0.3` -> `spawnSteps(...)` (self-focuses Ghostty, so no `activationStep`/`activate`/`select`) -> short settle (`sleep 0.5`) -> `resolveMultiplexer(kind).focusSteps(...)` to land on pane P after attach.
- Reference window for placement = `W` when `windowExists(W)`, else nil (-> new window). Fullscreen comes from the plumbed saved `windowFullscreen`, not a probe.

### 7. `Sources/NotificationSender.swift`
- `captureAndSave`: use the combined capture method; save `windowFullscreen` into `SessionState`. Preserve the existing "never clobber a good target on a capture miss" logic (carry prior fullscreen when the read fails).
- `sendNotification`: thread `windowFullscreen` from saved state into the payload.

### 8. `Sources/Focus.swift` (`FocusPayload`) + `Sources/AppDelegate.swift`
- Extend `FocusPayload.userInfo` / `decode` to carry `windowFullscreen` across the notification (plist-safe, alongside the existing JSON-encoded targets).
- `AppDelegate.handleNotificationResponse` passes the decoded fullscreen into `clawBack` -> `focusPlan`.

### 9. `Package.swift`
- Add the three new `.applescript` paths to the target `exclude` list (they are resources copied by the justfile, not Swift sources). Remove `ghostty-front-target.applescript` from `exclude` only if the file is deleted after folding it into `ghostty-capture.applescript`.

### 10. `Sources/Terminal.swift` / `Sources/Multiplexer.swift` defaults
- Provide default no-op-ish conformances where needed so `BaselineTerminal` (non-Ghostty) and future multiplexers still compile: baseline terminals have no `windowExists`/spawn, so the spawn branch only triggers when `term is TerminalSpawn` and there is a multiplexer target; everything else falls through to today's behavior.

### 11. Docs
- `README.md`: note the reuse-or-spawn behavior and the new **Accessibility** permission needed for capture-time fullscreen (degrades gracefully to "new window" when denied). `ROADMAP.md` already lists the config toggles.

## Tests (`Tests/`)
Extend the existing `Focus`/`focusPlan` tests (which already inject fakes via the capability protocols) with cases:
- window gone + session detached -> spawn `new window`, then `focus-pane-id`.
- window exists + fullscreen -> spawn `new tab in W`.
- window exists + session attached -> healthy reuse (unchanged step order).
- window exists but session detached -> spawn (not reuse).
- Non-Ghostty terminal / no multiplexer -> unchanged behavior (no spawn).
- `StateStore` round-trip includes `windowFullscreen`; legacy files still decode.

## Verification (end-to-end, after implementation)
1. `just build` (SwiftPM) and unit tests: `swift test`.
2. `just install` to bundle + sign to `~/Applications/ClawdBack.app`; confirm the three new scripts land in `Contents/Resources/Ghostty/`.
3. Manual, in Ghostty + Zellij:
   - Attach session A in a window, start Claude, submit a prompt (capture). Detach A. Trigger a Stop/Notification. Click -> a fresh surface attaches A and lands on Claude's pane. Fullscreen window -> new tab; windowed -> new window.
   - Close the captured window entirely, then click -> new window attaches A.
   - Healthy case (session still visible in W) -> raises W/tab, no new surface.
   - Grant vs deny Accessibility: denied still works, always choosing new window.
