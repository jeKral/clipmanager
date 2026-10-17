// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClipManager",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "ClipManagerCore",
            path: "Sources/ClipManagerCore"
        ),
        .executableTarget(
            name: "ClipManager",
            dependencies: ["ClipManagerCore"],
            path: "Sources/ClipManager",
            exclude: [
                "Resources/Info.plist",
                "Resources/ClipManager.entitlements",
            ]
        ),
        .testTarget(
            name: "ClipManagerCoreTests",
            dependencies: ["ClipManagerCore"],
            path: "Tests/ClipManagerCoreTests"
        ),
    ]
)
