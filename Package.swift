// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacGamingLauncher",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "MacGamingLauncher",
            targets: ["MacGamingLauncher"]
        )
    ],
    targets: [
        .executableTarget(
            name: "MacGamingLauncher",
            path: "Sources/MacGamingLauncher"
        ),
        .testTarget(
            name: "MacGamingLauncherTests",
            dependencies: ["MacGamingLauncher"]
        ),
    ]
)
