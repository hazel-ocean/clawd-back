cask "clawd-back" do
  version "2.6.0"
  sha256 "9adc685294dad60c4e67ece348d897bcf57bc458c356666ae4e7bea706e5b95b"

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
