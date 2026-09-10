import Foundation
import TOMLDecoder

// Every field is optional: a config that sets one thing must not have to
// restate the others. A required field here fails the whole decode, which
// reverts every setting to its default and looks like the file was ignored.
struct AppConfig: Codable {
  let application: String?
  // Required when application == "generic": the bundle id of the app to
  // claw back to, since .generic has no fixed identity of its own.
  let bundleIdentifier: String?
  // Lifts the WindowServer gate's macOS ceiling only. The floor and the Apple
  // Silicon requirement stand.
  let forceWindowServerRaiseEnabled: Bool?
  // Notification sound, by name, from the app bundle or any Library/Sounds
  // directory. Case sensitive, and the extension is optional for the system set.
  let sound: String?
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

  if let data = try? Data(contentsOf: configDir.appendingPathComponent("config.toml")) {
    if let config = try? TOMLDecoder().decode(AppConfig.self, from: data) { return config }
    counter(.configUndecodable)
  }
  if let data = try? Data(contentsOf: configDir.appendingPathComponent("config.json")) {
    if let config = try? JSONDecoder().decode(AppConfig.self, from: data) { return config }
    counter(.configUndecodable)
  }
  return nil
}

func loadConfiguredApp() -> any AppActivation {
  guard let config = loadConfig(), let name = config.application else { return Ghostty() }
  guard let application = Application(rawValue: name) else {
    counter(.configApplicationUnknown)
    return Ghostty()
  }
  return resolvedApp(for: application, bundleIdentifier: config.bundleIdentifier)
}
