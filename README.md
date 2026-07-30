# Clawd Back

A tiny macOS app that notifies you when [Claude Code](https://docs.anthropic.com/en/docs/claude-code) needs you, and **claws you back** to the exact terminal window, tab, and (in [Zellij](https://zellij.dev/)) pane where that session is waiting when you click the notification.

It also stays quiet when you are already looking at that session, so you only get pinged when it is actually worth switching.

> Fork of [rvcas/claude-zellij-whip](https://github.com/rvcas/claude-zellij-whip) (MIT). The original focused on Zellij pane focus; this fork adds OS window/tab targeting, skip-when-viewing, a Nix flake, and some crabs.

## What it does

- **Notifies** via `UNUserNotificationCenter` on Claude's `Stop` and `Notification` hooks.
- **Remembers where the session lives.** On `SessionStart` and every `UserPromptSubmit` (when the terminal is reliably frontmost) it records the OS window id + tab id, plus the Zellij session/pane when present, keyed by Claude session id. Re-capturing per prompt keeps targeting correct after you reattach a Zellij session in a different window.
- **Skips the banner** when the front window is already that session's window (and, in Zellij, its pane).
- **Clicks back.** Clicking a notification raises the saved window, selects its tab, brings the app to the front (even from another app), and in Zellij runs `action focus-pane-id`.
- **Cleans up** the saved state on `SessionEnd`.
- **Crabs.** Each notification shows a random Claude Crab as its image.

## Requirements

- macOS (uses `UNUserNotificationCenter` + AppKit).
- A terminal emulator. **Ghostty** is fully supported (window + tab targeting via AppleScript). Others (`wezterm`, `iterm2`, `terminal`, `alacritty`, `kitty`) degrade to activating the app, plus Zellij pane focus.
- Optional: [Zellij](https://zellij.dev/) with the built-in `action focus-pane-id`.

## Install

### Nix (flake)

```nix
inputs.clawd-back.url = "github:hazel-ocean/clawd-back";
```

The flake exposes `packages.default` (an `.app` under `$out/Applications`). Install it where LaunchServices can find it, for example a home-manager activation that copies it to `~/Applications`, re-signs ad-hoc, and runs `lsregister`.

### Make

```bash
git clone https://github.com/hazel-ocean/clawd-back
cd clawd-back
make install   # builds, bundles, signs, installs to ~/Applications/ClawdBack.app
```

By default the app is ad-hoc signed. To use a Developer ID: `make install SIGNING_IDENTITY="Apple Development: You (XXXXXXXXXX)"`.

> First time you click a notification, macOS asks for permission to control Ghostty (Automation). Grant it. An ad-hoc re-sign on rebuild can reset that grant; the app still comes to the front regardless, only the tab-select needs it.

## Claude Code hooks

The app has three modes, each driven by a Claude Code hook:

| Mode      | Claude hooks                     | What it does                                              |
| --------- | -------------------------------- | -------------------------------------------------------- |
| `capture` | `SessionStart`, `UserPromptSubmit` | Save the current window/tab for this session.            |
| `notify`  | `Stop`, `Notification`           | Ping you (and stash the locator to claw you back).       |
| `cleanup` | `SessionEnd`                     | Delete this session's saved state.                       |

`capture` runs on **both** `SessionStart` (initial/attach) and `UserPromptSubmit` (every turn). The per-turn re-capture keeps targeting correct after you reattach a Zellij session in a *different* terminal window: the process never restarts so `SessionStart` never re-fires, but the next prompt refreshes the saved window/tab. It only writes when the terminal is frontmost, which both events guarantee.

Claude Code delivers the hook payload (including `session_id`) as **JSON on stdin**, so each mode is fronted by a tiny wrapper that reads stdin and calls the app. **Ready-made wrappers ship inside the app bundle**, one directory per shell, at `/Applications/ClawdBack.app/Contents/Resources/hooks/<shell>/{capture,notify,cleanup}`, so point your hooks straight at them, no copy-paste.

Bash:

```json
{
  "hooks": {
    "SessionStart":     [{ "hooks": [{ "type": "command", "command": "/Applications/ClawdBack.app/Contents/Resources/hooks/bash/capture" }] }],
    "UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "/Applications/ClawdBack.app/Contents/Resources/hooks/bash/capture" }] }],
    "Stop":             [{ "hooks": [{ "type": "command", "command": "/Applications/ClawdBack.app/Contents/Resources/hooks/bash/notify" }] }],
    "Notification":     [{ "hooks": [{ "type": "command", "command": "/Applications/ClawdBack.app/Contents/Resources/hooks/bash/notify" }] }],
    "SessionEnd":       [{ "hooks": [{ "type": "command", "command": "/Applications/ClawdBack.app/Contents/Resources/hooks/bash/cleanup" }] }]
  }
}
```

Nushell (swap `bash` for `nushell`):

```json
{
  "hooks": {
    "SessionStart":     [{ "hooks": [{ "type": "command", "command": "/Applications/ClawdBack.app/Contents/Resources/hooks/nushell/capture" }] }],
    "UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "/Applications/ClawdBack.app/Contents/Resources/hooks/nushell/capture" }] }],
    "Stop":             [{ "hooks": [{ "type": "command", "command": "/Applications/ClawdBack.app/Contents/Resources/hooks/nushell/notify" }] }],
    "Notification":     [{ "hooks": [{ "type": "command", "command": "/Applications/ClawdBack.app/Contents/Resources/hooks/nushell/notify" }] }],
    "SessionEnd":       [{ "hooks": [{ "type": "command", "command": "/Applications/ClawdBack.app/Contents/Resources/hooks/nushell/cleanup" }] }]
  }
}
```

Use whatever path the app actually lives at, `~/Applications/...` if you installed there via `make install`.

> **Nix users:** the flake installs the app under `~/Applications` (a `/nix/store` path rotates on rebuild). Rather than chase the bundle path, generate your own wrappers with `pkgs.writeScript` and point the hooks at their stable `~/.claude/hooks/...` symlinks. The [`hooks/nushell/`](hooks/nushell/) scripts are a ready template.

Prefer your own copies, or a shell that isn't shipped? The same wrappers live under [`hooks/`](hooks/), one directory per shell: [`hooks/bash/`](hooks/bash/) and [`hooks/nushell/`](hooks/nushell/). Copy a set to `~/.claude/hooks/` and point the commands there instead.

Because `open` propagates the caller's environment, `ZELLIJ_SESSION_NAME` / `ZELLIJ_PANE_ID` reach the app when the hook runs inside a Zellij pane.

## Configuration

Pick a terminal in `~/.config/clawd-back/config.toml` (or `config.json`):

```toml
terminal = "ghostty"  # ghostty | wezterm | iterm2 | terminal | alacritty | kitty
```

Defaults to `ghostty` if no config exists.

## How it works

```
SessionStart   -->  open ClawdBack.app --args capture --session-id <id>
UserPromptSubmit    saves window_id + tab_id (+ zellij session/pane)
                    to ~/.cache/clawd-back/<id>.json (only when frontmost)

Stop / Notify  -->  open ClawdBack.app --args notify --session-id <id> ...
                    already viewing that window? -> skip
                    else show notification (locator in userInfo, random crab)

click          -->  open -b <terminal>   (bring to front, cross-app)
                    select saved window + tab
                    zellij: action focus-pane-id terminal_<pane>

SessionEnd     -->  open ClawdBack.app --args cleanup --session-id <id>
                    removes ~/.cache/clawd-back/<id>.json
```

Targeting is by the saved OS window id captured at `SessionStart`, so it is exact regardless of what is frontmost when a notification fires. Only Ghostty implements window/tab capture + select; other terminals fall back to activating the app (+ `focus-pane-id`).

## Project layout

```
Sources/
  main.swift               # mode dispatch: capture | notify | cleanup | click handler
  AppDelegate.swift        # notification click handling
  NotificationSender.swift # capture + send, skip-when-viewing, crab attachment
  TerminalController.swift # per-terminal window/tab capture + focus
  StateStore.swift         # ~/.cache/clawd-back/<id>.json
  Config.swift             # terminal-selection config (TOML/JSON)
  ZellijContext.swift      # zellij binary discovery
  FocusManager.swift       # zellij focus-pane-id
Resources/
  Info.plist               # LSUIElement bundle, id com.hazel.clawd-back
  AppIcon.icns             # app icon
  Crabs/                   # crab images, one at random per notification
hooks/                     # hook wrappers, one dir per shell (both bundled into the app)
  bash/                    # capture | notify | cleanup
  nushell/                 # same wrappers, Nushell
```

## License

MIT. See [LICENSE](LICENSE).
