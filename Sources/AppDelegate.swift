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

    let userInfo = response.notification.request.content.userInfo
    let session = userInfo["session"] as? String
    let paneId = userInfo["paneId"] as? String

    let config = loadConfig()
    let terminal = Terminal(rawValue: config.terminal) ?? .ghostty
    focusTerminal(terminal)

    if let session = session, !session.isEmpty,
      let paneId = paneId, !paneId.isEmpty
    {
      focusZellijPane(session: session, paneId: paneId)
    }

    terminateApp()
  }

  private func terminateApp() {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
      NSApplication.shared.terminate(nil)
    }
  }
}
