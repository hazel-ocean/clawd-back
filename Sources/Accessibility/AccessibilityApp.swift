import AppKit
import Foundation

// Generic WindowFocus fallback for any app without its own AppleScript
// dictionary (see Application.swift's .generic case). Addresses windows by
// title via System Events/Accessibility rather than a stable id, since
// generic AXWindows expose no id the way Ghostty's dictionary does. A stale
// title (e.g. an app whose title changes with the active document) just
// resolves to windowExists returning false, which FocusFailure.swift already
// turns into a locator notification, not a crash.
//
// Scripts take the target process id, not its name: System Events' process
// names are inconsistent in case/format across apps, so pid is the only
// reliable handle.
struct AccessibilityApp: WindowFocus {
  let kind = Application.generic
  let bundleIdentifier: String

  private var pid: pid_t? {
    NSWorkspace.shared.runningApplications
      .first { $0.bundleIdentifier == bundleIdentifier }?
      .processIdentifier
  }

  func frontTarget() -> WindowFocusTarget? {
    guard
      let pid,
      let script = bundledResource("Accessibility/ax-front-target.applescript"),
      let title = runProcess("/usr/bin/osascript", [script, String(pid)]),
      !title.isEmpty
    else { return nil }
    return WindowFocusTarget(window: title, tab: nil)
  }

  func windowExists(_ window: String) -> Bool {
    guard
      let pid,
      let script = bundledResource("Accessibility/ax-window-exists.applescript"),
      let out = runProcess("/usr/bin/osascript", [script, String(pid), window])
    else { return false }
    return out == "true"
  }

  // The pid and title ride as osascript argv, same injection-safe pattern as
  // Ghostty's scripts: nothing is interpolated into the AppleScript source.
  // `open -b` runs first: System Events' `tell process id` fails if the
  // process isn't already running, and this also gets it roughly frontmost
  // even if Accessibility permission turns out to be denied.
  func focusSteps(for target: WindowFocusTarget) -> [String] {
    guard
      let pid,
      let script = bundledResource("Accessibility/ax-focus.applescript")
    else { return [] }
    return [
      activationStep(),
      "/usr/bin/osascript \(shq(script)) \(shq(String(pid))) \(shq(target.window))",
    ]
  }
}
