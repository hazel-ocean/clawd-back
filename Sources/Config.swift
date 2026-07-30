import Foundation
import TOMLDecoder

struct AppConfig: Codable {
  let terminal: String
}

enum Terminal: String, CaseIterable {
  case ghostty = "ghostty"
  case wezterm = "wezterm"
  case iterm2 = "iterm2"
  case terminal = "terminal"
  case alacritty = "alacritty"
  case kitty = "kitty"

  var bundleIdentifier: String {
    switch self {
    case .ghostty: return "com.mitchellh.ghostty"
    case .wezterm: return "com.github.wez.wezterm"
    case .iterm2: return "com.googlecode.iterm2"
    case .terminal: return "com.apple.Terminal"
    case .alacritty: return "org.alacritty"
    case .kitty: return "net.kovidgoyal.kitty"
    }
  }
}

func loadConfig() -> AppConfig {
  let configDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".config/clawd-back", isDirectory: true)

  let tomlPath = configDir.appendingPathComponent("config.toml")
  let jsonPath = configDir.appendingPathComponent("config.json")

  // Try TOML first
  if let tomlData = try? Data(contentsOf: tomlPath),
    let config = try? TOMLDecoder().decode(AppConfig.self, from: tomlData)
  {
    if Terminal(rawValue: config.terminal) != nil {
      return config
    }
  }

  // Fall back to JSON
  if let jsonData = try? Data(contentsOf: jsonPath),
    let config = try? JSONDecoder().decode(AppConfig.self, from: jsonData)
  {
    if Terminal(rawValue: config.terminal) != nil {
      return config
    }
  }

  // Default fallback
  return AppConfig(terminal: "ghostty")
}
