import Foundation

// Common install locations. Nix profiles are included so this resolves on
// nix-darwin / home-manager setups, not just Homebrew.
private let zellijPaths = [
  "/opt/homebrew/bin/zellij",
  "/usr/local/bin/zellij",
  "/run/current-system/sw/bin/zellij",
  "\(NSHomeDirectory())/.nix-profile/bin/zellij",
  "/etc/profiles/per-user/\(NSUserName())/bin/zellij",
  "/usr/bin/zellij",
]

func findZellijPath() -> String? {
  zellijPaths.first { FileManager.default.fileExists(atPath: $0) }
}
