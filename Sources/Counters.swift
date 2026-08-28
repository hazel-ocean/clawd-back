import Foundation
import os

// A claw-back is one shot in a process that exits straight after, so a counter
// has nowhere to live but the unified log. Read them back with:
//   log show --last 1h --predicate 'subsystem == "com.hazel.clawd-back"'
private let counterLog = Logger(subsystem: "com.hazel.clawd-back", category: "counters")

enum Counter: String {
  case raiseAttempted
  case raiseSucceeded
  case raiseFailed
  case gateClosedByArchitecture
  case gateClosedByVersion
  case gateClosedByMissingSymbol
  case targetOffSpace
  case fellBackToShellPlan
}

func counter(_ event: Counter) {
  counterLog.info("\(event.rawValue, privacy: .public)")
}
