import AppKit
import Foundation

// Window/tab/pane focusing per terminal.
//
// The window+tab that Claude runs in are captured at SessionStart (when Claude's
// window is reliably frontmost) and saved by session id; notify and click read
// that saved locator, so targeting is by the exact OS window id rather than any
// cwd/front-window guessing. Inside zellij we additionally use the pane id +
// `focus-pane-id`.
//
// Only Ghostty is implemented here; other terminals degrade to activating the
// app (and, in zellij, `focus-pane-id`).
struct TerminalController {
  let terminal: Terminal

  var isFrontmostApp: Bool {
    NSWorkspace.shared.frontmostApplication?.bundleIdentifier == terminal.bundleIdentifier
  }

  // Bring the app to the front (front window only, not `.activateAllWindows`).
  func activateApp() {
    NSWorkspace.shared.runningApplications
      .first { $0.bundleIdentifier == terminal.bundleIdentifier }?
      .activate()
  }

  // Capture the front window+tab id. Called at SessionStart; only Ghostty.
  func captureFrontWindowTab() -> (window: String, tab: String)? {
    guard terminal == .ghostty else { return nil }
    guard
      let out = runOsascript(
        """
        tell application "Ghostty"
          set w to front window
          return (id of w) & "\t" & (id of selected tab of w)
        end tell
        """), out.contains("\t")
    else { return nil }
    let p = out.components(separatedBy: "\t")
    return p.count == 2 ? (p[0], p[1]) : nil
  }

  // True when the user is already looking at Claude's window (and, in zellij,
  // its pane), so a notification would be noise. Precise: it compares the front
  // window id to the saved one. Conservative (false → notify) on any doubt.
  func isViewing(savedWindow: String?, zellijSession: String?, zellijPane: String?) -> Bool {
    guard isFrontmostApp else { return false }
    guard let savedWindow = savedWindow, !savedWindow.isEmpty else { return false }
    guard frontWindowId() == savedWindow else { return false }
    if let session = zellijSession, !session.isEmpty, let pane = zellijPane, !pane.isEmpty {
      return zellijClientFocusedOnPane(session: session, paneId: pane)
    }
    return true
  }

  // Raise the saved window, select the saved tab, and (in zellij) focus the pane.
  func focus(windowId: String?, tabId: String?, zellijPane: String?, zellijSession: String?) {
    let hasWindow = (windowId?.isEmpty == false) && (tabId?.isEmpty == false)
    let hasPane = (zellijSession?.isEmpty == false) && (zellijPane?.isEmpty == false)
    // Nothing to focus (e.g. an un-captured session's notification): do nothing,
    // so it can't clobber a correct focus from another notification.
    guard hasWindow || hasPane else { return }

    // Run the focus from a DETACHED shell that waits for this app to quit first.
    // This app was launched by the notification click, and if it activates the
    // terminal window then terminates, the terminal regains focus on our quit
    // and resets to its previously-active tab — undoing our select. Running the
    // focus after we're gone (like a plain shell would) makes it stick.
    // Wait out this app's ~0.1s self-terminate so the focus lands after we've
    // quit and the terminal has settled (otherwise our quit resets the tab).
    var steps = ["sleep 0.3"]
    if terminal == .ghostty, hasWindow, let windowId = windowId, let tabId = tabId {
      let script = [
        "tell application \"Ghostty\"",
        "activate window (window id \"\(escAS(windowId))\")",
        "select tab (tab id \"\(escAS(tabId))\" of window id \"\(escAS(windowId))\")",
        "end tell",
      ].joined(separator: "\n")
      let tmp = NSTemporaryDirectory() + "czw-focus-\(UUID().uuidString).applescript"
      try? script.write(toFile: tmp, atomically: true, encoding: .utf8)
      steps.append("/usr/bin/osascript \(shq(tmp))")
      steps.append("rm -f \(shq(tmp))")
    } else if hasWindow || hasPane {
      // Non-Ghostty, or zellij with no captured window: just raise the app.
      steps.append("/usr/bin/open -b \(shq(terminal.bundleIdentifier))")
    }
    if hasPane, let session = zellijSession, let pane = zellijPane, let zellij = findZellijPath() {
      steps.append(
        "\(shq(zellij)) --session \(shq(session)) action focus-pane-id terminal_\(shq(pane))")
    }
    let cmd = steps.joined(separator: "; ")
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/sh")
    p.arguments = ["-c", cmd]
    try? p.run()  // detached: do not wait; this app terminates next.
  }

  // Single-quote a string for safe embedding in a /bin/sh command.
  private func shq(_ s: String) -> String {
    "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
  }

  private func frontWindowId() -> String? {
    guard terminal == .ghostty else { return nil }
    return runOsascript(#"tell application "Ghostty" to return id of front window"#)
  }

  // Is any zellij client in `session` currently focused on Claude's pane?
  // `zellij action list-clients` maps each client to its focused ZELLIJ_PANE_ID
  // (e.g. "terminal_4"); match that column exactly.
  private func zellijClientFocusedOnPane(session: String, paneId: String) -> Bool {
    guard let zellij = findZellijPath(),
      let out = runProcess(zellij, ["--session", session, "action", "list-clients"])
    else { return false }
    let target = "terminal_\(paneId)"
    return out.split(separator: "\n").dropFirst().contains { line in
      line.split(whereSeparator: { $0 == " " || $0 == "\t" }).contains { String($0) == target }
    }
  }

  // MARK: - Helpers

  private func runOsascript(_ script: String) -> String? {
    runProcess("/usr/bin/osascript", ["-e", script])
  }

  private func runProcess(_ path: String, _ args: [String]) -> String? {
    guard FileManager.default.isExecutableFile(atPath: path) else { return nil }
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    let out = Pipe()
    p.standardOutput = out
    p.standardError = FileHandle.nullDevice
    do {
      try p.run()
      p.waitUntilExit()
    } catch {
      return nil
    }
    guard p.terminationStatus == 0 else { return nil }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  // Escape a value for embedding inside an AppleScript double-quoted string.
  private func escAS(_ s: String) -> String {
    s.replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
  }
}
