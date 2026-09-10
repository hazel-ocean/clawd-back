import AppKit
import Foundation

// The application a Claude session runs inside, recorded per session so a
// claw-back can target whatever hosts the agent: a terminal, or an editor
// speaking ACP to Claude Code.
//
// macOS stamps `__CFBundleIdentifier` on every process an application launches,
// and children inherit it, so inside the session the stamp already names the
// host: a shell in Ghostty carries com.mitchellh.ghostty, and Claude Code run by
// Obsidian's agent client carries md.obsidian. It cannot be read here, because
// LaunchServices overwrites it with our own id in the app that `open` launches,
// so the hook forwards it and this reads the flag.
//
// A hook that sends nothing (an older one) leaves the host unnamed, and the
// configured application answers as before.
func hostBundleId(_ arg: String?) -> String? {
  guard let arg, !arg.isEmpty, arg != Bundle.main.bundleIdentifier else { return nil }
  return arg
}

// A recorded host resolves to its own driver: a host we hold a dictionary for
// keeps window/tab addressing, anything else is addressed generically through
// Accessibility.
func resolvedHost(_ bundleIdentifier: String) -> any AppActivation {
  let known = Application.allCases.first { $0.bundleIdentifier == bundleIdentifier }
  return resolvedApp(for: known ?? .generic, bundleIdentifier: bundleIdentifier)
}

// The app to claw back to. The session's own host wins, so one machine can run
// sessions in several hosts at once; the config is the fallback for a session
// whose host nothing named.
func appForSession(host: String?) -> any AppActivation {
  guard let host else { return loadConfiguredApp() }
  return resolvedHost(host)
}
