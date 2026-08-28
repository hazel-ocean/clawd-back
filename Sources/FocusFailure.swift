import Foundation
import UserNotifications

// Why a claw-back could not land, from cheap probes (no Space-query APIs).
enum FocusFailure: Equatable {
  case windowGone
  case sessionDetached
  case sessionMissing
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
  // Keys the locator notification to the same banner it replaces, so the next
  // prompt can dismiss it.
  var sessionId: String? = nil
  // True for the locator itself. A locator carries the same targets as the
  // banner it replaced, so without this a click on one that still can't reach
  // its target posts another locator, and every click posts one more.
  var isLocator: Bool = false
}

// Configurable reaction to a FocusFailure, decoded from config like Application.
// Only .notify today; spawn / newTab / switchSession slot in with the config
// schema (docs/plans/configuration.md).
enum FocusFailureResponse: String, Codable, CaseIterable {
  case notify
}

// A session failure is the more actionable one (we can name the session), so it
// wins over a gone window. A reachable target yields today's focus plan.
func resolveFocus(
  term: any AppActivation,
  terminalTarget: WindowFocusTarget?,
  multiplexerTarget: MultiplexerFocusTarget?,
  resolveMultiplexer: (MultiplexerKind) -> any MultiplexerFocus = multiplexer(for:),
  raiseSupported: Bool = architectureSupported
) -> FocusOutcome {
  if let mux = multiplexerTarget {
    switch resolveMultiplexer(mux.kind).sessionState(on: mux) {
    case .missing:
      return .failure(.sessionMissing)
    // Unreachable reads as detached: the attach hint is the useful thing to say
    // either way.
    case .detached, .unreachable:
      return .failure(.sessionDetached)
    case .attached:
      break
    }
  }
  if let wf = term as? WindowFocus, let target = terminalTarget,
    !wf.windowExists(target)
  {
    return .failure(.windowGone)
  }
  return .focus(
    focusPlan(
      term: term, terminalTarget: terminalTarget, multiplexerTarget: multiplexerTarget,
      resolveMultiplexer: resolveMultiplexer, raiseSupported: raiseSupported))
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
  // The session name identifies the workspace on its own, so the folder label is
  // only the fallback when there is no session to name.
  let label = state.multiplexer?.session ?? state.folder
  let title = label.map { "[\($0)] - \(issueLabel(failure))" } ?? issueLabel(failure)

  var lines: [String] = []
  if let mux = state.multiplexer {
    let kind = mux.kind.rawValue
    switch failure {
    case .windowGone:
      // The window/tab ids are stale now, but the session is still attached
      // somewhere, so the user can get back to it.
      lines.append("The \(kind) session is attached elsewhere.")
    case .sessionDetached:
      lines.append("The \(kind) session is detached.")
      // Quoted, because session names hold spaces and this line is meant to be
      // copy-pasted.
      lines.append("Attach: \(kind) attach \(shq(mux.session))")
    case .sessionMissing:
      lines.append("The \(kind) session is gone, possibly renamed.")
    }
  } else {
    lines.append("The terminal window is closed.")
  }
  // The working directory is the durable locator: still valid whatever became of
  // the window or session.
  if let cwd = state.cwd { lines.append("Last in: \(bannerPath(cwd))") }
  return (title, lines.joined(separator: "\n"))
}

private func issueLabel(_ failure: FocusFailure) -> String {
  switch failure {
  case .windowGone: return "Window closed"
  case .sessionDetached: return "Session detached"
  case .sessionMissing: return "Session not found"
  }
}

// A path a notification banner can show whole: home as `~`, and no more than the
// last three components, since the banner truncates a long path mid-word.
func bannerPath(_ path: String) -> String {
  let home = FileManager.default.homeDirectoryForCurrentUser.path
  let rooted = path.hasPrefix(home + "/") ? "~/" + path.dropFirst(home.count + 1) : path
  let parts = rooted.split(separator: "/").map(String.init)
  guard parts.count > 4 else { return rooted }
  let tail = parts.suffix(3).joined(separator: "/")
  return rooted.hasPrefix("/") ? "/…/" + tail : "\(parts[0])/…/" + tail
}

private func sendLocatorNotification(_ failure: FocusFailure, state: FocusState) async {
  let (title, body) = locatorContent(failure, state: state)
  let content = UNMutableNotificationContent()
  content.title = title
  content.body = body
  content.sound = .default
  content.interruptionLevel = .timeSensitive
  // Same identity and payload as the banner this replaces: one live notification
  // per session, dismissible by the next prompt and by skip-when-viewing.
  content.userInfo = FocusPayload.userInfo(
    terminal: state.terminal, multiplexer: state.multiplexer,
    title: state.title, message: state.message, folder: state.folder, cwd: state.cwd,
    sessionId: state.sessionId, isLocator: true)
  let request = UNNotificationRequest(
    identifier: notificationIdentifier(sessionId: state.sessionId), content: content,
    trigger: nil)
  try? await UNUserNotificationCenter.current().add(request)
}
