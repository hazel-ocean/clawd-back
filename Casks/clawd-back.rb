cask "clawd-back" do
  version "2.4.0"
  sha256 "bd1d1bfa2c3b112db02a084e2638ae0878fca7cf5c2856dd9281026cf15f9095"

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
