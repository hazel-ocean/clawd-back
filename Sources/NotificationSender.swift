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

// SessionStart / UserPromptSubmit: re-derive where Claude is running, keyed by
// the Claude session id, so later notify/click resolve the exact window. Every
// prompt re-reads what it can and re-validates what it can't, because a target
// that no longer resolves is worse than none: a dead window id makes
// `resolveFocus` give up, where no window id at all still focuses the pane.
// Returns true when a dismissal was issued, so the caller can stay alive for it.
@discardableResult
func captureAndSave(args: [String]) -> Bool {
  guard let sessionId = parseArg(args, flag: "--session-id"), !sessionId.isEmpty else {
    return false
  }
  let existing = StateStore.load(sessionId)

  // The prompt was submitted from Claude's pane, so any banner this session left
  // behind is stale. That holds whatever is frontmost by the time this process
  // launches, so the dismissal never waits on the reads below: the user can hit
  // enter and switch away faster than we start.
  let dismissed = existing?.notified == true
  if dismissed { dismissNotification(sessionId: sessionId) }

  let term = loadConfiguredApp()
  let multiplexerTarget = recapturedMultiplexer(
    existing: existing?.multiplexer, env: ProcessInfo.processInfo.environment)
  let terminalTarget = recapturedTerminal(
    term: term, existing: existing?.terminal, multiplexer: multiplexerTarget)

  persist(
    SessionState(terminal: terminalTarget, multiplexer: multiplexerTarget),
    sessionId: sessionId)
  return dismissed
}

// The window and tab to raise. A front-window read is only right when the front
// window is the one this session lives in, which the OS frontmost check confirms
// and a focused pane confirms independently: pane focus is a fact about this
// session's own client, so it holds while another app sits in front. Failing
// both, keep the saved target only while its window is still open.
func recapturedTerminal(
  term: any AppActivation,
  existing: WindowFocusTarget?,
  multiplexer: MultiplexerFocusTarget?,
  resolveMultiplexer: (MultiplexerKind) -> any MultiplexerFocus = multiplexer(for:)
) -> WindowFocusTarget? {
  // No window/tab vocabulary at all, so there is nothing to read or check.
  guard let wf = term as? WindowFocus else { return existing }

  let paneConfirms =
    multiplexer.map { resolveMultiplexer($0.kind).isFocused(on: $0) } ?? false
  if term.isFrontmost || paneConfirms, let front = wf.frontTarget() {
    return front
  }
  guard let existing, wf.windowExists(existing) else { return nil }
  return existing
}

// The pane to focus. Neither source can see a rename: the env is fixed at
// Claude's spawn, and the saved value only changes when something rewrites it.
// So take whichever still names a live session, saved first, since a rename
// through the workspace command rewrites the file.
func recapturedMultiplexer(
  existing: MultiplexerFocusTarget?,
  env: [String: String],
  resolveMultiplexer: (MultiplexerKind) -> any MultiplexerFocus = multiplexer(for:)
) -> MultiplexerFocusTarget? {
  [existing, captureMultiplexerTarget(env: env)]
    .compactMap { $0 }
    .first { resolveMultiplexer($0.kind).sessionState(on: $0) != .missing }
}

// An all-empty state is never written, so clear the file instead: leaving a
// stale `notified` behind would re-arm the dismissal on every prompt.
private func persist(_ state: SessionState, sessionId: String) {
  if state.isEmpty {
    StateStore.clear(sessionId)
  } else {
    StateStore.save(state, sessionId: sessionId)
  }
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
    title: baseTitle, message: message, folder: folder, cwd: cwd, sessionId: sessionId)
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
