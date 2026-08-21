# Plan: Configuration schema and settings window

Status: proposed

## Motivation

ClawdBack's behavior is almost entirely hard-coded. The only setting is `terminal`, read from `~/.config/clawd-back/config.{toml,json}` by `loadConfiguredTerminal` in `Sources/Config.swift`. As the app grows more opinionated (focus timing, skip-when-viewing, notification level, crab image, detached-session strategy), those defaults need a place to be seen and changed without recompiling. Two things are needed and are really one effort:

1. a **config schema** that covers the tunables, and
2. a **settings window** that reads and writes it.

## Current state (grounded)

- `AppConfig` is `struct { let terminal: String }`. `loadConfiguredTerminal` reads `config.toml` first (via `TOMLDecoder`), then `config.json` (via `JSONDecoder`), else defaults to `.ghostty`. Note `TOMLDecoder` is **decode-only**: there is no TOML encoder in the dependency set.
- `Sources/main.swift` dispatches by argv: `capture` / `cleanup` / `notify` modes, and **no args => notification-click path** (`AppDelegate`).
- `AppDelegate.applicationDidFinishLaunching` acts only when launched with a notification `userInfo`; a **bare launch** (double-click, no notification) currently falls through and does nothing (the app just runs windowless).
- The app is `LSUIElement` (agent: no dock icon, no menu bar, no window).
- Every hook invocation is a fresh, short-lived process that reads config at start. So config changes propagate on the next hook with no reload logic.

## Goals

- One config file is the single source of truth for hooks and the UI.
- Backward compatible: existing `terminal`-only configs keep working; every new field is optional with a documented default.
- A settings window reachable by double-clicking the app, without giving the agent a permanent dock presence.

## Non-goals

- Exposing settings whose behavior is not yet implemented as a live default. The detached-session strategy and new-surface placement are implemented (hard-coded) by the reuse-or-spawn-claw-back plan; this effort makes them *configurable* only once that lands. The UI wires a setting only when its behavior exists.
- Live config reload for a long-running process (not needed; see above).

## Design

### 1. Config schema

Expand `AppConfig` to hold the tunables, all optional with defaults so old files decode cleanly. Use typed enums decoded from strings (mirroring how `Terminal` already decodes), with an unknown value falling back to the default rather than failing the whole decode. Candidate shape:

```
struct AppConfig: Codable {
  var terminal: Terminal = .ghostty
  var skipWhenViewing: Bool = true
  var interruptionLevel: InterruptionLevel = .timeSensitive
  var crabImage: CrabImage = .random            // random | off | fixed(path)
  var zellijAttach: ZellijAttach = .attach       // attach | attachCreate
  var focus: FocusTimings = .init()              // advanced: settle delays
  // pending features (schema only until implemented):
  // detachedSessionStrategy, newSurfacePlacement, multiplexer
}
```

Provide a single `AppConfig.load()` that returns a fully-defaulted value (never throws to the caller), replacing the ad-hoc `loadConfiguredTerminal`. Keep a thin `loadConfiguredTerminal` shim, or migrate its one call site (`AppDelegate.handleNotificationResponse`) to `AppConfig.load().terminal`.

### 2. File format and precedence (the split-brain risk)

Today toml wins over json. If the UI writes json while a stale `config.toml` exists, the UI's writes are silently shadowed. Decision:

- **Canonical writable store is `config.json`.** Foundation's `JSONEncoder` round-trips the schema with no new dependency; `TOMLDecoder` is decode-only, so writing TOML would mean hand-rolling a serializer. Not worth it: json is the single format the UI reads and writes.
- Keep reading a hand-authored `config.toml` for backward compatibility, but make precedence unambiguous and visible. On first UI save, if a `config.toml` exists, **migrate it into `config.json` and rename the toml to `config.toml.bak`**, so there is one live file afterward. Surface this in the UI ("imported your config.toml"). Never delete the toml, only rename.
- Write atomically (`Data.write(to:options:.atomic)`) and create the config dir if missing.

### 3. Launch dispatch

In `main.swift`, the no-arg branch currently means "notification click". Split it: a launch carrying a notification `userInfo` is a click (existing `AppDelegate` path); a launch **without** one is a bare double-click and should open the settings window. `AppDelegate.applicationDidFinishLaunching` already inspects `launchUserNotificationUserInfoKey`; branch there:

- notification present -> `handleNotificationResponse` (unchanged).
- absent -> open the settings window (do **not** terminate).

### 4. Activation policy for an `LSUIElement` window

An `LSUIElement` app can still show a window, but it won't take focus or show in the dock by default. When opening settings: `NSApp.setActivationPolicy(.regular)`, show and center the window, `NSApp.activate(ignoringOtherApps: true)`; on window close, drop back to `.accessory` and terminate (there is nothing else to keep the process alive). This keeps the agent invisible in normal operation and only "appears" while settings are open.

### 5. UI

SwiftUI settings form (macOS 13+, already the floor). One `Form` mapping the settings table: a terminal picker, toggles for skip-when-viewing, a picker for interruption level, crab image control (random / off / choose file), zellij attach mode, and an **Advanced** disclosure group for focus-settle timings. Bind to an `AppConfig` observable; a Save writes the canonical file. Keep it a plain data-in/data-out form so it stays testable and the persistence layer is the only thing touching disk.

## Settings inventory

Each row names the current default, so the UI has something to diff against. All but Application are hard-coded today; Application is already file-configurable (`loadConfiguredApp()`), so the UI would only surface it.

| Setting | Current default | Options |
| --- | --- | --- |
| Application | `ghostty` (already file-configurable) | ghostty \| wezterm \| iterm2 \| terminal \| alacritty \| kitty \| rio \| generic (shipped) |
| Focus-failure response (unreachable click) | notify (locate the session) | notify \| spawn a fresh surface \| switch captured window's session |
| New-surface placement | fullscreen -> new tab, else new window | smart (that rule, default) \| always a new window \| always a new tab |
| Skip-when-viewing | on | on \| off |
| Notification interruption level | `timeSensitive` | passive \| active \| timeSensitive \| critical |
| Crab image | random per notification | random \| off (app icon) \| fixed image |
| `zellij attach` when session is gone | plain `attach` (errors visibly) | `attach` \| `attach --create` (empty session) |
| Focus-settle timings | `sleep 0.3` focus delay; attach-settle delay before pane focus | advanced / tunable |
| Multiplexer | zellij | zellij (tmux is a future conformer) |

Implementation status per row:

- Implemented today, wire immediately: Terminal, Skip-when-viewing, Notification interruption level, Crab image, `zellij attach` mode, Focus-settle timings.
- Behavior implemented (hard-coded) by `reuse-or-spawn-claw-back.md`, surface here once it lands: Detached-session strategy, New-surface placement.
- Schema placeholder until the feature exists: Multiplexer (zellij only until a second `MultiplexerFocus` conformer exists).

## Phasing

1. **Schema + loader.** Expand `AppConfig`, add `AppConfig.load()`/`save()`, resolve toml/json precedence + migration, keep the terminal call site working. Thread the already-implemented settings (skip-when-viewing, interruption level, crab image, zellij attach, focus timings) through their call sites so the file actually controls behavior. No UI yet; hand-edited files drive it.
2. **Settings window.** Bare-launch dispatch, activation-policy dance, SwiftUI form bound to the schema, atomic save.
3. **Advanced + polish.** Focus-timing disclosure, file-import notice, validation (e.g. crab image path exists).

Phase 1 is independently useful: it makes the tunables configurable via the file even before the window exists.

## Risks / open questions

- toml/json split-brain: the migration step must be well tested so a user's hand-authored toml is never silently ignored or lost (rename, do not delete).
- `LSUIElement` + activation policy flipping can be finicky; verify focus and the return to `.accessory` on close across macOS versions.
- Decoding must degrade gracefully: an unknown enum value should fall back to the default field, not fail the whole file (which would silently revert every setting). Per-field `decodeIfPresent` with defaults.
- Some table rows describe behavior that does not exist; keep them out of the UI until implemented to avoid settings that do nothing.

## Verification

- Old `terminal`-only `config.toml` still selects the terminal after the schema change.
- Each implemented setting, set via the file, changes behavior on the next hook.
- Double-click opens settings; save writes `config.json`; a pre-existing `config.toml` is migrated and backed up; hooks read the new values.
- App returns to invisible agent state after the window closes.
