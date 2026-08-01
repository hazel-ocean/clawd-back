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

    let (terminalTarget, multiplexerTarget) = FocusPayload.decode(
      response.notification.request.content.userInfo)

    // Raise the saved window, select its tab (falls back to app-activate), and
    // in a multiplexer switch the session to Claude's pane.
    clawBack(
      term: terminalApp(for: loadConfiguredTerminal()),
      terminalTarget: terminalTarget,
      multiplexerTarget: multiplexerTarget)

    terminateApp()
  }

  private func terminateApp() {
    // Quit promptly; the detached focus (spawned by clawBack) waits out this
    // quit before touching the terminal.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
      NSApplication.shared.terminate(nil)
    }
  }
}
