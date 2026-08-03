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

Behaviors the settings window would expose. All but Terminal are currently
hard-coded; Terminal is already file-configurable (`loadConfiguredTerminal()`),
so the UI would just surface it. Each row names the current default so the UI
has something to diff against.

| Setting | Current default | Options |
| --- | --- | --- |
| Terminal | `ghostty` (already file-configurable) | ghostty \| wezterm \| iterm2 \| terminal \| alacritty \| kitty \| rio (shipped) |
| Detached-session strategy | spawn a fresh surface | spawn fresh \| reuse captured window (switch its session) \| reuse-if-possible-else-spawn |
| New-surface placement | fullscreen -> new tab, else new window | smart (that rule, default) \| always a new window \| always a new tab |
| Skip-when-viewing | on | on \| off |
| Notification interruption level | `timeSensitive` | passive \| active \| timeSensitive \| critical |
| Crab image | random per notification | random \| off (app icon) \| fixed image |
| `zellij attach` when session is gone | plain `attach` (errors visibly) | `attach` \| `attach --create` (empty session) |
| Focus-settle timings | `sleep 0.3` focus delay; attach-settle delay before pane focus | advanced / tunable |
| Multiplexer | zellij | zellij (tmux is a future conformer) |

Plan: [docs/plans/configuration.md](docs/plans/configuration.md).

## Detached / moved session handling

When the captured Ghostty window no longer shows the session - because it was
detached, reattached elsewhere, or closed - claw-back opens the session in a
fresh surface instead of failing: a new tab when the reference window is
fullscreen, a new window otherwise. This establishes the "Detached-session
strategy" and "New-surface placement" defaults in the table above.

Plan: [docs/plans/reuse-or-spawn-claw-back.md](docs/plans/reuse-or-spawn-claw-back.md).

## Cross-Space and external-display focus

Clicking a notification does not reliably travel to the session's window when it
lives on another Mission Control Space or a second monitor: `open -b` and
AppleScript `activate window` activate the app but cannot command WindowServer to
switch to that window's Space (advisory activation on macOS 14+, and the
per-display Spaces model). The robust fix is the private SkyLight sequence
(`_SLPSSetFrontProcessWithOptions` with the target `CGWindowID`, a synthetic
key-window event, then `AXRaise`) that switchers like AltTab use, which requires
moving the focus in-process and capturing the window's `CGWindowID`.

Plan: [docs/plans/external-display-focus.md](docs/plans/external-display-focus.md).

## Multiplexer support

`MultiplexerFocus` is a protocol precisely so tmux (and others) can be added as
conformers. tmux exposes stable pane/session ids and `switch-client` / `attach`,
so the same capture -> reuse-or-spawn model should map over.
