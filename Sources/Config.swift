import Foundation
import TOMLDecoder

struct AppConfig: Codable {
  let application: String
  // Required when application == "generic": the bundle id of the app to
  // claw back to, since .generic has no fixed identity of its own.
  let bundleIdentifier: String?
}

// The configured app to claw back to, from ~/.config/clawd-back/config.{toml,json},
// resolved to its concrete driver. Falls back to Ghostty when there's no
// valid config.
func loadConfiguredApp() -> any AppActivation {
  let configDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".config/clawd-back", isDirectory: true)

  let tomlPath = configDir.appendingPathComponent("config.toml")
  let jsonPath = configDir.appendingPathComponent("config.json")

  if let data = try? Data(contentsOf: tomlPath),
    let config = try? TOMLDecoder().decode(AppConfig.self, from: data),
    let application = Application(rawValue: config.application)
  {
    return resolvedApp(for: application, bundleIdentifier: config.bundleIdentifier)
  }

  if let data = try? Data(contentsOf: jsonPath),
    let config = try? JSONDecoder().decode(AppConfig.self, from: data),
    let application = Application(rawValue: config.application)
  {
    return resolvedApp(for: application, bundleIdentifier: config.bundleIdentifier)
  }

  return Ghostty()
}
