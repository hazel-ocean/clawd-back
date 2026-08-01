import Foundation

// An ordered list of shell steps run as ONE detached process. Claw-back must
// run after this app quits: the app is launched by the notification click, and
// if it activates the terminal then terminates, the terminal regains focus on
// our quit and resets to its previously-active tab, undoing the select. Running
// the steps from a detached shell that waits out our quit makes the focus stick.
struct FocusPlan {
  private(set) var steps: [String] = []

  mutating func add(_ step: String) { steps.append(step) }
  mutating func add(_ more: [String]) { steps += more }

  func runDetached() {
    guard !steps.isEmpty else { return }
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/sh")
    p.arguments = ["-c", steps.joined(separator: "; ")]
    try? p.run()  // detached: do not wait; this app terminates next.
  }
}

// True when the user is already looking at Claude's session, so a notification
// would be noise. Skips only when a capability POSITIVELY confirms the exact
// window/pane; a bare frontmost app we can't address still notifies.
func isViewing(
  term: any TerminalApp,
  terminalTarget: WindowFocusTarget?,
  multiplexerTarget: MultiplexerFocusTarget?,
  resolveMultiplexer: (MultiplexerKind) -> any MultiplexerFocus = multiplexer(for:)
) -> Bool {
  guard term.isFrontmost else { return false }
  var confirmed = false
  if let wf = term as? WindowFocus, let target = terminalTarget {
    guard wf.frontTarget() == target else { return false }
    confirmed = true
  }
  if let target = multiplexerTarget {
    guard resolveMultiplexer(target.kind).isFocused(on: target) else { return false }
    confirmed = true
  }
  return confirmed
}

// The ordered steps that raise the saved window, select its tab, and (in a
// multiplexer) focus the pane. Split from clawBack so the composition is
// testable without running anything.
func focusPlan(
  term: any TerminalApp,
  terminalTarget: WindowFocusTarget?,
  multiplexerTarget: MultiplexerFocusTarget?,
  resolveMultiplexer: (MultiplexerKind) -> any MultiplexerFocus = multiplexer(for:)
) -> FocusPlan {
  var plan = FocusPlan()
  let hasTerminal = terminalTarget != nil && term is WindowFocus
  // Nothing to focus (e.g. an un-captured session): empty plan, so a stray
  // notification can't clobber a correct focus from another one.
  guard hasTerminal || multiplexerTarget != nil else { return plan }

  // Wait out this app's ~0.1s self-terminate so the focus lands after we've quit
  // and the terminal has settled (otherwise our quit resets the tab).
  plan.add("sleep 0.3")
  plan.add(term.activationStep())
  if let wf = term as? WindowFocus, let target = terminalTarget {
    plan.add(wf.focusSteps(for: target))
  }
  if let target = multiplexerTarget {
    plan.add(resolveMultiplexer(target.kind).focusSteps(for: target))
  }
  return plan
}

func clawBack(
  term: any TerminalApp,
  terminalTarget: WindowFocusTarget?,
  multiplexerTarget: MultiplexerFocusTarget?
) {
  focusPlan(
    term: term, terminalTarget: terminalTarget, multiplexerTarget: multiplexerTarget
  ).runDetached()
}

// Bridges the focus targets through the notification's userInfo, which must hold
// plist types; each target rides across as its JSON string (empty when absent).
enum FocusPayload {
  static func userInfo(
    terminal: WindowFocusTarget?, multiplexer: MultiplexerFocusTarget?
  ) -> [String: Any] {
    [
      "terminal_target": encodeJSON(terminal),
      "multiplexer_target": encodeJSON(multiplexer),
    ]
  }

  static func decode(
    _ userInfo: [AnyHashable: Any]
  ) -> (terminal: WindowFocusTarget?, multiplexer: MultiplexerFocusTarget?) {
    (
      decodeJSON(WindowFocusTarget.self, from: userInfo["terminal_target"] as? String),
      decodeJSON(MultiplexerFocusTarget.self, from: userInfo["multiplexer_target"] as? String)
    )
  }
}

func encodeJSON<T: Encodable>(_ value: T?) -> String {
  guard let value, let data = try? JSONEncoder().encode(value),
    let s = String(data: data, encoding: .utf8)
  else { return "" }
  return s
}

func decodeJSON<T: Decodable>(_ type: T.Type, from s: String?) -> T? {
  guard let s, !s.isEmpty, let data = s.data(using: .utf8) else { return nil }
  return try? JSONDecoder().decode(type, from: data)
}
