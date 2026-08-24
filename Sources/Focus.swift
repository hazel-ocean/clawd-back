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
    // Hand the child our pid via the environment (captured at spawn, so it's
    // correct even if we exit immediately) so its first step can block until we
    // are gone. $PPID would need the child to start before we die; this doesn't.
    var env = ProcessInfo.processInfo.environment
    env["CLAWD_PID"] = String(ProcessInfo.processInfo.processIdentifier)
    p.environment = env
    try? p.run()  // detached: do not wait; this app terminates next.
  }
}

// True when the user is already looking at Claude's session, so a notification
// would be noise. Skips only when a capability POSITIVELY confirms the exact
// window/pane; a bare frontmost app we can't address still notifies.
func isViewing(
  term: any AppActivation,
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

// The ordered steps that focus the multiplexer pane, then raise the saved window
// and select its tab. Split from clawBack so the composition is testable without
// running anything.
//
// Ordering matters: the last activation wins for OS focus. The multiplexer focus
// is a session-state change with no OS-focus effect, so it goes first; the
// terminal window raise goes LAST so nothing steals the window back afterward
// (an earlier ordering ran the pane focus last and the window lost frontmost).
func focusPlan(
  term: any AppActivation,
  terminalTarget: WindowFocusTarget?,
  multiplexerTarget: MultiplexerFocusTarget?,
  resolveMultiplexer: (MultiplexerKind) -> any MultiplexerFocus = multiplexer(for:)
) -> FocusPlan {
  var plan = FocusPlan()
  let hasTerminal = terminalTarget != nil && term is WindowFocus
  // Nothing to focus (e.g. an un-captured session): empty plan, so a stray
  // notification can't clobber a correct focus from another one.
  guard hasTerminal || multiplexerTarget != nil else { return plan }

  // Wait out this app's self-terminate so the focus lands after we've quit and
  // the terminal has settled (otherwise our quit resets the tab). A fixed sleep
  // raced a variable quit latency; block on this app's own pid (CLAWD_PID, set
  // by runDetached) so focus runs strictly after we're gone, then a short settle
  // for the window server to finish reactivating the prior app.
  plan.add("while kill -0 \"$CLAWD_PID\" 2>/dev/null; do sleep 0.02; done")
  plan.add("sleep 0.1")
  if let target = multiplexerTarget {
    plan.add(resolveMultiplexer(target.kind).focusSteps(for: target))
  }
  // A window raise brings the app forward itself (Ghostty's `focus`), so the
  // extra `open -b` activation is redundant and, being async, can land after the
  // raise and steal focus back, e.g. to another display's window. Activate only
  // when no window raise will run (baseline terminals, or a mux-only target).
  if let wf = term as? WindowFocus, let target = terminalTarget {
    plan.add(wf.focusSteps(for: target))
    // Re-assert once: macOS reactivates the prior front app as we quit, which can
    // steal the window back right after the first raise. `select tab` + `focus`
    // are idempotent, so a second pass is a no-op when the first already won.
    plan.add("sleep 0.15")
    plan.add(wf.focusSteps(for: target))
  } else {
    plan.add(term.activationStep())
  }
  return plan
}

// Bridges the focus targets through the notification's userInfo, which must hold
// plist types; each target rides across as its JSON string (empty when absent).
enum FocusPayload {
  // message/folder ride along so the click handler, a fresh process with only
  // this userInfo, can rebuild the locator notification without the state store.
  static func userInfo(
    terminal: WindowFocusTarget?, multiplexer: MultiplexerFocusTarget?,
    title: String, message: String, folder: String?, cwd: String?, sessionId: String?
  ) -> [String: Any] {
    [
      "terminal_target": encodeJSON(terminal),
      "multiplexer_target": encodeJSON(multiplexer),
      "title": title,
      "message": message,
      "folder": folder ?? "",
      "cwd": cwd ?? "",
      "session_id": sessionId ?? "",
    ]
  }

  static func decode(_ userInfo: [AnyHashable: Any]) -> FocusState {
    let folder = userInfo["folder"] as? String
    let cwd = userInfo["cwd"] as? String
    let sessionId = userInfo["session_id"] as? String
    return FocusState(
      terminal: decodeJSON(WindowFocusTarget.self, from: userInfo["terminal_target"] as? String),
      multiplexer: decodeJSON(
        MultiplexerFocusTarget.self, from: userInfo["multiplexer_target"] as? String),
      title: userInfo["title"] as? String ?? "Claude Code",
      message: userInfo["message"] as? String ?? "",
      folder: (folder?.isEmpty ?? true) ? nil : folder,
      cwd: (cwd?.isEmpty ?? true) ? nil : cwd,
      sessionId: (sessionId?.isEmpty ?? true) ? nil : sessionId)
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
