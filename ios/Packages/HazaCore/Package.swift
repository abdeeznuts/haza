// swift-tools-version: 5.9
// HazaCore — platform-independent logic shared by the iOS app, the Watch app and the widgets.
// It has no Apple-UI dependencies so its tests run on Linux (see docs/05-architecture.md).
import PackageDescription

let package = Package(
    name: "HazaCore",
    platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v14)],
    products: [
        .library(name: "HazaCore", targets: ["HazaCore"]),
    ],
    targets: [
        .target(name: "HazaCore"),
        .testTarget(name: "HazaCoreTests", dependencies: ["HazaCore"]),
    ]
)
