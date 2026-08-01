import Foundation

// Single-quote a string for safe embedding in a /bin/sh command.
func shq(_ s: String) -> String {
  "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

// Escape a value for embedding inside an AppleScript double-quoted string.
func escAS(_ s: String) -> String {
  s.replacingOccurrences(of: "\\", with: "\\\\")
    .replacingOccurrences(of: "\"", with: "\\\"")
}

func runOsascript(_ script: String) -> String? {
  runProcess("/usr/bin/osascript", ["-e", script])
}

func runProcess(_ path: String, _ args: [String]) -> String? {
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
