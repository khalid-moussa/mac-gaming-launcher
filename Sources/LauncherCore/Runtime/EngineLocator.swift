import Foundation

/// Finds usable Wine engines: the managed runtime and (optionally) CrossOver.
public struct EngineLocator: Sendable {
    public let paths: LauncherPaths

    public init(paths: LauncherPaths) { self.paths = paths }

    public func discover(fileManager: FileManager = .default) -> [Engine] {
        [managedEngine(fileManager: fileManager), crossOverEngine(fileManager: fileManager)].compactMap { $0 }
    }

    /// The runtime downloaded by the launcher, if installed.
    public func managedEngine(fileManager: FileManager = .default) -> Engine? {
        let installer = RuntimeInstaller(paths: paths)
        guard let version = installer.installedVersion(fileManager: fileManager) else { return nil }
        let libraries = paths.librariesFolder
        let bin = libraries.appending(path: "Wine/bin")
        // The runtime ships `wine64` and `wine` (both point at the same WoW64 loader).
        let wine = ["wine64", "wine"].map { bin.appending(path: $0) }.first { fileManager.isExecutableFile(atPath: $0.path) }
        guard let wine else { return nil }
        let dxvk = libraries.appending(path: "DXVK")
        let dxmt = libraries.appending(path: "DXMT")
        return Engine(
            kind: .managed,
            version: version,
            wineBinary: wine,
            wineserverBinary: bin.appending(path: "wineserver"),
            dxvkFolder: fileManager.fileExists(atPath: dxvk.appending(path: "x64").path) ? dxvk : nil,
            dxmtFolder: fileManager.fileExists(atPath: dxmt.appending(path: "x64").path) ? dxmt : nil,
            d3dMetal: D3DMetalInstaller(paths: paths).deployedInfo(fileManager: fileManager),
            supportsMSync: installer.isGPTKCapable()
        )
    }

    /// CodeWeavers CrossOver, if installed in `/Applications` or `~/Applications`.
    public func crossOverEngine(fileManager: FileManager = .default) -> Engine? {
        let candidates = [URL(filePath: "/Applications/CrossOver.app"), paths.home.appending(path: "Applications/CrossOver.app")]
        for app in candidates {
            let bin = app.appending(path: "Contents/SharedSupport/CrossOver/bin")
            let wine = bin.appending(path: "wine")
            guard fileManager.isExecutableFile(atPath: wine.path) else { continue }
            let info = NSDictionary(contentsOf: app.appending(path: "Contents/Info.plist"))
            let version = info?["CFBundleShortVersionString"] as? String ?? "?"
            let external = app.appending(path: "Contents/SharedSupport/CrossOver/lib64/apple_gptk/external")
            let d3dMetal = D3DMetalInstaller.frameworkVersion(inExternal: external).map(D3DMetalInfo.init(version:))
            return Engine(
                kind: .crossOver,
                version: version,
                wineBinary: wine,
                wineserverBinary: bin.appending(path: "wineserver"),
                d3dMetal: d3dMetal,
                supportsMSync: true,
                appBundle: app
            )
        }
        return nil
    }
}

/// Rosetta 2 is required: the Wine runtime is x86_64.
public enum Rosetta {
    public static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: "/Library/Apple/usr/libexec/oah/libRosettaRuntime")
    }

    /// Shell command that installs Rosetta (needs administrator rights).
    public static let installCommand = "/usr/sbin/softwareupdate --install-rosetta --agree-to-license"
}
