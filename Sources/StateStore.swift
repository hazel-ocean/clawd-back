import Foundation

// Where Claude is running, captured at SessionStart (when Claude's window is
// reliably frontmost) and keyed by Claude's session id. `terminal` is nil for
// terminals we can't address by window/tab; `multiplexer` is nil outside one.
struct SessionState: Codable, Equatable {
  var terminal: WindowFocusTarget?
  var multiplexer: MultiplexerFocusTarget?

  var isEmpty: Bool { terminal == nil && multiplexer == nil }
}

// The pre-protocol flat schema, kept only so a session already in flight at
// upgrade still resolves. Decoded only when the current schema yields nothing.
private struct LegacyState: Codable {
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

  func migrated() -> SessionState {
    let terminal =
      windowId.isEmpty
      ? nil : WindowFocusTarget(window: windowId, tab: tabId.isEmpty ? nil : tabId)
    var multiplexer: MultiplexerFocusTarget?
    if let session = zellijSessionId, !session.isEmpty,
      let pane = zellijPaneId, !pane.isEmpty
    {
      multiplexer = MultiplexerFocusTarget(kind: .zellij, session: session, pane: pane)
    }
    return SessionState(terminal: terminal, multiplexer: multiplexer)
  }
}

// Per-session state under ~/.cache/clawd-back/<session-id>.json.
enum StateStore {
  private static func fileURL(_ sessionId: String) -> URL? {
    let safe = sessionId.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    guard !safe.isEmpty else { return nil }
    let dir = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".cache/clawd-back", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("\(safe).json")
  }

  static func save(_ state: SessionState, sessionId: String) {
    guard !state.isEmpty, let url = fileURL(sessionId),
      let data = try? JSONEncoder().encode(state)
    else { return }
    try? data.write(to: url)
  }

  static func load(_ sessionId: String) -> SessionState? {
    guard let url = fileURL(sessionId), let data = try? Data(contentsOf: url) else { return nil }
    return decode(data)
  }

  // Split from load so migration is testable without the filesystem.
  static func decode(_ data: Data) -> SessionState? {
    // All-optional fields mean a legacy file decodes vacuously into an empty
    // SessionState; treat empty as a miss and retry the old schema.
    if let state = try? JSONDecoder().decode(SessionState.self, from: data), !state.isEmpty {
      return state
    }
    if let legacy = try? JSONDecoder().decode(LegacyState.self, from: data) {
      let migrated = legacy.migrated()
      return migrated.isEmpty ? nil : migrated
    }
    return nil
  }

  static func clear(_ sessionId: String) {
    guard let url = fileURL(sessionId) else { return }
    try? FileManager.default.removeItem(at: url)
  }
}
