import AppKit

let app = NSApplication.shared
let args = CommandLine.arguments

if args.count > 1 && args[1] == "capture" {
  // SessionStart: record Claude's window+tab (when it's reliably frontmost).
  captureAndSave(args: Array(args.dropFirst(2)))
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
