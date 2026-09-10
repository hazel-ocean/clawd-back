import XCTest

@testable import clawd_back

final class HostBundleIdTests: XCTestCase {
  func testForwardedStampNamesTheHost() {
    XCTAssertEqual(hostBundleId("md.obsidian"), "md.obsidian")
  }

  // An older hook sends nothing, and a session whose host is genuinely unknown
  // sends the empty string. Both mean the config answers instead.
  func testMissingStampIsNoHost() {
    XCTAssertNil(hostBundleId(nil))
    XCTAssertNil(hostBundleId(""))
  }

  // Our own id is what LaunchServices stamps on the app `open` launches, so it
  // says nothing about the session.
  func testOwnIdentifierIsNoHost() {
    XCTAssertNil(hostBundleId(Bundle.main.bundleIdentifier))
  }
}

final class HostResolutionTests: XCTestCase {
  func testKnownHostKeepsItsOwnDriver() {
    let app = resolvedHost("com.mitchellh.ghostty")
    XCTAssertEqual(app.kind, .ghostty)
    XCTAssertTrue(app is WindowFocus)
  }

  // The point of recording the host: an app with no dictionary of its own is
  // still addressed, generically, by the id the hook forwarded.
  func testUnknownHostIsAddressedGenerically() {
    let app = resolvedHost("md.obsidian")
    XCTAssertEqual(app.kind, .generic)
    XCTAssertEqual(app.bundleIdentifier, "md.obsidian")
  }

  func testRecordedHostWinsOverTheConfiguredApp() {
    XCTAssertEqual(appForSession(host: "md.obsidian").bundleIdentifier, "md.obsidian")
  }
}
