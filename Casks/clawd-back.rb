cask "clawd-back" do
  version "2.4.3"
  sha256 "e086eb5c90d37f8ae23b171cd83711bfe8c47e0a37b1a6941ca1455b6e3da5b4"

  url "https://github.com/hazel-ocean/clawd-back/releases/download/v#{version}/ClawdBack-#{version}-aarch64-darwin.zip"
  name "Clawd Back"
  desc "Notifies you when Claude Code needs you and claws you back to its terminal"
  homepage "https://github.com/hazel-ocean/clawd-back"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on arch: :arm64
  depends_on macos: :ventura

  app "ClawdBack.app"

  # Ad-hoc signed, not notarized: clear the quarantine so Gatekeeper doesn't
  # block first launch.
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/ClawdBack.app"]
  end

  zap trash: [
    "~/.cache/clawd-back",
    "~/.config/clawd-back",
  ]
end
