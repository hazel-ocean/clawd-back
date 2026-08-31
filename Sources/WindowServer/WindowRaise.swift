import CoreGraphics
import Foundation
import AppKit

// Resolved by `raiseRequest` before the plan is built, so the plan stays a list
// of shell steps and the AppDelegate performs the in-process part.
struct RaiseRequest: Equatable {
  let pid: pid_t
  let window: CGWindowID
}

// Steps 1, 2 and 4 of AltTab's focus sequence. Step 3, the intra-app AXRaise,
// stays in the detached shell, where Ghostty's `select tab` and the generic
// path's AXRaise already do it: performing it here needs an AXUIElement, which
// has no lookup from a window id and would drag in a brute-force search and a
// cache. False means the plan must carry its own activation: nil request (there
// was nothing to raise), a shut gate, or a step that failed.
func raiseWindow(_ request: RaiseRequest?, forceEnabled: Bool) -> Bool {
  guard let request else { return false }
  counter(.raiseAttempted)
  guard let sky = SkyLight.load(forceEnabled: forceEnabled),
    var psn = sky.processSerialNumber(for: request.pid)
  else {
    counter(.fellBackToShellPlan)
    return false
  }

  // Snapshot before the front, because fronting is what changes both.
  let origin = originToRepair(sky, request: request)

  guard sky.front(&psn, window: request.window) else {
    counter(.raiseFailed)
    counter(.fellBackToShellPlan)
    return false
  }
  sky.makeKey(&psn, window: request.window)
  if let origin { sky.restoreFront(of: origin.space, to: origin.pid) }

  counter(.raiseSucceeded)
  return true
}

private func originToRepair(
  _ sky: SkyLight, request: RaiseRequest
) -> (space: CGSSpaceID, pid: pid_t)? {
  guard let current = sky.currentSpace() else { return nil }
  let target = sky.spaces(of: request.window)
  guard !target.isEmpty, !target.contains(current) else { return nil }
  counter(.targetOffSpace)
  guard let front = NSWorkspace.shared.frontmostApplication?.processIdentifier,
    front != request.pid
  else { return nil }
  return (current, front)
}

// Only called at capture time, when the window is frontmost, so the first
// on-screen match at layer 0 is the right one.
func frontWindowId(pid: pid_t) -> CGWindowID? {
  guard
    let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID)
      as? [[String: Any]]
  else { return nil }
  for window in windows {
    guard window[kCGWindowOwnerPID as String] as? pid_t == pid,
      window[kCGWindowLayer as String] as? Int == 0,
      let id = window[kCGWindowNumber as String] as? CGWindowID
    else { continue }
    return id
  }
  return nil
}

// Answers across Spaces, and does not depend on a title that an app may rewrite
// as its open document changes.
//
// Two traps here, both of which report a live window as closed:
//   * `kCGWindowListOptionIncludingWindow` is intersected with on-screen. A
//     background tab of a native macOS tab group is ordered out, so it answers
//     empty, and a waiting claw-back targets exactly such a tab.
//   * the array holds window ids cast to pointers, NOT CFNumbers. NSNumbers
//     silently match nothing.
func windowIdExists(_ window: CGWindowID) -> Bool {
  guard let id = UnsafeRawPointer(bitPattern: UInt(window)) else { return false }
  var ids: [UnsafeRawPointer?] = [id]
  guard let array = CFArrayCreate(nil, &ids, 1, nil),
    let info = CGWindowListCreateDescriptionFromArray(array) as? [[String: Any]]
  else { return false }
  return !info.isEmpty
}
