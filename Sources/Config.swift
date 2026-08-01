import Foundation
import TOMLDecoder

struct AppConfig: Codable {
  let terminal: String
}

// The configured terminal from ~/.config/clawd-back/config.{toml,json}, or
// .ghostty when there's no valid config.
func loadConfiguredTerminal() -> Terminal {
  let configDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".config/clawd-back", isDirectory: true)

  let tomlPath = configDir.appendingPathComponent("config.toml")
  let jsonPath = configDir.appendingPathComponent("config.json")

  if let data = try? Data(contentsOf: tomlPath),
    let config = try? TOMLDecoder().decode(AppConfig.self, from: data),
    let terminal = Terminal(rawValue: config.terminal)
  {
    return terminal
  }

  if let data = try? Data(contentsOf: jsonPath),
    let config = try? JSONDecoder().decode(AppConfig.self, from: data),
    let terminal = Terminal(rawValue: config.terminal)
  {
    return terminal
  }

  return .ghostty
}
