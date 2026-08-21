import AppKit

let app = NSApplication.shared
let args = CommandLine.arguments

if args.count > 1 && args[1] == "capture" {
  // SessionStart / UserPromptSubmit: record Claude's window+tab (when it's reliably frontmost),
  // and clear this session's banner now that the user is back at its pane.
  if captureAndSave(args: Array(args.dropFirst(2))) {
    // The removal is a one-way message to the notification server, so outlive it.
    Task {
      try? await Task.sleep(for: .milliseconds(250))
      await MainActor.run { app.terminate(nil) }
    }
    app.run()
  }
} else if args.count > 1 && args[1] == "cleanup" {
  // SessionEnd: drop this session's saved window/tab state.
  if let sid = parseArg(Array(args.dropFirst(2)), flag: "--session-id"), !sid.isEmpty {
    StateStore.clear(sid)
  }
} else if args.count > 1 && args[1] == "notify" {
  Task {
    await sendNotification(args: Array(args.dropFirst(2)))
    try? await Task.sleep(for: .milliseconds(500))
    await MainActor.run { app.terminate(nil) }
  }
  app.run()
} else {
  // No args: launched by a notification click.
  let delegate = AppDelegate()
  app.delegate = delegate
  app.run()
}
