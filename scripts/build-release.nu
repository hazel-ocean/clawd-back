#!/usr/bin/env nu
# Build a versioned, zipped app bundle for a release. Invoked by semantic-release
# with the computed version as the first argument.
def main [version: string] {
  # The single source of truth for the version: `just bundle` and the nix
  # derivation both stamp the bundle from it. Committed back by
  # @semantic-release/git, so a checkout knows what it is.
  $"($version)\n" | save -f VERSION

  ^just bundle

  mkdir dist
  let zip = $"dist/ClawdBack-($version)-aarch64-darwin.zip"
  ^ditto -c -k --keepParent ClawdBack.app $zip

  # Point the Homebrew cask at this release. Committed back by @semantic-release/git.
  let sha = (^shasum -a 256 $zip | split row -r '\s+' | first)
  let cask = "Casks/clawd-back.rb"
  open --raw $cask
    | str replace -r '(?m)^  version ".*"' $'  version "($version)"'
    | str replace -r '(?m)^  sha256 ".*"' $'  sha256 "($sha)"'
    | save -f $cask
}
