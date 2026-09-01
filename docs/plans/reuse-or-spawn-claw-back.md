# Plan: Focus-failure responses for detached / moved sessions

## Context

ClawdBack notifies you when a Claude Code session needs attention and, on click, "claws" you back to the exact terminal window/tab and Zellij pane where that session lives. Today the click handler is brittle: for a Zellij target it runs `zellij --session X action focus-pane-id terminal_P` (invisible when nothing is attached to session X) and then AppleScripts `activate window W` + `select tab T`. If the captured Ghostty window `W` no longer displays session `X` - because you detached `X`, attached a different session in `W`, or closed `W` entirely - the raise lands on the wrong surface or the AppleScript throws, and nothing useful happens. You clicked, and nothing moved, with no explanation.

## The idea

Model a claw-back as something that *resolves* to either runnable focus steps or a **typed failure with a reason**, and hand the failure to a **configurable response**. Never a silent no-op. The first, least-destructive response is `.notify`: after a click that can't land, post a second notification that says why and where the session is, so you can get there yourself. It moves nothing, evicts nothing, spawns nothing.

More aggressive responses (spawn a fresh surface, add a tab, switch an occupied window's session in place) are real options but they all disturb your existing workspace to some degree, so they are deferred to the configuration effort as opt-in strategies. See [docs/plans/configuration.md](configuration.md) (Detached-session strategy / New-surface placement). The default stays non-destructive: tell the user, don't rearrange their windows.

## Model

```
// Why a claw-back could not land, from cheap probes (no Space APIs needed).
enum FocusFailure {
  case windowGone       // captured terminal window no longer exists
  case sessionDetached  // multiplexer session has no attached client
  // later: case offScreen  (cross-Space / external display; needs SkyLight work)
}

// A resolved claw-back is one or the other, never a silent no-op.
enum FocusOutcome {
  case focus(FocusPlan)
  case failure(FocusFailure)
}

// Everything a response needs, carried across the notification payload.
struct FocusState {
  var terminal: WindowFocusTarget?
  var multiplexer: MultiplexerFocusTarget?
  var title: String
  var message: String
  var folder: String?
}

// Configurable reaction to a FocusFailure, decoded from config like Terminal.
// MVP is .notify; spawn / newTab / switchSession slot in here later.
enum FocusFailureResponse: String, Codable, CaseIterable {
  case notify
}
```

## Resolution happens at click time

The first notification is the normal "Claude needs you." Only when you click it and the cheap probes say the target is unreachable does the failure response run. This matches the "focus action fails -> respond" model, avoids firing two banners unless you actually tried to jump, and needs no Space-query APIs: just `windowExists(W)` and `isAttached(X)`, both runnable in the click handler.

Resolution order (most actionable reason wins):

- Multiplexer target whose session has no attached client -> `.failure(.sessionDetached)`. The locator can tell you exactly how to get back: `zellij attach X`.
- Otherwise, window target whose window is gone -> `.failure(.windowGone)`.
- Otherwise -> `.focus(...)` (today's healthy-reuse plan, unchanged).

## The two-notification UX

`UNNotificationContent.body` is not hard-capped by the API, but the OS truncates the displayed banner to a couple of lines, so cramming Claude's message plus a locator into one body loses information. Split it:

- Notification 1 (unchanged): Claude's actual message. Already delivered; on click it triggers resolution.
- Notification 2 (`.notify` response): the locator. Title names the context; body carries the actionable "where + how", e.g. `Detached - run: zellij attach main` plus the folder. `FocusState.message` rides along so the response can echo Claude's text if useful, since notification 1 is dismissed once clicked.

The click process is a fresh launch that only sees the notification's `userInfo`, so the payload must carry enough to rebuild notification 2 without touching the session store: the targets (already there), plus `message` and `folder`.

## Empirically validated against the running Ghostty (2.x AppleScript dictionary)

- `exists window id W` returns a boolean, no throw when absent. This is the `windowGone` probe.

The spawn-related dictionary verbs (`new surface configuration`, `new tab in (window id W)`, `AXFullScreen` via System Events) were also validated and are captured in git history / the configuration plan for when the spawn responses are built; the notify MVP does not need them.

## Files and changes (notify MVP)

### 1. `Sources/FocusFailure.swift` (new)
- `FocusFailure`, `FocusOutcome`, `FocusState`, `FocusFailureResponse` as above.
- `resolveFocus(term:terminalTarget:multiplexerTarget:resolveMultiplexer:) -> FocusOutcome` doing the ordered probes, returning `.focus(focusPlan(...))` on success. Probes dispatch through the capability protocols so tests inject fakes.
- `handleFocusFailure(_:state:as:) async` switching on the response; `.notify` builds and posts notification 2.

### 2. `Sources/Terminal.swift`
- Add `func windowExists(_ window: String) -> Bool` to the `WindowFocus` protocol.

### 3. `Sources/Ghostty/Ghostty.swift` + `ghostty-window-exists.applescript` (new)
- `ghostty-window-exists.applescript` - argv: window id -> prints `true`/`false` via `exists window id`.
- Implement `windowExists` driving it through `bundledResource` + `runProcess`, argv-quoted (no interpolation), matching `ghostty-focus.applescript`.

### 4. `Sources/Multiplexer.swift`
- Add `func isAttached(on target: MultiplexerFocusTarget) -> Bool` to `MultiplexerFocus` (true when `zellij action list-clients --session X` has >=1 client row; reuse the parsing shape in `isFocused`). Implement on `Zellij`.

### 5. `Sources/NotificationSender.swift`
- `sendNotification`: thread `message` and `folder` into `FocusPayload.userInfo` so the click handler can rebuild the locator.

### 6. `Sources/AppDelegate.swift`
- `handleNotificationResponse`: decode the (now richer) payload, `resolveFocus(...)`, then either `plan.runDetached()` + quit (unchanged happy path) or run the configured response (post notification 2, stay alive until delivered, then quit). Response is hard-wired to `.notify` until the config schema exists.

### 7. `Sources/Focus.swift`
- `FocusPayload.userInfo` / `decode` carry `message` and `folder` alongside the existing JSON-encoded targets (plist-safe strings). `focusPlan` and the healthy-reuse ordering are unchanged.

### 8. `Package.swift`
- Add `Ghostty/ghostty-window-exists.applescript` to the target `exclude` list (bundled by the justfile glob, not a Swift source).

### 9. Config (deferred)
- `FocusFailureResponse` becomes a real config field in the configuration effort; until then the click handler passes `.notify`.

### 10. `README.md`
- Note the failure notification: when a click can't reach the session (detached / window closed), a second notification says where it is instead of doing nothing.

## Tests (`Tests/`)
- `resolveFocus`: session detached -> `.failure(.sessionDetached)`; window gone -> `.failure(.windowGone)`; window exists + session attached -> `.focus` with today's step order; detached takes precedence over a gone window. Inject fakes via the capability protocols (extend the existing `FakeWindowTerminal` / `FakeMux` with `windowExists` / `isAttached`).
- Baseline terminal / no multiplexer -> `.focus` (unchanged behavior, no failure).
- `FocusPayload` round-trips `message` / `folder` through `userInfo`.
- Locator body composition for a detached zellij target contains the session name and the `zellij attach` hint.

## Verification (end-to-end, after implementation)
1. `just build` and `swift test`.
2. `just bundle`; confirm `ghostty-window-exists.applescript` lands in `Contents/Resources/Ghostty/`.
3. Manual, in Ghostty + Zellij:
   - Attach session A in a window, start Claude, submit a prompt (capture). Detach A. Trigger a Stop/Notification. Click -> a second notification says session A is detached and shows `zellij attach A`.
   - Close the captured window entirely, then click -> a second notification says the window is gone (and, if the session is still attached, names it).
   - Healthy case (session still visible in W) -> raises W/tab as today, no second notification.
