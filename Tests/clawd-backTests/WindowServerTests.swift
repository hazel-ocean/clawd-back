import XCTest

@testable import clawd_back

private let waitForQuit = [
  "while kill -0 \"$CLAWD_PID\" 2>/dev/null; do sleep 0.02; done", "sleep 0.1",
]

private struct FakeWindowApp: WindowFocus {
  let kind = Application.ghostty
  var isFrontmost = false
  var pid: pid_t?
  var bundleIdentifier: String { kind.bundleIdentifier! }
  func frontTarget() -> WindowFocusTarget? { nil }
  func windowExists(_ target: WindowFocusTarget) -> Bool { true }
  // Stands in for the generic conformer, the one that carries an activation.
  func focusSteps(for target: WindowFocusTarget, raised: Bool) -> [String] {
    raised ? ["FOCUS"] : ["ACTIVATE", "FOCUS"]
  }
}

final class RaisePlanTests: XCTestCase {
  private let raisable = WindowFocusTarget(window: "w1", tab: "t1", cgWindowId: 42)

  func testRaiseReplacesActivationAndReassert() {
    let term = FakeWindowApp(pid: 7)
    let plan = focusPlan(
      term: term, terminalTarget: raisable, multiplexerTarget: nil, raiseSupported: true)
    XCTAssertEqual(plan.raise, RaiseRequest(pid: 7, window: 42))
    XCTAssertEqual(plan.steps, waitForQuit + ["FOCUS"])
  }

  func testClosedGateKeepsTheShellPlan() {
    let term = FakeWindowApp(pid: 7)
    let plan = focusPlan(
      term: term, terminalTarget: raisable, multiplexerTarget: nil, raiseSupported: false)
    XCTAssertNil(plan.raise)
    XCTAssertEqual(
      plan.steps, waitForQuit + ["ACTIVATE", "FOCUS", "sleep 0.15", "ACTIVATE", "FOCUS"])
  }

  // A target captured before window ids existed, or an app that is no longer
  // running: same fallback as a closed gate.
  func testNoWindowIdMeansNoRaise() {
    let term = FakeWindowApp(pid: 7)
    let plan = focusPlan(
      term: term, terminalTarget: WindowFocusTarget(window: "w1", tab: "t1"),
      multiplexerTarget: nil, raiseSupported: true)
    XCTAssertNil(plan.raise)
  }

  func testNoProcessMeansNoRaise() {
    let term = FakeWindowApp(pid: nil)
    let plan = focusPlan(
      term: term, terminalTarget: raisable, multiplexerTarget: nil, raiseSupported: true)
    XCTAssertNil(plan.raise)
  }
}

final class SkyLightGateTests: XCTestCase {
  private func version(_ major: Int, _ minor: Int = 0) -> OperatingSystemVersion {
    OperatingSystemVersion(majorVersion: major, minorVersion: minor, patchVersion: 0)
  }

  func testBelowFloorIsClosed() {
    XCTAssertFalse(versionSupported(version(13, 7), forceEnabled: false))
  }

  func testVerifiedRangeIsOpen() {
    XCTAssertTrue(versionSupported(version(14), forceEnabled: false))
    XCTAssertTrue(versionSupported(version(26), forceEnabled: false))
    // Every macOS 26 release passes, including ones that have not shipped.
    XCTAssertTrue(versionSupported(version(26, 99), forceEnabled: false))
  }

  func testCeilingIsExclusive() {
    XCTAssertFalse(versionSupported(version(27), forceEnabled: false))
  }

  func testEscapeHatchLiftsTheCeilingOnly() {
    XCTAssertTrue(versionSupported(version(27), forceEnabled: true))
    XCTAssertFalse(versionSupported(version(13, 7), forceEnabled: true))
  }
}

final class WindowFocusTargetTests: XCTestCase {
  func testDecodesWithoutAWindowId() throws {
    let json = Data(#"{"window":"w1","tab":"t1"}"#.utf8)
    let target = try JSONDecoder().decode(WindowFocusTarget.self, from: json)
    XCTAssertEqual(target.window, "w1")
    XCTAssertNil(target.cgWindowId)
  }

  func testWindowIdRoundTrips() throws {
    let target = WindowFocusTarget(window: "w1", tab: "t1", cgWindowId: 42)
    let decoded = try JSONDecoder().decode(
      WindowFocusTarget.self, from: JSONEncoder().encode(target))
    XCTAssertEqual(decoded.cgWindowId, 42)
  }

  func testSameWindowIgnoresTheWindowId() {
    XCTAssertTrue(
      WindowFocusTarget(window: "w1", tab: "t1", cgWindowId: 42)
        .isSameWindow(as: WindowFocusTarget(window: "w1", tab: "t1")))
    XCTAssertFalse(
      WindowFocusTarget(window: "w1", tab: "t1", cgWindowId: 42)
        .isSameWindow(as: WindowFocusTarget(window: "w2", tab: "t1", cgWindowId: 42)))
  }

  // Equality is whole-value again, so a window id difference shows up.
  func testEqualityIncludesTheWindowId() {
    XCTAssertNotEqual(
      WindowFocusTarget(window: "w1", tab: "t1", cgWindowId: 42),
      WindowFocusTarget(window: "w1", tab: "t1"))
  }
}
