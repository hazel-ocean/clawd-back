import XCTest

@testable import clawd_back

// The leading steps every non-empty plan shares: block on this app's quit
// (CLAWD_PID, set by runDetached), then a short settle. See `focusPlan`.
private let waitForQuit = ["while kill -0 \"$CLAWD_PID\" 2>/dev/null; do sleep 0.02; done", "sleep 0.1"]

private struct FakeBaseline: AppActivation {
  let kind: Application
  var isFrontmost: Bool
  var bundleIdentifier: String { kind.bundleIdentifier! }
}

private struct FakeWindowTerminal: WindowFocus {
  let kind: Application
  var isFrontmost: Bool
  var front: WindowFocusTarget?
  var steps: [String]
  var exists: Bool = true
  var bundleIdentifier: String { kind.bundleIdentifier! }
  func frontTarget() -> WindowFocusTarget? { front }
  func windowExists(_ window: String) -> Bool { exists }
  func focusSteps(for target: WindowFocusTarget) -> [String] { steps }
}

private struct FakeMux: MultiplexerFocus {
  let kind: MultiplexerKind
  var focused: Bool
  var steps: [String]
  var state: MultiplexerSessionState = .attached
  func currentTarget(env: [String: String]) -> MultiplexerFocusTarget? { nil }
  func isFocused(on target: MultiplexerFocusTarget) -> Bool { focused }
  func sessionState(on target: MultiplexerFocusTarget) -> MultiplexerSessionState { state }
  func focusSteps(for target: MultiplexerFocusTarget) -> [String] { steps }
}

final class FocusPlanTests: XCTestCase {
  private let winTarget = WindowFocusTarget(window: "w1", tab: "t1")
  private let muxTarget = MultiplexerFocusTarget(kind: .zellij, session: "main", pane: "3")

  private func resolve(_ mux: FakeMux) -> (MultiplexerKind) -> any MultiplexerFocus {
    { _ in mux }
  }

  func testWindowOnlyPlanOrder() {
    let term = FakeWindowTerminal(
      kind: .ghostty, isFrontmost: false, front: nil, steps: ["SELECT"])
    let plan = focusPlan(
      term: term, terminalTarget: winTarget, multiplexerTarget: nil)
    // A window raise self-activates, so no open -b step; re-asserted once.
    XCTAssertEqual(plan.steps, waitForQuit + ["SELECT", "sleep 0.15", "SELECT"])
  }

  func testMultiplexerOnlyPlanOnBaselineTerminal() {
    let term = FakeBaseline(kind: .rio, isFrontmost: false)
    let mux = FakeMux(kind: .zellij, focused: false, steps: ["FOCUS"])
    let plan = focusPlan(
      term: term, terminalTarget: nil, multiplexerTarget: muxTarget,
      resolveMultiplexer: resolve(mux))
    XCTAssertEqual(
      plan.steps,
      waitForQuit + ["FOCUS", "/usr/bin/open -b '\(Application.rio.bundleIdentifier!)'"])
  }

  func testMultiplexerBeforeWindowSoWindowRaiseIsLast() {
    let term = FakeWindowTerminal(
      kind: .ghostty, isFrontmost: false, front: nil, steps: ["SELECT"])
    let mux = FakeMux(kind: .zellij, focused: false, steps: ["FOCUS"])
    let plan = focusPlan(
      term: term, terminalTarget: winTarget, multiplexerTarget: muxTarget,
      resolveMultiplexer: resolve(mux))
    // Pane focus first (session state), window raise last (wins OS focus);
    // the raise self-activates, so no open -b, and is re-asserted once.
    XCTAssertEqual(plan.steps, waitForQuit + ["FOCUS", "SELECT", "sleep 0.15", "SELECT"])
  }

  func testNothingToFocusIsEmpty() {
    let term = FakeBaseline(kind: .rio, isFrontmost: false)
    let plan = focusPlan(term: term, terminalTarget: nil, multiplexerTarget: nil)
    XCTAssertTrue(plan.steps.isEmpty)
  }

  func testTerminalTargetOnBaselineIsIgnored() {
    // A window target with a terminal that can't address windows ⇒ no plan.
    let term = FakeBaseline(kind: .rio, isFrontmost: false)
    let plan = focusPlan(term: term, terminalTarget: winTarget, multiplexerTarget: nil)
    XCTAssertTrue(plan.steps.isEmpty)
  }
}

final class ResolveFocusTests: XCTestCase {
  private let winTarget = WindowFocusTarget(window: "w1", tab: "t1")
  private let muxTarget = MultiplexerFocusTarget(kind: .zellij, session: "main", pane: "3")

  private func resolve(_ mux: FakeMux) -> (MultiplexerKind) -> any MultiplexerFocus {
    { _ in mux }
  }
  private func failure(_ outcome: FocusOutcome) -> FocusFailure? {
    if case .failure(let f) = outcome { return f }
    return nil
  }
  private func plan(_ outcome: FocusOutcome) -> FocusPlan? {
    if case .focus(let p) = outcome { return p }
    return nil
  }

  func testDetachedSessionFails() {
    let term = FakeWindowTerminal(
      kind: .ghostty, isFrontmost: false, front: nil, steps: ["SELECT"])
    let mux = FakeMux(kind: .zellij, focused: false, steps: ["FOCUS"], state: .detached)
    let outcome = resolveFocus(
      term: term, terminalTarget: winTarget, multiplexerTarget: muxTarget,
      resolveMultiplexer: resolve(mux))
    XCTAssertEqual(failure(outcome), .sessionDetached)
  }

  func testMissingSessionFailsDistinctly() {
    let term = FakeWindowTerminal(
      kind: .ghostty, isFrontmost: false, front: nil, steps: ["SELECT"])
    let mux = FakeMux(kind: .zellij, focused: false, steps: ["FOCUS"], state: .missing)
    let outcome = resolveFocus(
      term: term, terminalTarget: winTarget, multiplexerTarget: muxTarget,
      resolveMultiplexer: resolve(mux))
    XCTAssertEqual(failure(outcome), .sessionMissing)
  }

  func testUnreachableMultiplexerReadsAsDetached() {
    let term = FakeWindowTerminal(
      kind: .ghostty, isFrontmost: false, front: nil, steps: ["SELECT"])
    let mux = FakeMux(kind: .zellij, focused: false, steps: ["FOCUS"], state: .unreachable)
    let outcome = resolveFocus(
      term: term, terminalTarget: winTarget, multiplexerTarget: muxTarget,
      resolveMultiplexer: resolve(mux))
    XCTAssertEqual(failure(outcome), .sessionDetached)
  }

  func testGoneWindowFails() {
    let term = FakeWindowTerminal(
      kind: .ghostty, isFrontmost: false, front: nil, steps: ["SELECT"], exists: false)
    let outcome = resolveFocus(
      term: term, terminalTarget: winTarget, multiplexerTarget: nil)
    XCTAssertEqual(failure(outcome), .windowGone)
  }

  func testDetachedWinsOverGoneWindow() {
    let term = FakeWindowTerminal(
      kind: .ghostty, isFrontmost: false, front: nil, steps: ["SELECT"], exists: false)
    let mux = FakeMux(kind: .zellij, focused: false, steps: ["FOCUS"], state: .detached)
    let outcome = resolveFocus(
      term: term, terminalTarget: winTarget, multiplexerTarget: muxTarget,
      resolveMultiplexer: resolve(mux))
    XCTAssertEqual(failure(outcome), .sessionDetached)
  }

  func testHealthyResolvesToTodaysFocusPlan() {
    let term = FakeWindowTerminal(
      kind: .ghostty, isFrontmost: false, front: nil, steps: ["SELECT"])
    let mux = FakeMux(kind: .zellij, focused: false, steps: ["FOCUS"])
    let outcome = resolveFocus(
      term: term, terminalTarget: winTarget, multiplexerTarget: muxTarget,
      resolveMultiplexer: resolve(mux))
    XCTAssertEqual(plan(outcome)?.steps, waitForQuit + ["FOCUS", "SELECT", "sleep 0.15", "SELECT"])
  }

  func testBaselineNoMultiplexerResolvesToFocus() {
    let term = FakeBaseline(kind: .rio, isFrontmost: false)
    let outcome = resolveFocus(
      term: term, terminalTarget: winTarget, multiplexerTarget: nil)
    XCTAssertNotNil(plan(outcome))
  }
}

final class FocusPayloadTests: XCTestCase {
  private let winTarget = WindowFocusTarget(window: "w1", tab: "t1")
  private let muxTarget = MultiplexerFocusTarget(kind: .zellij, session: "main", pane: "3")

  func testRoundTripsMessageFolderAndCwd() {
    let info = FocusPayload.userInfo(
      terminal: winTarget, multiplexer: muxTarget,
      title: "Claude Code", message: "needs you", folder: "myrepo", cwd: "/repos/myrepo",
      sessionId: "abc-123")
    let state = FocusPayload.decode(info)
    XCTAssertFalse(state.isLocator)
    XCTAssertEqual(state.terminal, winTarget)
    XCTAssertEqual(state.multiplexer, muxTarget)
    XCTAssertEqual(state.message, "needs you")
    XCTAssertEqual(state.folder, "myrepo")
    XCTAssertEqual(state.cwd, "/repos/myrepo")
    XCTAssertEqual(state.sessionId, "abc-123")
  }

  func testEmptyFolderAndCwdDecodeNil() {
    let info = FocusPayload.userInfo(
      terminal: nil, multiplexer: nil, title: "T", message: "m", folder: nil, cwd: nil,
      sessionId: nil)
    let state = FocusPayload.decode(info)
    XCTAssertNil(state.folder)
    XCTAssertNil(state.cwd)
    XCTAssertNil(state.sessionId)
  }
}

final class LocatorPayloadTests: XCTestCase {
  // A locator has to be recognisable on click, or clicking one posts another.
  func testLocatorFlagRoundTrips() {
    let info = FocusPayload.userInfo(
      terminal: nil, multiplexer: nil, title: "T", message: "m", folder: nil, cwd: nil,
      sessionId: "abc-123", isLocator: true)
    XCTAssertTrue(FocusPayload.decode(info).isLocator)
  }
}

final class LocatorContentTests: XCTestCase {
  private let muxTarget = MultiplexerFocusTarget(kind: .zellij, session: "main", pane: "3")
  private let winTarget = WindowFocusTarget(window: "w1", tab: "t1")

  private func state(
    mux: MultiplexerFocusTarget?, folder: String? = nil, cwd: String? = nil,
    message: String = "needs you"
  ) -> FocusState {
    FocusState(
      terminal: winTarget, multiplexer: mux, title: "Claude Code", message: message,
      folder: folder, cwd: cwd)
  }

  func testTitleLeadsWithSessionAndIssue() {
    let (title, body) = locatorContent(.windowGone, state: state(mux: muxTarget))
    XCTAssertEqual(title, "[main] - Window closed")
    XCTAssertTrue(body.contains("The zellij session is attached elsewhere."))
    // The title names the session, so the body does not repeat it.
    XCTAssertFalse(body.contains("main"))
  }

  func testSessionNameWinsOverFolderLabel() {
    let (title, _) = locatorContent(.windowGone, state: state(mux: muxTarget, folder: "myrepo"))
    XCTAssertEqual(title, "[main] - Window closed")
  }

  func testFolderLabelsTheTitleWithoutASession() {
    let (title, body) = locatorContent(.windowGone, state: state(mux: nil, folder: "myrepo"))
    XCTAssertEqual(title, "[myrepo] - Window closed")
    XCTAssertTrue(body.contains("The terminal window is closed."))
  }

  func testDetachedQuotesTheAttachCommand() {
    let spaced = MultiplexerFocusTarget(kind: .zellij, session: "my main", pane: "3")
    let (title, body) = locatorContent(.sessionDetached, state: state(mux: spaced))
    XCTAssertEqual(title, "[my main] - Session detached")
    XCTAssertTrue(body.contains("Attach: zellij attach 'my main'"))
  }

  func testMissingSessionSaysItMayBeRenamed() {
    let (title, body) = locatorContent(.sessionMissing, state: state(mux: muxTarget))
    XCTAssertEqual(title, "[main] - Session not found")
    XCTAssertTrue(body.contains("gone, possibly renamed"))
  }

  func testTranscriptMessageIsNotInTheBody() {
    let (_, body) = locatorContent(
      .windowGone, state: state(mux: muxTarget, message: "Good question, and it exposes"))
    XCTAssertFalse(body.contains("Good question"))
  }

  func testStaleWindowIdsAreNotInTheBody() {
    let (_, body) = locatorContent(.windowGone, state: state(mux: muxTarget))
    XCTAssertFalse(body.contains("w1"))
    XCTAssertFalse(body.contains("t1"))
  }

  func testLongCwdIsAbbreviated() {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let (_, body) = locatorContent(
      .windowGone,
      state: state(mux: muxTarget, cwd: "\(home)/OneSignal/workbench/workspaces/sms-1580"))
    XCTAssertTrue(body.contains("Last in: ~/…/workbench/workspaces/sms-1580"))
  }

  func testShortCwdIsShownWhole() {
    let (_, body) = locatorContent(.windowGone, state: state(mux: muxTarget, cwd: "/repos/myrepo"))
    XCTAssertTrue(body.contains("Last in: /repos/myrepo"))
  }

  func testNoCwdLeavesTheBodyAtOneLine() {
    let (_, body) = locatorContent(.windowGone, state: state(mux: muxTarget))
    XCTAssertEqual(body, "The zellij session is attached elsewhere.")
  }
}

final class BannerPathTests: XCTestCase {
  func testHomeBecomesTilde() {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    XCTAssertEqual(bannerPath("\(home)/a/b"), "~/a/b")
  }

  func testDeepAbsolutePathKeepsTheLastThree() {
    XCTAssertEqual(bannerPath("/a/b/c/d/e"), "/…/c/d/e")
  }

  func testShallowPathIsUnchanged() {
    XCTAssertEqual(bannerPath("/a/b/c"), "/a/b/c")
  }
}

final class IsViewingTests: XCTestCase {
  private let winTarget = WindowFocusTarget(window: "w1", tab: "t1")
  private let muxTarget = MultiplexerFocusTarget(kind: .zellij, session: "main", pane: "3")

  private func resolve(_ mux: FakeMux) -> (MultiplexerKind) -> any MultiplexerFocus {
    { _ in mux }
  }

  func testNotFrontmostIsNotViewing() {
    let term = FakeWindowTerminal(
      kind: .ghostty, isFrontmost: false, front: winTarget, steps: [])
    XCTAssertFalse(
      isViewing(term: term, terminalTarget: winTarget, multiplexerTarget: nil))
  }

  func testFrontmostBaselineWithoutTargetsIsNotViewing() {
    // The conservative gate: frontmost but nothing positively confirmed ⇒ notify.
    let term = FakeBaseline(kind: .rio, isFrontmost: true)
    XCTAssertFalse(
      isViewing(term: term, terminalTarget: nil, multiplexerTarget: nil))
  }

  func testWindowMatchIsViewing() {
    let term = FakeWindowTerminal(
      kind: .ghostty, isFrontmost: true, front: winTarget, steps: [])
    XCTAssertTrue(
      isViewing(term: term, terminalTarget: winTarget, multiplexerTarget: nil))
  }

  func testWindowMismatchIsNotViewing() {
    let term = FakeWindowTerminal(
      kind: .ghostty, isFrontmost: true,
      front: WindowFocusTarget(window: "other", tab: "t1"), steps: [])
    XCTAssertFalse(
      isViewing(term: term, terminalTarget: winTarget, multiplexerTarget: nil))
  }

  func testMultiplexerFocusedIsViewing() {
    let term = FakeBaseline(kind: .rio, isFrontmost: true)
    let mux = FakeMux(kind: .zellij, focused: true, steps: [])
    XCTAssertTrue(
      isViewing(
        term: term, terminalTarget: nil, multiplexerTarget: muxTarget,
        resolveMultiplexer: resolve(mux)))
  }

  func testMultiplexerNotFocusedIsNotViewing() {
    let term = FakeBaseline(kind: .rio, isFrontmost: true)
    let mux = FakeMux(kind: .zellij, focused: false, steps: [])
    XCTAssertFalse(
      isViewing(
        term: term, terminalTarget: nil, multiplexerTarget: muxTarget,
        resolveMultiplexer: resolve(mux)))
  }

  func testWindowMatchButMultiplexerUnfocusedIsNotViewing() {
    let term = FakeWindowTerminal(
      kind: .ghostty, isFrontmost: true, front: winTarget, steps: [])
    let mux = FakeMux(kind: .zellij, focused: false, steps: [])
    XCTAssertFalse(
      isViewing(
        term: term, terminalTarget: winTarget, multiplexerTarget: muxTarget,
        resolveMultiplexer: resolve(mux)))
  }
}
