// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "MacGamingLauncher",
    defaultLocalization: "de",
    platforms: [
        // macOS 27 is required for Game Porting Toolkit 4 / D3DMetal 4 (Metal 4).
        .macOS(.v27)
    ],
    products: [
        .executable(name: "MacGamingLauncher", targets: ["MacGamingLauncher"])
    ],
    targets: [
        // Platform logic: runtime install, bottles, Wine invocation, Steam integration.
        // No UI, no global singletons — everything takes its dependencies explicitly so it is testable.
        .target(
            name: "LauncherCore",
            swiftSettings: [
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
            ]
        ),
        // SwiftUI app. Main-actor by default, as UI code should be.
        .executableTarget(
            name: "MacGamingLauncher",
            dependencies: ["LauncherCore"],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
            ]
        ),
        .testTarget(
            name: "LauncherCoreTests",
            dependencies: ["LauncherCore"]
        ),
    ]
)
