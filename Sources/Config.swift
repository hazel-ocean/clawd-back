import Foundation
import TOMLDecoder

struct AppConfig: Codable {
  let application: String
  // Required when application == "generic": the bundle id of the app to
  // claw back to, since .generic has no fixed identity of its own.
  let bundleIdentifier: String?
  // Lifts the WindowServer gate's macOS ceiling only. The floor and the Apple
  // Silicon requirement stand.
  let forceWindowServerRaiseEnabled: Bool?
}

func forceWindowServerRaiseEnabled() -> Bool {
  loadConfig()?.forceWindowServerRaiseEnabled ?? false
}

// The configured app to claw back to, from ~/.config/clawd-back/config.{toml,json},
// resolved to its concrete driver. Falls back to Ghostty when there's no
// valid config.
func loadConfig() -> AppConfig? {
  let configDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".config/clawd-back", isDirectory: true)

  if let data = try? Data(contentsOf: configDir.appendingPathComponent("config.toml")),
    let config = try? TOMLDecoder().decode(AppConfig.self, from: data)
  {
    return config
  }
  if let data = try? Data(contentsOf: configDir.appendingPathComponent("config.json")),
    let config = try? JSONDecoder().decode(AppConfig.self, from: data)
  {
    return config
  }
  return nil
}

func loadConfiguredApp() -> any AppActivation {
  guard let config = loadConfig(), let application = Application(rawValue: config.application)
  else { return Ghostty() }
  return resolvedApp(for: application, bundleIdentifier: config.bundleIdentifier)
}
