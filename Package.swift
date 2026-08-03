// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "clawd-back",
  platforms: [.macOS(.v13)],
  dependencies: [
    .package(url: "https://github.com/dduan/TOMLDecoder.git", from: "0.2.0")
  ],
  targets: [
    .executableTarget(
      name: "clawd-back",
      dependencies: ["TOMLDecoder"],
      exclude: [
        "Ghostty/ghostty-front-target.applescript",
        "Ghostty/ghostty-focus.applescript",
        "Ghostty/ghostty-window-exists.applescript",
      ]
    ),
    .testTarget(
      name: "clawd-backTests",
      dependencies: ["clawd-back"]
    ),
  ]
)
