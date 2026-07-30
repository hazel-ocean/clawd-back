import Foundation

// Where Claude is running, captured at SessionStart (when Claude's window is
// reliably frontmost) and keyed by Claude's session id. OS-level ids
// (window_id/tab_id) are distinguished from zellij-level ids
// (zellij_session_id/zellij_pane_id); the zellij ones are nil outside zellij.
struct WhipState: Codable {
  var windowId: String
  var tabId: String
  var zellijSessionId: String?
  var zellijPaneId: String?

  enum CodingKeys: String, CodingKey {
    case windowId = "window_id"
    case tabId = "tab_id"
    case zellijSessionId = "zellij_session_id"
    case zellijPaneId = "zellij_pane_id"
  }
}

// Per-session state under ~/.cache/claude-zellij-whip/<session-id>.json.
enum StateStore {
  private static func fileURL(_ sessionId: String) -> URL? {
    let safe = sessionId.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    guard !safe.isEmpty else { return nil }
    let dir = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".cache/claude-zellij-whip", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("\(safe).json")
  }

  static func save(_ state: WhipState, sessionId: String) {
    guard let url = fileURL(sessionId), let data = try? JSONEncoder().encode(state) else { return }
    try? data.write(to: url)
  }

  static func load(_ sessionId: String) -> WhipState? {
    guard let url = fileURL(sessionId), let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode(WhipState.self, from: data)
  }

  static func clear(_ sessionId: String) {
    guard let url = fileURL(sessionId) else { return }
    try? FileManager.default.removeItem(at: url)
  }
}
