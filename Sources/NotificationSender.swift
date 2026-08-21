import Foundation
import UserNotifications

// A random crab icon from the bundled Resources/Crabs, copied to a fresh temp
// URL so UNNotificationAttachment can take ownership without moving the
// original out of the bundle. Returns nil if there are none (notification then
// just falls back to the app icon).
private func randomCrabAttachment() -> UNNotificationAttachment? {
  guard let dir = Bundle.main.resourceURL?.appendingPathComponent("Crabs"),
    let files = try? FileManager.default.contentsOfDirectory(
      at: dir, includingPropertiesForKeys: nil),
    let pick = files.filter({ $0.pathExtension.lowercased() == "png" }).randomElement()
  else { return nil }
  let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("czw-crab-\(UUID().uuidString).png")
  guard (try? FileManager.default.copyItem(at: pick, to: tmp)) != nil else { return nil }
  return try? UNNotificationAttachment(identifier: "crab", url: tmp)
}

// SessionStart / UserPromptSubmit: record where Claude is running, keyed by the
// Claude session id, so later notify/click resolve the exact window. Only runs
// when the terminal is frontmost (which it is at these events), so a background
// event can't overwrite a good capture with the wrong window.
// Returns true when a dismissal was issued, so the caller can stay alive for it.
@discardableResult
func captureAndSave(args: [String]) -> Bool {
  guard let sessionId = parseArg(args, flag: "--session-id"), !sessionId.isEmpty else {
    return false
  }
  let term = loadConfiguredApp()
  guard term.isFrontmost else { return false }

  let existing = StateStore.load(sessionId)
  // Never clobber a good target with a transient capture miss: keep the prior
  // value if this read fails. The multiplexer session name only legitimately
  // changes on rename (which rewrites the file directly), so don't re-stale it
  // from the spawn-time env each UserPromptSubmit.
  let terminalTarget = (term as? WindowFocus)?.frontTarget() ?? existing?.terminal
  let multiplexerTarget =
    existing?.multiplexer
    ?? captureMultiplexerTarget(env: ProcessInfo.processInfo.environment)

  // Both events fire from Claude's pane while the terminal is frontmost, so the
  // user is back and any banner this session left behind is stale.
  let dismissed = existing?.notified == true
  if dismissed { dismissNotification(sessionId: sessionId) }

  let state = SessionState(terminal: terminalTarget, multiplexer: multiplexerTarget)
  // An all-empty state is never written, so clear the file instead: leaving a
  // stale `notified` behind would re-arm the dismissal on every prompt.
  if state.isEmpty {
    StateStore.clear(sessionId)
  } else {
    StateStore.save(state, sessionId: sessionId)
  }
  return dismissed
}

func sendNotification(args: [String]) async {
  let message = parseArg(args, flag: "--message") ?? "Notification"
  let baseTitle = parseArg(args, flag: "--title") ?? "Claude Code"

  let folder = parseArg(args, flag: "--folder")
  let cwd = parseArg(args, flag: "--cwd")
  let title = folder != nil ? "\(baseTitle) [\(folder!)]" : baseTitle

  let sessionId = parseArg(args, flag: "--session-id")
  let saved = sessionId.flatMap { StateStore.load($0) }
  let term = loadConfiguredApp()

  // Any pane the user walked over to since its notification arrived is stale,
  // including this session's own when the skip below applies.
  await dismissViewedNotifications(term: term)

  let terminalTarget = saved?.terminal
  // Prefer the capture; fall back to the live env for the multiplexer target
  // (window/tab has no env source).
  let multiplexerTarget =
    saved?.multiplexer
    ?? captureMultiplexerTarget(env: ProcessInfo.processInfo.environment)

  // If the user is already looking at Claude's window/pane, skip the notification.
  if isViewing(
    term: term, terminalTarget: terminalTarget, multiplexerTarget: multiplexerTarget)
  {
    return
  }

  let center = UNUserNotificationCenter.current()
  let settings = await center.notificationSettings()

  if settings.authorizationStatus == .notDetermined {
    do {
      let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
      guard granted else { return }
    } catch {
      return
    }
  } else if settings.authorizationStatus == .denied {
    print(
      "Notifications are denied. Please enable in System Settings > Notifications > ClawdBack"
    )
    return
  }

  let content = UNMutableNotificationContent()
  content.title = title
  content.body = message
  content.sound = .default
  // Break through Focus modes (needs the time-sensitive entitlement + signing).
  content.interruptionLevel = .timeSensitive
  content.userInfo = FocusPayload.userInfo(
    terminal: terminalTarget, multiplexer: multiplexerTarget,
    title: baseTitle, message: message, folder: folder, cwd: cwd)
  if let crab = randomCrabAttachment() {
    content.attachments = [crab]
  }

  let request = UNNotificationRequest(
    identifier: notificationIdentifier(sessionId: sessionId),
    content: content,
    trigger: nil
  )

  do {
    try await center.add(request)
    if let sessionId, !sessionId.isEmpty {
      var state =
        saved ?? SessionState(terminal: terminalTarget, multiplexer: multiplexerTarget)
      state.notified = true
      StateStore.save(state, sessionId: sessionId)
    }
  } catch {
    print("Failed to send notification: \(error)")
  }
}

func parseArg(_ args: [String], flag: String) -> String? {
  guard let index = args.firstIndex(of: flag),
    index + 1 < args.count
  else {
    return nil
  }
  return args[index + 1]
}
