import XCTest

@testable import clawd_back

private struct FakeBaseline: TerminalApp {
  let kind: Terminal
  var isFrontmost: Bool
  var bundleIdentifier: String { kind.bundleIdentifier }
}

private struct FakeWindowTerminal: WindowFocus {
  let kind: Terminal
  var isFrontmost: Bool
  var front: WindowFocusTarget?
  var steps: [String]
  var bundleIdentifier: String { kind.bundleIdentifier }
  func frontTarget() -> WindowFocusTarget? { front }
  func focusSteps(for target: WindowFocusTarget) -> [String] { steps }
}

private struct FakeMux: MultiplexerFocus {
  let kind: MultiplexerKind
  var focused: Bool
  var steps: [String]
  func currentTarget(env: [String: String]) -> MultiplexerFocusTarget? { nil }
  func isFocused(on target: MultiplexerFocusTarget) -> Bool { focused }
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
    XCTAssertEqual(
      plan.steps,
      ["sleep 0.3", "/usr/bin/open -b '\(Terminal.ghostty.bundleIdentifier)'", "SELECT"])
  }

  func testMultiplexerOnlyPlanOnBaselineTerminal() {
    let term = FakeBaseline(kind: .rio, isFrontmost: false)
    let mux = FakeMux(kind: .zellij, focused: false, steps: ["FOCUS"])
    let plan = focusPlan(
      term: term, terminalTarget: nil, multiplexerTarget: muxTarget,
      resolveMultiplexer: resolve(mux))
    XCTAssertEqual(
      plan.steps,
      ["sleep 0.3", "/usr/bin/open -b '\(Terminal.rio.bundleIdentifier)'", "FOCUS"])
  }

  func testWindowBeforeMultiplexer() {
    let term = FakeWindowTerminal(
      kind: .ghostty, isFrontmost: false, front: nil, steps: ["SELECT"])
    let mux = FakeMux(kind: .zellij, focused: false, steps: ["FOCUS"])
    let plan = focusPlan(
      term: term, terminalTarget: winTarget, multiplexerTarget: muxTarget,
      resolveMultiplexer: resolve(mux))
    XCTAssertEqual(plan.steps.suffix(2), ["SELECT", "FOCUS"])
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
