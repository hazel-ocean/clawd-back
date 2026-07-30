# claude-zellij-whip

Smart macOS notifications for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) running in [Ghostty](https://ghostty.org/) or [WezTerm](https://wezfurlong.org/wezterm/) + [Zellij](https://zellij.dev/). When you click a notification, it focuses your terminal, navigates to the correct Zellij tab, and focuses the exact pane where Claude Code is waiting.

![screenshot](screenshot.png)

## The Problem

Claude Code's default `\a` bell notifications don't work properly through Zellij. Even with workarounds like `terminal-notifier`, clicking notifications doesn't bring you back to the right place.

## The Solution

A headless macOS app that:

1. Sends notifications via `UNUserNotificationCenter`
2. Captures Zellij context (session, tab, pane) when sending
3. On click: focuses Ghostty → navigates to tab → focuses pane

## Dependencies

- **macOS** (uses `UNUserNotificationCenter`)
- **Terminal emulator** (one of):
  - [Ghostty](https://ghostty.org/) (default)
  - [WezTerm](https://wezfurlong.org/wezterm/)
  - [iTerm2](https://iterm2.com/)
  - [Terminal.app](https://support.apple.com/guide/terminal/welcome/mac) (built-in)
  - [Alacritty](https://alacritty.org/)
  - [kitty](https://sw.kovidgoyal.net/kitty/)
- **[Zellij](https://zellij.dev/)** terminal multiplexer (with the built-in `action focus-pane-id`, i.e. a reasonably recent version)

## Configuration

The app can be configured to use different terminal emulators via a config file.

**Config file location:** `~/.config/claude-zellij-whip/config.toml` or `config.json`

**Supported terminals:**
- `ghostty` (default, used if config file doesn't exist)
- `wezterm`
- `iterm2`
- `terminal` (macOS Terminal.app)
- `alacritty`
- `kitty`

**TOML config (preferred):**
```toml
terminal = "wezterm"
```

**JSON config:**
```json
{
  "terminal": "wezterm"
}
```

**Default behavior:** If no config file exists, the app defaults to `ghostty`. TOML is checked first, then JSON.

## Installation

### Build and install ClaudeZellijWhip

```bash
git clone https://github.com/rvcas/claude-zellij-whip
cd claude-zellij-whip
make install
```

The app will be installed to `~/Applications/ClaudeZellijWhip.app`.

#### Code Signing (Optional)

By default, the app is ad-hoc signed. To sign with your Apple Developer ID:

```bash
# Find your identity
security find-identity -v -p codesigning

# Set it in the Makefile or pass it directly
make install SIGNING_IDENTITY="Apple Development: Your Name (XXXXXXXXXX)"
```

## Usage

### Manual test

```bash
open ~/Applications/ClaudeZellijWhip.app --args notify \
  --title "Claude Code" \
  --message "Test notification" \
  --folder "my-project"
```

### Claude Code hooks

Add to `~/.claude/settings.json` (see [hooks documentation](https://docs.anthropic.com/en/docs/claude-code/hooks)):

```json
{
  "hooks": {
    "Notification": [
      {
        "matcher": "idle_prompt",
        "hooks": [{
          "type": "command",
          "command": "open ~/Applications/ClaudeZellijWhip.app --args notify --title 'Claude Code' --message 'Waiting for your input' --folder ${CLAUDE_PROJECT_DIR##*/}"
        }]
      },
      {
        "matcher": "permission_prompt",
        "hooks": [{
          "type": "command",
          "command": "open ~/Applications/ClaudeZellijWhip.app --args notify --title 'Claude Code' --message 'Permission needed' --folder ${CLAUDE_PROJECT_DIR##*/}"
        }]
      }
    ]
  }
}
```

The `--folder` parameter appends the project folder name to the notification title (e.g., "Claude Code [my-project]"), using the `CLAUDE_PROJECT_DIR` environment variable provided by Claude Code.

## How It Works

```
SessionStart hook (startup/resume) — Claude's window is reliably frontmost
    ↓
open ClaudeZellijWhip.app --args capture --session-id <id>
    ↓
App records window_id + tab_id (+ zellij_session_id/zellij_pane_id in zellij)
to ~/.cache/claude-zellij-whip/<session-id>.json
    ⋮  (later)
Stop / Notification hook
    ↓
open ClaudeZellijWhip.app --args notify --session-id <id> --message "..."
    ↓
App loads the saved state. If you're already looking at Claude's window
(front window == saved window_id, + in zellij its pane), it SKIPS. Otherwise:
    ↓
Shows macOS notification (saved locator in userInfo)
    ↓
User clicks → app raises the saved window_id, selects tab_id,
              and in zellij runs `action focus-pane-id terminal_<pane>`
```

Targeting is by the **saved OS window id** captured at SessionStart (when
Claude's window is reliably frontmost), so it's exact regardless of what's
frontmost when a notification fires — no cwd guessing. Currently only **Ghostty**
implements window/tab capture+focus; other terminals fall back to activating the
app (+ `focus-pane-id` in zellij).

## Project Structure

```
claude-zellij-whip/
├── Sources/
│   ├── main.swift              # Entry point, mode detection
│   ├── AppDelegate.swift       # Notification click handling
│   ├── NotificationSender.swift # Notification creation + tab-locator capture
│   ├── TerminalController.swift # Per-terminal window+tab capture/focus
│   ├── FocusManager.swift      # Zellij focus-pane-id
│   ├── Config.swift            # Terminal-selection config loading
│   └── ZellijContext.swift     # Zellij binary discovery
├── Resources/
│   ├── Info.plist              # App bundle config (LSUIElement)
│   └── AppIcon.icns            # App icon (shows in notifications)
├── Package.swift
└── Makefile
```

## Makefile Targets

- `make build` - Debug build
- `make release` - Release build
- `make install` - Build, bundle, sign, and install to ~/Applications
- `make uninstall` - Remove the app
- `make clean` - Clean build artifacts
- `make list-identities` - Show available code signing identities

## License

MIT
