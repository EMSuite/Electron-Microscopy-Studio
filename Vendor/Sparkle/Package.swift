// swift-tools-version: 6.2
// The website download's updater (#761): Sparkle at the tag tools/lib/sparkle-pin.sh names, built by tools/build-sparkle.sh with
// SPARKLE_NORMALIZE_INSTALLED_APPLICATION_NAME=1, so an update renames macEM.app to the app's current name. The Xcode project links
// this package's product in place of sparkle-project/Sparkle's own, which ships the same framework built with the flag off.
// README.md beside this file says how to rebuild it and how to go back to the stock package.
import PackageDescription

let package = Package(
    name: "Sparkle",
    platforms: [.macOS(.v12)],
    products: [
        .library(name: "Sparkle", targets: ["Sparkle"]),
    ],
    targets: [
        .binaryTarget(name: "Sparkle", path: "Sparkle.xcframework"),
    ]
)
