# Roadmap

Forward-looking work. Not commitments, just the shape of where this could go.

## Configuration

Today ClawdBack is an `LSUIElement` (no dock icon, no window) driven entirely by
Claude Code hooks, with a single config file (`~/.config/clawd-back/config.toml`,
read via `Config.swift`) that only selects the terminal. As behavior grows more
opinionated (see the tunables below), the defaults need a place to be seen and
changed.

Plan: expand the config schema to cover the tunables, and add a settings window
opened by a **bare launch** of `ClawdBack.app` (double-click), distinct from the
notification-click path in `main.swift`. Settings persist to the existing config
file so hooks and the UI read one source of truth; because each hook is a
short-lived process that reads config on every run, file-based settings propagate
with no live-reload machinery.

Behaviors the settings window would expose. All but Application are currently
hard-coded; Application is already file-configurable (`loadConfiguredApp()`),
so the UI would just surface it. Each row names the current default so the UI
has something to diff against.

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

Plan: [docs/plans/configuration.md](docs/plans/configuration.md).

## Cross-Space and external-display focus

Clicking a notification now reliably surfaces the session's window, tab, and pane
across Spaces and displays: Ghostty's `focus` verb brings the window to the front
(unlike AppKit `activate window`), and dropping the redundant, async `open -b`
stops the raise from bouncing keyboard focus to another display's window.

What it does not yet do is choose *how* it surfaces an off-Space window: `focus`
pulls the window onto the currently-focused Space instead of switching to the
Space that already holds it, so a click rearranges your desktops (the window
jumps from its Desktop to your current one). The wanted behavior is to switch the
display to the window's Space and leave the window put. Two levers:

- Global (affects all app switching): `com.apple.spaces
  AppleSpacesSwitchOnActivate` (off by default) makes activation travel to the
  Space that has the window rather than pulling it.
- Per-claw-back, no global change: the private SkyLight sequence
  (`_SLPSSetFrontProcessWithOptions` with the target `CGWindowID`, a synthetic
  key-window event, then `AXRaise`) that switchers like AltTab use, which
  switches to the specific window's Space as a side effect. Requires moving focus
  in-process and capturing the window's `CGWindowID`.

Plan: [docs/plans/external-display-focus.md](docs/plans/external-display-focus.md).

## Multiplexer support

`MultiplexerFocus` is a protocol precisely so tmux (and others) can be added as
conformers. tmux exposes stable pane/session ids and `switch-client` / `attach`,
so the same capture -> reuse-or-spawn model should map over.

## Generic Accessibility fallback: known gaps

The `generic` application (`Sources/Accessibility/AccessibilityApp.swift`)
addresses windows by title via System Events, not a stable id, since apps
without an AppleScript dictionary expose nothing more specific through
`AXWindow`. Two things intentionally not solved by that change:

- **One app configured at a time.** `AppConfig`/`loadConfiguredApp()` model a
  single globally-configured target; there's no per-session tag recording
  which app a captured `WindowFocusTarget` belongs to (unlike
  `MultiplexerFocusTarget`, which already carries `kind`). A user running
  concurrent Claude sessions across two different apps only gets correct
  claw-back for whichever one is currently configured. Fixing this means
  tagging captured state with the resolved app and auto-detecting the
  frontmost known app at capture time instead of trusting one configured
  value.
- **The named terminals besides Ghostty** (`wezterm`, `iterm2`, `terminal`,
  `alacritty`, `kitty`, `rio`) still use `BaselineApp` (activation-only) even
  though `AccessibilityApp` could likely give them real window targeting too,
  the same way it does for `generic`. Not done because it wasn't needed for
  any of them yet, not because it wouldn't work.
