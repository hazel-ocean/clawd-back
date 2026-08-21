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
