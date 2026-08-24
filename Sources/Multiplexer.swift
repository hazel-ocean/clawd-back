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

// How reachable a session is right now. Drives both the failure the user is
// told about and whether a saved target is still worth keeping.
enum MultiplexerSessionState: Equatable {
  case attached
  case detached
  // Not in the session list at all: renamed or killed.
  case missing
  // No way to ask (no multiplexer binary on this machine).
  case unreachable
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

  // Where `target`'s session stands: reachable, idle, gone, or unaskable.
  func sessionState(on target: MultiplexerFocusTarget) -> MultiplexerSessionState

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

  // The client rows of `zellij action list-clients`, or nil when the output is
  // not a client list at all. For an unknown or exited session the command still
  // exits 0 and prints the whole session list on stdout, so the CLIENT_ID header
  // is the only proof that the rest of the output describes clients. Reading
  // those session rows as clients is what made a renamed session look attached.
  private func clientRows(on target: MultiplexerFocusTarget) -> [String]? {
    guard let zellij = findZellijPath(),
      let out = runProcess(zellij, ["--session", target.session, "action", "list-clients"])
    else { return nil }
    let lines = out.split(separator: "\n").map(String.init)
    guard let header = lines.first, header.hasPrefix("CLIENT_ID") else { return nil }
    return lines.dropFirst().filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
  }

  // `list-sessions --short --no-formatting` prints one exact name per line,
  // exited sessions included, so an absent name means the session is really
  // gone. A non-zero run is zellij reporting no sessions at all, which is the
  // same answer for this target.
  func sessionState(on target: MultiplexerFocusTarget) -> MultiplexerSessionState {
    guard let zellij = findZellijPath() else { return .unreachable }
    guard let out = runProcess(zellij, ["list-sessions", "--short", "--no-formatting"]),
      out.split(separator: "\n").map(String.init).contains(target.session)
    else { return .missing }
    guard let rows = clientRows(on: target) else { return .detached }
    return rows.isEmpty ? .detached : .attached
  }

  // Each client row carries its focused ZELLIJ_PANE_ID (e.g. "terminal_4");
  // match that column exactly.
  func isFocused(on target: MultiplexerFocusTarget) -> Bool {
    guard let rows = clientRows(on: target) else { return false }
    let needle = "terminal_\(target.pane)"
    return rows.contains { line in
      line.split(whereSeparator: { $0 == " " || $0 == "\t" }).contains { String($0) == needle }
    }
  }

  // `focus-pane-id` also switches to the pane's tab, so no separate go-to-tab
  // step is needed, and it targets the exact pane rather than guessing.
  func focusSteps(for target: MultiplexerFocusTarget) -> [String] {
    guard let zellij = findZellijPath() else { return [] }
    return [
      "\(shq(zellij)) --session \(shq(target.session)) action focus-pane-id \(shq("terminal_\(target.pane)"))"
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
