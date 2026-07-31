#!/usr/bin/env bash
# Build a versioned, zipped app bundle for a release. Invoked by semantic-release
# with the computed version as $1.
set -euo pipefail

version="${1:?usage: build-release.sh <version>}"

/usr/libexec/PlistBuddy \
  -c "Set :CFBundleVersion $version" \
  -c "Set :CFBundleShortVersionString $version" \
  Resources/Info.plist

make bundle

mkdir -p dist
zip="dist/ClawdBack-${version}-aarch64-darwin.zip"
ditto -c -k --keepParent ClawdBack.app "$zip"

# Point the Homebrew cask at this release. Committed back by @semantic-release/git.
sha="$(shasum -a 256 "$zip" | awk '{ print $1 }')"
/usr/bin/sed -i '' \
  -e "s|^  version \".*\"|  version \"${version}\"|" \
  -e "s|^  sha256 \".*\"|  sha256 \"${sha}\"|" \
  Casks/clawd-back.rb
