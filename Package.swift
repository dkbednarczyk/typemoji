// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "typemoji",
  platforms: [.macOS(.v14)],
  targets: [
    .target(name: "TypemojiCore"),
    .executableTarget(name: "typemoji", dependencies: ["TypemojiCore"]),
    .testTarget(name: "TypemojiCoreTests", dependencies: ["TypemojiCore"]),
  ]
)
