import AppKit

func focusTerminal(_ terminal: Terminal) {
  let app = NSWorkspace.shared.runningApplications
    .first { $0.bundleIdentifier == terminal.bundleIdentifier }
  app?.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
}

// Focus Claude's pane by its stable id. `focus-pane-id` also switches to the
// pane's tab, so no separate go-to-tab step (or `room` plugin) is needed, and
// it targets the exact pane rather than guessing the focused tab.
func focusZellijPane(session: String, paneId: String) {
  guard let zellijPath = findZellijPath() else { return }

  let process = Process()
  process.executableURL = URL(fileURLWithPath: zellijPath)
  process.arguments = [
    "--session", session,
    "action", "focus-pane-id", "terminal_\(paneId)",
  ]
  process.standardOutput = FileHandle.nullDevice
  process.standardError = FileHandle.nullDevice

  try? process.run()
  process.waitUntilExit()
}
