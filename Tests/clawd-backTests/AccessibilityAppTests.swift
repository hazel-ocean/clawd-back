import XCTest

@testable import clawd_back

final class AccessibilityAppTests: XCTestCase {
  func testKindIsGeneric() {
    let app = AccessibilityApp(bundleIdentifier: "com.example.nonexistent")
    XCTAssertEqual(app.kind, .generic)
    XCTAssertEqual(app.bundleIdentifier, "com.example.nonexistent")
  }

  // swift test runs unbundled, so bundledResource() has nothing to find and
  // pid resolution also fails for a bundle id nothing is running under; both
  // guards should short-circuit to the same "nothing to do" values the
  // Ghostty conformer returns when its own bundled scripts are missing.
  func testUnbundledOrUnresolvedProcessFailsGracefully() {
    let app = AccessibilityApp(bundleIdentifier: "com.example.nonexistent")
    XCTAssertNil(app.frontTarget())
    XCTAssertFalse(app.windowExists("Some Window"))
    XCTAssertEqual(app.focusSteps(for: WindowFocusTarget(window: "Some Window", tab: nil)), [])
  }
}
