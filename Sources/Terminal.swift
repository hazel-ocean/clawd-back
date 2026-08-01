import AppKit
import Foundation

// The terminals ClawdBack knows about. The config's `terminal` string decodes
// into one of these; an unknown value falls back to .ghostty.
enum Terminal: String, Codable, CaseIterable {
  case ghostty, wezterm, iterm2, terminal, alacritty, kitty, rio

  var bundleIdentifier: String {
    switch self {
    case .ghostty: return "com.mitchellh.ghostty"
    case .wezterm: return "com.github.wez.wezterm"
    case .iterm2: return "com.googlecode.iterm2"
    case .terminal: return "com.apple.Terminal"
    case .alacritty: return "org.alacritty"
    case .kitty: return "net.kovidgoyal.kitty"
    case .rio: return "com.raphaelamorim.rio"
    }
  }
}

// A specific window (and, when the terminal has tabs, tab) to raise. Serialized
// into the per-session state and the notification payload.
struct WindowFocusTarget: Equatable, Codable {
  let window: String
  let tab: String?
}

// Every terminal ClawdBack can drive. Identity + activation need nothing but a
// bundle id, so they come free to every conformer.
protocol TerminalApp {
  var kind: Terminal { get }
  var bundleIdentifier: String { get }
  // A requirement (not just an extension member) so it dispatches dynamically
  // and tests can supply a terminal with a known frontmost state.
  var isFrontmost: Bool { get }
}

extension TerminalApp {
  var isFrontmost: Bool {
    NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleIdentifier
  }

  // Cross-app raise. `open -b` does a real app activation (unlike AppleScript
  // `activate window`, which only reorders windows within an already-front app),
  // so focus survives even when another app was frontmost. Also step one of a
  // claw-back plan.
  func activationStep() -> String {
    "/usr/bin/open -b \(shq(bundleIdentifier))"
  }
}

// Capability: read the current window/tab and select a specific one. Only a
// terminal that exposes stable window/tab ids and a way to select them can
// conform; today that is Ghostty (via its AppleScript dictionary). Terminals
// without it degrade to activation only.
protocol WindowFocus: TerminalApp {
  // The front window+tab right now. Used both to capture at SessionStart and to
  // compare for skip-when-viewing.
  func frontTarget() -> WindowFocusTarget?

  // Shell steps that raise `target`'s window and select its tab.
  func focusSteps(for target: WindowFocusTarget) -> [String]
}

struct Ghostty: WindowFocus {
  let kind = Terminal.ghostty
  var bundleIdentifier: String { kind.bundleIdentifier }

  func frontTarget() -> WindowFocusTarget? {
    guard
      let out = runOsascript(
        """
        tell application "Ghostty"
          set w to front window
          return (id of w) & "\t" & (id of selected tab of w)
        end tell
        """), out.contains("\t")
    else { return nil }
    let p = out.components(separatedBy: "\t")
    return p.count == 2 ? WindowFocusTarget(window: p[0], tab: p[1]) : nil
  }

  func focusSteps(for target: WindowFocusTarget) -> [String] {
    var lines = [
      "tell application \"Ghostty\"",
      "activate window (window id \"\(escAS(target.window))\")",
    ]
    if let tab = target.tab, !tab.isEmpty {
      lines.append(
        "select tab (tab id \"\(escAS(tab))\" of window id \"\(escAS(target.window))\")")
    }
    lines.append("end tell")
    let script = lines.joined(separator: "\n")
    let tmp = NSTemporaryDirectory() + "czw-focus-\(UUID().uuidString).applescript"
    try? script.write(toFile: tmp, atomically: true, encoding: .utf8)
    return ["/usr/bin/osascript \(shq(tmp))", "rm -f \(shq(tmp))"]
  }
}

// A terminal we can raise but not address by window/tab. Everything but Ghostty
// today; adding window/tab support later is just a new WindowFocus conformer.
struct BaselineTerminal: TerminalApp {
  let kind: Terminal
  var bundleIdentifier: String { kind.bundleIdentifier }
}

func terminalApp(for terminal: Terminal) -> any TerminalApp {
  switch terminal {
  case .ghostty: return Ghostty()
  default: return BaselineTerminal(kind: terminal)
  }
}
