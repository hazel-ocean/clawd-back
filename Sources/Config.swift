import Foundation

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
  let jsonPath = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".config/claude-zellij-whip/config.json")

  if let data = try? Data(contentsOf: jsonPath),
    let config = try? JSONDecoder().decode(AppConfig.self, from: data),
    Terminal(rawValue: config.terminal) != nil
  {
    return config
  }

  return AppConfig(terminal: "ghostty")
}
