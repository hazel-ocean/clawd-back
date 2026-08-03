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
    let term = terminalApp(for: loadConfiguredTerminal())

    switch resolveFocus(
      term: term, terminalTarget: state.terminal, multiplexerTarget: state.multiplexer)
    {
    case .focus(let plan):
      // Raise the saved window, select its tab, and in a multiplexer switch the
      // session to Claude's pane.
      plan.runDetached()
      terminateApp()
    case .failure(let reason):
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
    // Quit promptly; the detached focus (spawned by clawBack) waits out this
    // quit before touching the terminal.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
      NSApplication.shared.terminate(nil)
    }
  }
}
