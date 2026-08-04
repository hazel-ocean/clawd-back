cask "clawd-back" do
  version "2.3.0"
  sha256 "faa88ee1db1f78751fc6114c7c7c7d5b92a3408f6a7892d17b20e433a4e198e4"

  url "https://github.com/hazel-ocean/clawd-back/releases/download/v#{version}/ClawdBack-#{version}-aarch64-darwin.zip"
  name "Clawd Back"
  desc "Notifies you when Claude Code needs you and claws you back to its terminal"
  homepage "https://github.com/hazel-ocean/clawd-back"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on arch: :arm64
  depends_on macos: ">= :ventura"

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
