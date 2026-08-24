import XCTest

@testable import clawd_back

final class NotificationIdentifierTests: XCTestCase {
  func testSessionIdIsTheKey() {
    XCTAssertEqual(notificationIdentifier(sessionId: "abc-123"), "session:abc-123")
  }

  func testSameSessionIsStableAcrossCalls() {
    XCTAssertEqual(
      notificationIdentifier(sessionId: "abc-123"), notificationIdentifier(sessionId: "abc-123"))
  }

  func testUnsafeCharactersAreStripped() {
    XCTAssertEqual(notificationIdentifier(sessionId: "../a b/c"), "session:abc")
  }

  func testMissingSessionIdIsUnique() {
    let a = notificationIdentifier(sessionId: nil)
    XCTAssertFalse(a.hasPrefix("session:"))
    XCTAssertNotEqual(a, notificationIdentifier(sessionId: ""))
  }
}

final class LocatorIdentityTests: XCTestCase {
  // A locator replaces the banner that was clicked, so the click path has to
  // rebuild that banner's identifier from the payload alone.
  func testPayloadRebuildsTheBannerIdentifier() {
    let info = FocusPayload.userInfo(
      terminal: nil, multiplexer: nil, title: "Claude Code", message: "m", folder: nil,
      cwd: nil, sessionId: "abc-123")
    let state = FocusPayload.decode(info)
    XCTAssertEqual(
      notificationIdentifier(sessionId: state.sessionId),
      notificationIdentifier(sessionId: "abc-123"))
  }

  func testMissingSessionIdStillYieldsAnIdentifier() {
    let info = FocusPayload.userInfo(
      terminal: nil, multiplexer: nil, title: "Claude Code", message: "m", folder: nil,
      cwd: nil, sessionId: nil)
    let state = FocusPayload.decode(info)
    XCTAssertFalse(notificationIdentifier(sessionId: state.sessionId).hasPrefix("session:"))
  }
}
