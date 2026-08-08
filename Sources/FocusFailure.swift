import Foundation
import UserNotifications

// Why a claw-back could not land, from cheap probes (no Space-query APIs).
enum FocusFailure: Equatable {
  case windowGone
  case sessionDetached
}

// A resolved claw-back is one or the other, never a silent no-op.
enum FocusOutcome {
  case focus(FocusPlan)
  case failure(FocusFailure)
}

// Everything a failure response needs, carried across the notification payload.
struct FocusState: Equatable {
  var terminal: WindowFocusTarget?
  var multiplexer: MultiplexerFocusTarget?
  var title: String
  var message: String
  var folder: String?
  var cwd: String? = nil
}

// Configurable reaction to a FocusFailure, decoded from config like Application.
// Only .notify today; spawn / newTab / switchSession slot in with the config
// schema (docs/plans/configuration.md).
enum FocusFailureResponse: String, Codable, CaseIterable {
  case notify
}

// A detached session is the more actionable failure (we can name the reattach),
// so it wins over a gone window. A reachable target yields today's focus plan.
func resolveFocus(
  term: any AppActivation,
  terminalTarget: WindowFocusTarget?,
  multiplexerTarget: MultiplexerFocusTarget?,
  resolveMultiplexer: (MultiplexerKind) -> any MultiplexerFocus = multiplexer(for:)
) -> FocusOutcome {
  if let mux = multiplexerTarget,
    !resolveMultiplexer(mux.kind).isAttached(on: mux)
  {
    return .failure(.sessionDetached)
  }
  if let wf = term as? WindowFocus, let target = terminalTarget,
    !wf.windowExists(target.window)
  {
    return .failure(.windowGone)
  }
  return .focus(
    focusPlan(
      term: term, terminalTarget: terminalTarget, multiplexerTarget: multiplexerTarget,
      resolveMultiplexer: resolveMultiplexer))
}

func handleFocusFailure(
  _ failure: FocusFailure, state: FocusState, as response: FocusFailureResponse
) async {
  switch response {
  case .notify:
    await sendLocatorNotification(failure, state: state)
  }
}

// The second notification: a click couldn't reach the session, so say where it
// is instead of doing nothing.
func locatorContent(_ failure: FocusFailure, state: FocusState) -> (title: String, body: String) {
  let suffix = state.folder.map { " [\($0)]" } ?? ""
  // The working directory is the durable locator: still valid whatever became of
  // the window or session, so append it whenever we captured it.
  let location = state.cwd.map { "\nLast in: \($0)" } ?? ""
  if let mux = state.multiplexer {
    switch failure {
    case .sessionDetached:
      return (
        "Session detached\(suffix)",
        "\(state.message)\n\(mux.kind.rawValue) session \(mux.session) is detached - run: \(mux.kind.rawValue) attach \(mux.session)\(location)"
      )
    case .windowGone:
      // The window/tab ids are stale now, but the session is still attached
      // somewhere; name it so a reattach lands the user back on the pane.
      return (
        "Window closed\(suffix)",
        "\(state.message)\n\(mux.kind.rawValue) session \(mux.session) is attached elsewhere - run: \(mux.kind.rawValue) attach \(mux.session)\(location)"
      )
    }
  }
  // No multiplexer and the window is gone: the cwd is all that survives, so lead
  // with it rather than the old dead-end sentence.
  if state.cwd != nil {
    return ("Window closed\(suffix)", "\(state.message)\nTerminal window closed.\(location)")
  }
  return ("Window closed\(suffix)", "\(state.message)\nIts terminal window is no longer open.")
}

private func sendLocatorNotification(_ failure: FocusFailure, state: FocusState) async {
  let (title, body) = locatorContent(failure, state: state)
  let content = UNMutableNotificationContent()
  content.title = title
  content.body = body
  content.sound = .default
  content.interruptionLevel = .timeSensitive
  let request = UNNotificationRequest(
    identifier: UUID().uuidString, content: content, trigger: nil)
  try? await UNUserNotificationCenter.current().add(request)
}
