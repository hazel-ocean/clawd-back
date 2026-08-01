import XCTest

@testable import clawd_back

final class StateStoreTests: XCTestCase {
  private func decode(_ json: String) -> SessionState? {
    StateStore.decode(Data(json.utf8))
  }

  func testCurrentSchemaRoundTrips() {
    let state = SessionState(
      terminal: WindowFocusTarget(window: "w1", tab: "t1"),
      multiplexer: MultiplexerFocusTarget(kind: .zellij, session: "main", pane: "4"))
    let data = try! JSONEncoder().encode(state)
    XCTAssertEqual(StateStore.decode(data), state)
  }

  func testEmptyCurrentSchemaIsNil() {
    XCTAssertNil(decode("{}"))
  }

  func testGarbageIsNil() {
    XCTAssertNil(decode("not json"))
  }

  func testLegacyFullMigrates() {
    let migrated = decode(
      """
      {"window_id":"w9","tab_id":"t9","zellij_session_id":"main","zellij_pane_id":"7"}
      """)
    XCTAssertEqual(
      migrated,
      SessionState(
        terminal: WindowFocusTarget(window: "w9", tab: "t9"),
        multiplexer: MultiplexerFocusTarget(kind: .zellij, session: "main", pane: "7")))
  }

  func testLegacyWindowOnlyMigratesWithoutMultiplexer() {
    let migrated = decode(#"{"window_id":"w1","tab_id":"t1"}"#)
    XCTAssertEqual(
      migrated,
      SessionState(terminal: WindowFocusTarget(window: "w1", tab: "t1"), multiplexer: nil))
  }

  func testLegacyEmptyWindowKeepsMultiplexer() {
    let migrated = decode(
      """
      {"window_id":"","tab_id":"","zellij_session_id":"main","zellij_pane_id":"2"}
      """)
    XCTAssertEqual(
      migrated,
      SessionState(
        terminal: nil,
        multiplexer: MultiplexerFocusTarget(kind: .zellij, session: "main", pane: "2")))
  }

  func testLegacyEmptyTabBecomesNilTab() {
    let migrated = decode(#"{"window_id":"w1","tab_id":""}"#)
    XCTAssertEqual(migrated?.terminal, WindowFocusTarget(window: "w1", tab: nil))
  }

  func testLegacyAllEmptyIsNil() {
    XCTAssertNil(decode(#"{"window_id":"","tab_id":""}"#))
  }

  func testSaveLoadRoundTripOnDisk() {
    let sessionId = "clawd-test-\(UUID().uuidString)"
    defer { StateStore.clear(sessionId) }
    let state = SessionState(
      terminal: WindowFocusTarget(window: "w", tab: "t"), multiplexer: nil)
    StateStore.save(state, sessionId: sessionId)
    XCTAssertEqual(StateStore.load(sessionId), state)
  }

  func testEmptyStateIsNotWritten() {
    let sessionId = "clawd-test-\(UUID().uuidString)"
    defer { StateStore.clear(sessionId) }
    StateStore.save(SessionState(terminal: nil, multiplexer: nil), sessionId: sessionId)
    XCTAssertNil(StateStore.load(sessionId))
  }
}
