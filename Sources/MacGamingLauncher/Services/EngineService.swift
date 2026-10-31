import Foundation

public final class EngineService: @unchecked Sendable {
    public static let shared = EngineService()

    private let fileManager = FileManager.default

    public init() {}

    /// Discovers Wine and GPTK engines on the system
    public func discoverEngines() -> [Engine] {
        var engines: [Engine] = []

        // 1. CrossOver in User Applications or /Applications
        let crossOverPaths = [
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications/CrossOver.app"),
            URL(fileURLWithPath: "/Applications/CrossOver.app")
        ]

        for appURL in crossOverPaths {
            let wineURL = appURL.appendingPathComponent("Contents/SharedSupport/CrossOver/bin/wine")
            let wineServerURL = appURL.appendingPathComponent("Contents/SharedSupport/CrossOver/bin/wineserver")

            if fileManager.fileExists(atPath: wineURL.path) {
                // Determine version from Info.plist
                let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
                var version = "26.x"
                if let data = try? Data(contentsOf: plistURL),
                   let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                   let ver = dict["CFBundleShortVersionString"] as? String {
                    version = ver
                }

                // Check for Apple GPTK D3DMetal inside CrossOver
                let gptkPath = appURL.appendingPathComponent("Contents/SharedSupport/CrossOver/lib64/apple_gptk/external/D3DMetal.framework")
                let hasD3DMetal = fileManager.fileExists(atPath: gptkPath.path)

                let engine = Engine(
                    name: "CrossOver \(version) (GPTK + MSync)",
                    type: .crossOver,
                    appBundleURL: appURL,
                    wineExecutableURL: wineURL,
                    wineServerExecutableURL: wineServerURL,
                    version: version,
                    hasD3DMetal: hasD3DMetal,
                    hasMSync: true
                )
                engines.append(engine)
                break
            }
        }

        // 2. Apple Game Porting Toolkit standalone / Homebrew
        let gptkPaths = [
            URL(fileURLWithPath: "/opt/game-porting-toolkit/bin/wine64"),
            URL(fileURLWithPath: "/usr/local/opt/game-porting-toolkit/bin/wine64")
        ]

        for wineURL in gptkPaths {
            if fileManager.fileExists(atPath: wineURL.path) {
                let serverURL = wineURL.deletingLastPathComponent().appendingPathComponent("wineserver")
                let engine = Engine(
                    name: "Apple Game Porting Toolkit (Evaluation)",
                    type: .appleGPTK,
                    appBundleURL: nil,
                    wineExecutableURL: wineURL,
                    wineServerExecutableURL: serverURL,
                    version: "GPTK 4 / Metal 4",
                    hasD3DMetal: true,
                    hasMSync: true
                )
                engines.append(engine)
                break
            }
        }

        return engines
    }
}
