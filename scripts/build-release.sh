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
ditto -c -k --keepParent ClaudeZellijWhip.app \
  "dist/ClaudeZellijWhip-${version}-aarch64-darwin.zip"
