import Foundation

// Single-quote a string for safe embedding in a /bin/sh command.
func shq(_ s: String) -> String {
  "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

// Absolute path to a file under the bundle's Resources, or nil when unbundled
// (swift build / tests) or missing.
func bundledResource(_ relativePath: String) -> String? {
  guard
    let url = Bundle.main.resourceURL?.appendingPathComponent(relativePath),
    FileManager.default.fileExists(atPath: url.path)
  else { return nil }
  return url.path
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
