import AppKit
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
  private var handled = false

  func applicationDidFinishLaunching(_ notification: Notification) {
    UNUserNotificationCenter.current().delegate = self

    if let userInfo = notification.userInfo,
      let response = userInfo[NSApplication.launchUserNotificationUserInfoKey]
        as? UNNotificationResponse
    {
      handleNotificationResponse(response)
    }
    armLaunchBackstop()
  }

  // Every path here quits within 300ms, so anything still alive at two seconds
  // is stuck. A stuck instance is worse than a lost claw-back: `open --args`
  // against a running app delivers nothing and only activates it, so one of
  // these silently disables every later notification and steals key focus from
  // the terminal on each attempt. Unconditional, because the failure mode is a
  // path that believes it has finished; a path needing longer must say so.
  private func armLaunchBackstop() {
    Task {
      try? await Task.sleep(for: .seconds(2))
      await MainActor.run {
        if !handled { counter(.launchWithoutResponse) }
        NSApplication.shared.terminate(nil)
      }
    }
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse
  ) async {
    handleNotificationResponse(response)
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    [.banner, .sound]
  }

  // A cold launch from a click can arrive via both the launch userInfo and the
  // didReceive delegate; act only once.
  private func handleNotificationResponse(_ response: UNNotificationResponse) {
    guard !handled else { return }
    handled = true
    counter(.clickHandled)

    guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else {
      terminateApp()
      return
    }

    let state = FocusPayload.decode(response.notification.request.content.userInfo)
    let term = loadConfiguredApp()

    switch resolveFocus(
      term: term, terminalTarget: state.terminal, multiplexerTarget: state.multiplexer)
    {
    case .reachable:
      // The raise runs first, in this process, because the plan's steps are shell
      // and these are private in-process calls. The plan is then built from what
      // actually happened, so it carries an activation only when it must.
      let raised = raiseWindow(
        raiseRequest(term: term, target: state.terminal),
        forceEnabled: forceWindowServerRaiseEnabled())

      // Raise the saved window, select its tab, and in a multiplexer switch the
      // session to Claude's pane.
      focusPlan(
        term: term, terminalTarget: state.terminal, multiplexerTarget: state.multiplexer,
        raised: raised
      ).runDetached()

      guard raised else {
        terminateApp()
        return
      }
      // Outlive the Space switch: it is animated, and quitting mid-transition
      // hands focus back to the app macOS reactivates for us.
      Task {
        try? await Task.sleep(for: .milliseconds(150))
        await MainActor.run { NSApplication.shared.terminate(nil) }
      }
    case .failure(let reason):
      counter(Counter(reason))
      // One locator per failure. Clicking a locator retries the focus, but a
      // second failure is silent: re-notifying would post a new banner on every
      // click.
      guard !state.isLocator else {
        terminateApp()
        return
      }
      // Couldn't reach the session: post the locator notification, then quit
      // once it's delivered.
      Task {
        await handleFocusFailure(reason, state: state, as: .notify)
        try? await Task.sleep(for: .milliseconds(300))
        await MainActor.run { NSApplication.shared.terminate(nil) }
      }
    }
  }

  private func terminateApp() {
    // Quit immediately; the detached focus already holds our pid (CLAWD_PID) from
    // its spawn environment and blocks on it, so it lands strictly after we exit.
    // No pre-quit delay is needed to let the child capture the pid first.
    NSApplication.shared.terminate(nil)
  }
}
