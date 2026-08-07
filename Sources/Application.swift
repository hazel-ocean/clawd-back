import AppKit
import Foundation

// Applications ClawdBack knows how to claw back to. The config's `application`
// string decodes into one of these; an unknown value falls back to .ghostty.
// .generic is not tied to a specific app: it's the fallback for any app with
// no AppleScript dictionary, addressed by a bundle id supplied in config.
enum Application: String, Codable, CaseIterable {
  case ghostty, wezterm, iterm2, terminal, alacritty, kitty, rio, generic

  // nil for .generic: that case has no fixed identity, its bundle id comes
  // from config at resolve time instead.
  var bundleIdentifier: String? {
    switch self {
    case .ghostty: return "com.mitchellh.ghostty"
    case .wezterm: return "com.github.wez.wezterm"
    case .iterm2: return "com.googlecode.iterm2"
    case .terminal: return "com.apple.Terminal"
    case .alacritty: return "org.alacritty"
    case .kitty: return "net.kovidgoyal.kitty"
    case .rio: return "com.raphaelamorim.rio"
    case .generic: return nil
    }
  }
}

// A specific window (and, when the app has tabs, tab) to raise. Serialized
// into the per-session state and the notification payload.
struct WindowFocusTarget: Equatable, Codable {
  let window: String
  let tab: String?
}

// Every app ClawdBack can drive. Identity + activation need nothing but a
// bundle id, so they come free to every conformer.
protocol AppActivation {
  var kind: Application { get }
  var bundleIdentifier: String { get }
  // A requirement (not just an extension member) so it dispatches dynamically
  // and tests can supply an app with a known frontmost state.
  var isFrontmost: Bool { get }
}

extension AppActivation {
  var isFrontmost: Bool {
    NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleIdentifier
  }

  // Cross-app raise. `open -b` does a real app activation (unlike AppleScript
  // `activate window`, which only reorders windows within an already-front app),
  // so focus survives even when another app was frontmost. Also step one of a
  // claw-back plan.
  func activationStep() -> String {
    "/usr/bin/open -b \(shq(bundleIdentifier))"
  }
}

// Capability: read the current window/tab and select a specific one. Only an
// app that exposes stable window/tab ids and a way to select them can conform
// directly; today that is Ghostty (see Ghostty.swift, via its AppleScript
// dictionary). Anything without a dictionary goes through AccessibilityApp
// (see Accessibility/AccessibilityApp.swift), which addresses windows
// generically by title via System Events instead.
protocol WindowFocus: AppActivation {
  // The front window+tab right now. Used both to capture at SessionStart and to
  // compare for skip-when-viewing.
  func frontTarget() -> WindowFocusTarget?

  // Does the captured window still exist? False ⇒ claw-back can't land on it.
  func windowExists(_ window: String) -> Bool

  // Shell steps that raise `target`'s window and select its tab.
  func focusSteps(for target: WindowFocusTarget) -> [String]
}

// An app we can raise but not address by window/tab. Used for the named
// terminals that aren't Ghostty; adding window/tab support for one of them
// later is just a new WindowFocus conformer.
struct BaselineApp: AppActivation {
  let kind: Application
  var bundleIdentifier: String { kind.bundleIdentifier! }
}

// Pure resolver: given a configured application kind (and, for .generic, the
// bundle id from config), returns the conformer that drives it.
func resolvedApp(for application: Application, bundleIdentifier: String?) -> any AppActivation {
  switch application {
  case .ghostty: return Ghostty()
  case .generic: return AccessibilityApp(bundleIdentifier: bundleIdentifier ?? Application.ghostty.bundleIdentifier!)
  default: return BaselineApp(kind: application)
  }
}
