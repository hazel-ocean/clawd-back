import Foundation

// Capability: read the current window/tab and select a specific one. Only a
// terminal that exposes stable window/tab ids and a way to select them can
// conform; today that is Ghostty (via its AppleScript dictionary). Terminals
// without it degrade to activation only. The scripts it runs live beside this
// file as standalone .applescript files, bundled into Contents/Resources/Ghostty.
struct Ghostty: WindowFocus {
  let kind = Terminal.ghostty
  var bundleIdentifier: String { kind.bundleIdentifier }

  func frontTarget() -> WindowFocusTarget? {
    guard
      let script = bundledResource("Ghostty/ghostty-front-target.applescript"),
      let out = runProcess("/usr/bin/osascript", [script]), out.contains("\t")
    else { return nil }
    let p = out.components(separatedBy: "\t")
    return p.count == 2 ? WindowFocusTarget(window: p[0], tab: p[1]) : nil
  }

  func windowExists(_ window: String) -> Bool {
    guard
      let script = bundledResource("Ghostty/ghostty-window-exists.applescript"),
      let out = runProcess("/usr/bin/osascript", [script, window])
    else { return false }
    return out == "true"
  }

  // The ids ride across as osascript argv, so nothing is interpolated into the
  // AppleScript source: no escaping, no temp file, no injection surface.
  func focusSteps(for target: WindowFocusTarget) -> [String] {
    guard let script = bundledResource("Ghostty/ghostty-focus.applescript")
    else { return [] }
    var step = "/usr/bin/osascript \(shq(script)) \(shq(target.window))"
    if let tab = target.tab, !tab.isEmpty { step += " \(shq(tab))" }
    return [step]
  }
}
