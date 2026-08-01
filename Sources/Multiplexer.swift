import Foundation

// The terminal multiplexers ClawdBack knows about. An enum so a target can only
// ever carry a kind we actually handle.
enum MultiplexerKind: String, Codable, CaseIterable {
  case zellij
}

// A specific multiplexer pane to focus. `kind` records which multiplexer owns
// it so a click can re-select the right conformer even after the spawn-time env
// is gone.
struct MultiplexerFocusTarget: Equatable, Codable {
  let kind: MultiplexerKind
  let session: String
  let pane: String
}

// Capability: locate the current pane and focus a specific one. A future tmux
// is just another conformer.
protocol MultiplexerFocus {
  var kind: MultiplexerKind { get }

  // Where am I, if this multiplexer is active? nil ⇒ not running under it.
  // Read from the hook's environment.
  func currentTarget(env: [String: String]) -> MultiplexerFocusTarget?

  // Is any client currently focused on `target`'s pane? (skip-when-viewing)
  func isFocused(on target: MultiplexerFocusTarget) -> Bool

  // Shell steps that focus `target`'s pane.
  func focusSteps(for target: MultiplexerFocusTarget) -> [String]
}

struct Zellij: MultiplexerFocus {
  let kind = MultiplexerKind.zellij

  func currentTarget(env: [String: String]) -> MultiplexerFocusTarget? {
    guard let session = env["ZELLIJ_SESSION_NAME"], !session.isEmpty,
      let pane = env["ZELLIJ_PANE_ID"], !pane.isEmpty
    else { return nil }
    return MultiplexerFocusTarget(kind: .zellij, session: session, pane: pane)
  }

  // `zellij action list-clients` maps each client to its focused ZELLIJ_PANE_ID
  // (e.g. "terminal_4"); match that column exactly.
  func isFocused(on target: MultiplexerFocusTarget) -> Bool {
    guard let zellij = findZellijPath(),
      let out = runProcess(zellij, ["--session", target.session, "action", "list-clients"])
    else { return false }
    let needle = "terminal_\(target.pane)"
    return out.split(separator: "\n").dropFirst().contains { line in
      line.split(whereSeparator: { $0 == " " || $0 == "\t" }).contains { String($0) == needle }
    }
  }

  // `focus-pane-id` also switches to the pane's tab, so no separate go-to-tab
  // step is needed, and it targets the exact pane rather than guessing.
  func focusSteps(for target: MultiplexerFocusTarget) -> [String] {
    guard let zellij = findZellijPath() else { return [] }
    return [
      "\(shq(zellij)) --session \(shq(target.session)) action focus-pane-id terminal_\(shq(target.pane))"
    ]
  }
}

private let allMultiplexers: [any MultiplexerFocus] = [Zellij()]

func multiplexer(for kind: MultiplexerKind) -> any MultiplexerFocus {
  switch kind {
  case .zellij: return Zellij()
  }
}

// The active multiplexer's target, if the hook is running inside one.
func captureMultiplexerTarget(env: [String: String]) -> MultiplexerFocusTarget? {
  for mux in allMultiplexers {
    if let target = mux.currentTarget(env: env) { return target }
  }
  return nil
}

// Common install locations. Nix profiles are included so this resolves on
// nix-darwin / home-manager setups, not just Homebrew.
private let zellijPaths = [
  "/opt/homebrew/bin/zellij",
  "/usr/local/bin/zellij",
  "/run/current-system/sw/bin/zellij",
  "\(NSHomeDirectory())/.nix-profile/bin/zellij",
  "/etc/profiles/per-user/\(NSUserName())/bin/zellij",
  "/usr/bin/zellij",
]

func findZellijPath() -> String? {
  zellijPaths.first { FileManager.default.fileExists(atPath: $0) }
}
