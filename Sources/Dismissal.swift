import Foundation
import UserNotifications

// One live notification per Claude session: a new one replaces the pane's stale
// banner, and a dismissal needs no lookup. Sanitized like the state file name,
// since the id arrives from the hook payload. Without an id there is no key to
// dismiss by, so those notifications keep a unique identifier.
func notificationIdentifier(sessionId: String?) -> String {
  let safe = (sessionId ?? "").filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
  return safe.isEmpty ? UUID().uuidString : "session:\(safe)"
}

func dismissNotification(sessionId: String) {
  UNUserNotificationCenter.current()
    .removeDeliveredNotifications(withIdentifiers: [notificationIdentifier(sessionId: sessionId)])
}

// Clear the banner of every session whose window/pane the user is now looking
// at. Each delivered notification carries its targets in userInfo, so the
// delivered list is the whole work queue and needs no extra state. Locator
// notifications carry the same payload, so they clear the same way.
func dismissViewedNotifications(term: any AppActivation) async {
  // Nothing is viewed while the terminal is in the background, so the
  // per-notification probes never run in that case.
  guard term.isFrontmost else { return }

  let center = UNUserNotificationCenter.current()
  let viewed = await center.deliveredNotifications().filter { notification in
    let state = FocusPayload.decode(notification.request.content.userInfo)
    return isViewing(
      term: term, terminalTarget: state.terminal, multiplexerTarget: state.multiplexer)
  }
  guard !viewed.isEmpty else { return }
  center.removeDeliveredNotifications(withIdentifiers: viewed.map { $0.request.identifier })
}
