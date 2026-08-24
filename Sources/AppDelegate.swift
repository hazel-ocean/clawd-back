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

    guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else {
      terminateApp()
      return
    }

    let state = FocusPayload.decode(response.notification.request.content.userInfo)
    let term = loadConfiguredApp()

    switch resolveFocus(
      term: term, terminalTarget: state.terminal, multiplexerTarget: state.multiplexer)
    {
    case .focus(let plan):
      // Raise the saved window, select its tab, and in a multiplexer switch the
      // session to Claude's pane.
      plan.runDetached()
      terminateApp()
    case .failure(let reason):
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
