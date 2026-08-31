import AppKit

let app = NSApplication.shared
let args = CommandLine.arguments

// The hook wrappers name one of these; no argument at all means the app was
// launched by a notification click.
enum Mode: String {
  case capture, cleanup, notify
}

let modeArgs = Array(args.dropFirst(2))

switch args.dropFirst().first {
case .none:
  let delegate = AppDelegate()
  app.delegate = delegate
  app.run()

case .some(let raw):
  switch Mode(rawValue: raw) {
  case .capture:
    // SessionStart / UserPromptSubmit: record Claude's window+tab (when it's reliably
    // frontmost), and clear this session's banner now that the user is back at its pane.
    if captureAndSave(args: modeArgs) {
      // The removal is a one-way message to the notification server, so outlive it.
      Task {
        try? await Task.sleep(for: .milliseconds(250))
        await MainActor.run { app.terminate(nil) }
      }
      app.run()
    }

  case .cleanup:
    // SessionEnd: drop this session's saved window/tab state.
    if let sid = parseArg(modeArgs, flag: "--session-id"), !sid.isEmpty {
      StateStore.clear(sid)
    }

  case .notify:
    Task {
      await sendNotification(args: modeArgs)
      try? await Task.sleep(for: .milliseconds(500))
      await MainActor.run { app.terminate(nil) }
    }
    app.run()

  case .none:
    // Exit rather than fall through to the click handler: that handler waits for
    // a notification response that a mistyped mode will never bring, and a
    // lingering instance makes every later `open --args` a no-op.
    counter(.unknownMode)
    FileHandle.standardError.write(Data("clawd-back: unknown mode '\(raw)'\n".utf8))
    exit(1)
  }
}
