import Foundation
import os

// A claw-back is one shot in a process that exits straight after, so a counter
// has nowhere to live but the unified log. Read them back with:
//   log show --last 1h --predicate 'subsystem == "com.hazel.clawd-back"'
private let counterLog = Logger(subsystem: "com.hazel.clawd-back", category: "counters")

enum Counter: String {
  case clickHandled
  // The launch backstop with nothing handled: the signature of a click handler
  // that would otherwise have run forever.
  case launchWithoutResponse
  case raiseAttempted
  case raiseSucceeded
  case raiseFailed
  case gateClosedByArchitecture
  case gateClosedByVersion
  case gateClosedByMissingSymbol
  case targetOffSpace
  case fellBackToShellPlan
  // Why a click could not land. A locator notification says this to the user;
  // without a counter it says nothing to whoever debugs it later.
  case focusFailedWindowGone
  case focusFailedSessionDetached
  case focusFailedSessionMissing
  case notificationPosted
  case notificationSkippedWhileViewing
  case notificationNotAuthorized
  case unknownMode
}

extension Counter {
  init(_ failure: FocusFailure) {
    switch failure {
    case .windowGone: self = .focusFailedWindowGone
    case .sessionDetached: self = .focusFailedSessionDetached
    case .sessionMissing: self = .focusFailedSessionMissing
    }
  }
}

func counter(_ event: Counter) {
  // notice, not info: info is memory-only, so a counter written on a path that
  // hangs is exactly the one `log show` cannot give back.
  counterLog.notice("\(event.rawValue, privacy: .public)")
}
