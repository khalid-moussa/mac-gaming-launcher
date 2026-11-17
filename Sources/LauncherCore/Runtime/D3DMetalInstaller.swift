import Foundation

/// Imports Apple's D3DMetal (Game Porting Toolkit 3/4) into the managed runtime.
///
/// Apple's GPTK is not redistributable, so the user provides it: the GPTK `.dmg` from developer.apple.com
/// (outer image or the nested "Evaluation environment" image), a mounted volume, a folder, or an installed
/// `Game Porting Toolkit.app`. All of them contain a `lib` payload root shaped like
///
///     lib/external/D3DMetal.framework
///     lib/external/libd3dshared.dylib
///     lib/wine/x86_64-windows/{d3d10,d3d11,d3d12,dxgi}.dll   (+ nvngx-on-metalfx.dll, nvapi64.dll in GPTK 3+)
///
/// Import copies the payload into a store outside the runtime (survives runtime updates). Deploying places the
/// forwarder DLLs into Wine's builtin directory and points the unix-side `.so` names at `libd3dshared.dylib`.
public struct D3DMetalInstaller: Sendable {
    static let forwarderDLLs = ["d3d10.dll", "d3d11.dll", "d3d12.dll", "dxgi.dll"]
    static let unixLibraries = ["d3d10.so", "d3d11.so", "d3d12.so", "dxgi.so"]
    static let unixLinkDestination = "../../external/libd3dshared.dylib"
    static let metalFXSource = "nvngx-on-metalfx.dll"
    static let metalFXName = "nvngx.dll"
    static let nvapiName = "nvapi64.dll"

    public let paths: LauncherPaths

    public init(paths: LauncherPaths) { self.paths = paths }

    var storeLib: URL { paths.d3dMetalStore.appending(path: "lib", directoryHint: .isDirectory) }
    var originals: URL { paths.d3dMetalStore.appending(path: "originals", directoryHint: .isDirectory) }
    var wineLib: URL { paths.librariesFolder.appending(path: "Wine/lib", directoryHint: .isDirectory) }
    var peDirectory: URL { wineLib.appending(path: "wine/x86_64-windows", directoryHint: .isDirectory) }
    var unixDirectory: URL { wineLib.appending(path: "wine/x86_64-unix", directoryHint: .isDirectory) }

    // MARK: - Status

    /// Version of the imported payload, if any.
    public func importedInfo() -> D3DMetalInfo? {
        Self.frameworkVersion(inExternal: storeLib.appending(path: "external")).map(D3DMetalInfo.init(version:))
    }

    /// Version of the payload deployed in the runtime, if any.
    public func deployedInfo(fileManager: FileManager = .default) -> D3DMetalInfo? {
        let link = unixDirectory.appending(path: "dxgi.so")
        guard (try? fileManager.destinationOfSymbolicLink(atPath: link.path)) == Self.unixLinkDestination,
              fileManager.fileExists(atPath: wineLib.appending(path: "external/libd3dshared.dylib").path)
        else { return nil }
        return Self.frameworkVersion(inExternal: wineLib.appending(path: "external")).map(D3DMetalInfo.init(version:))
    }

    /// Finds an installed Game Porting Toolkit app (e.g. from `brew install --cask gcenx/wine/game-porting-toolkit`).
    public func installedToolkitApps(fileManager: FileManager = .default) -> [URL] {
        ["/Applications/Game Porting Toolkit.app", paths.home.appending(path: "Applications/Game Porting Toolkit.app").path]
            .map { URL(filePath: $0) }
            .filter { Self.locatePayload(under: $0, fileManager: fileManager) != nil }
    }

    // MARK: - Import

    /// Imports from a `.dmg`, folder, volume or `.app`, then deploys into the runtime. Returns the imported version.
    @discardableResult
    public func importPayload(from source: URL) async throws -> D3DMetalInfo {
        var mounts: [URL] = []
        defer { for mount in mounts.reversed() { Self.detach(mount) } }

        let payload: URL
        if source.pathExtension.lowercased() == "dmg" {
            let outer = try await Self.attach(source)
            mounts.append(outer)
            if let found = Self.locatePayload(under: outer) {
                payload = found
            } else {
                // The outer GPTK image contains the evaluation environment as a nested image.
                var nestedPayload: URL?
                let contents = (try? FileManager.default.contentsOfDirectory(at: outer, includingPropertiesForKeys: nil)) ?? []
                for nested in contents where nested.pathExtension.lowercased() == "dmg" {
                    let inner = try await Self.attach(nested)
                    mounts.append(inner)
                    if let found = Self.locatePayload(under: inner) { nestedPayload = found; break }
                }
                guard let nestedPayload else { throw Self.notFound }
                payload = nestedPayload
            }
        } else {
            guard let found = Self.locatePayload(under: source) else { throw Self.notFound }
            payload = found
        }

        let info = try copyToStore(payload)
        try deploy()
        return info
    }

    static let notFound = LauncherError(
        "Kein Game-Porting-Toolkit-Inhalt gefunden.",
        detail: "Wähle die GPTK-.dmg von developer.apple.com, das darin enthaltene „Evaluation environment“-Image oder die „Game Porting Toolkit.app“."
    )

    func copyToStore(_ payload: URL) throws -> D3DMetalInfo {
        let fileManager = FileManager.default
        let missing = Self.missingFiles(in: payload, fileManager: fileManager)
        guard missing.isEmpty else {
            throw LauncherError("Das Game Porting Toolkit ist unvollständig.", detail: "Fehlt: " + missing.joined(separator: ", "))
        }
        guard let version = Self.frameworkVersion(inExternal: payload.appending(path: "external")) else {
            throw LauncherError("Die D3DMetal-Version konnte nicht gelesen werden.")
        }

        let staging = paths.root.appending(path: "D3DMetal.staging", directoryHint: .isDirectory)
        try? fileManager.removeItem(at: staging)
        let stagingLib = staging.appending(path: "lib", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: stagingLib.appending(path: "wine"), withIntermediateDirectories: true)
        try fileManager.copyItem(at: payload.appending(path: "external"), to: stagingLib.appending(path: "external"))
        try fileManager.copyItem(at: payload.appending(path: "wine/x86_64-windows"), to: stagingLib.appending(path: "wine/x86_64-windows"))

        // Keep originals backup (from a previous deploy) — only replace the payload itself.
        try fileManager.createDirectory(at: paths.d3dMetalStore, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: storeLib.path) { try fileManager.removeItem(at: storeLib) }
        try fileManager.moveItem(at: stagingLib, to: storeLib)
        try? fileManager.removeItem(at: staging)
        Log.runtime.info("D3DMetal \(version, privacy: .public) importiert")
        return D3DMetalInfo(version: version)
    }

    // MARK: - Deploy

    /// Re-deploys an imported payload, e.g. after a runtime update replaced the Wine tree. No-op without import.
    public func deployIfImported() throws {
        guard importedInfo() != nil, FileManager.default.fileExists(atPath: wineLib.path) else { return }
        try deploy()
    }

    /// Places the forwarders into Wine's builtin directory and links the unix side to `libd3dshared.dylib`.
    func deploy() throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: peDirectory.path) else {
            throw LauncherError("Die Runtime ist nicht installiert – D3DMetal kann nicht eingebunden werden.")
        }
        guard RuntimeInstaller(paths: paths).isGPTKCapable() else {
            throw LauncherError("Diese Runtime-Version unterstützt D3DMetal nicht.", detail: "Bitte die Runtime aktualisieren.")
        }
        try fileManager.createDirectory(at: originals, withIntermediateDirectories: true)
        let storePE = storeLib.appending(path: "wine/x86_64-windows")

        var dlls: [(source: String, target: String)] = Self.forwarderDLLs.map { ($0, $0) }
        if fileManager.fileExists(atPath: storePE.appending(path: Self.metalFXSource).path) {
            dlls.append((Self.metalFXSource, Self.metalFXName))
        }
        if fileManager.fileExists(atPath: storePE.appending(path: Self.nvapiName).path) {
            dlls.append((Self.nvapiName, Self.nvapiName))
        }

        for (source, target) in dlls {
            let destination = peDirectory.appending(path: target)
            let backup = originals.appending(path: target)
            if fileManager.fileExists(atPath: destination.path) {
                let isOurs = fileManager.contentsEqual(atPath: destination.path, andPath: storePE.appending(path: source).path)
                if !isOurs, !fileManager.fileExists(atPath: backup.path) {
                    try fileManager.moveItem(at: destination, to: backup)
                } else {
                    try fileManager.removeItem(at: destination)
                }
            }
            try fileManager.copyItem(at: storePE.appending(path: source), to: destination)
            let unixName = (target as NSString).deletingPathExtension + ".so"
            let link = unixDirectory.appending(path: unixName)
            if (try? fileManager.destinationOfSymbolicLink(atPath: link.path)) != nil || fileManager.fileExists(atPath: link.path) {
                let backupSO = originals.appending(path: unixName)
                if (try? fileManager.destinationOfSymbolicLink(atPath: link.path)) != Self.unixLinkDestination,
                   !fileManager.fileExists(atPath: backupSO.path) {
                    try? fileManager.moveItem(at: link, to: backupSO)
                } else {
                    try? fileManager.removeItem(at: link)
                }
            }
            try fileManager.createSymbolicLink(atPath: link.path, withDestinationPath: Self.unixLinkDestination)
        }

        let external = wineLib.appending(path: "external")
        if fileManager.fileExists(atPath: external.path) { try fileManager.removeItem(at: external) }
        try fileManager.copyItem(at: storeLib.appending(path: "external"), to: external)
        Log.runtime.info("D3DMetal in Runtime eingebunden")
    }

    /// Removes D3DMetal from the runtime and restores Wine's original DLLs.
    public func remove() throws {
        let fileManager = FileManager.default
        let names = Self.forwarderDLLs + [Self.metalFXName, Self.nvapiName]
        for name in names {
            let destination = peDirectory.appending(path: name)
            try? fileManager.removeItem(at: destination)
            let backup = originals.appending(path: name)
            if fileManager.fileExists(atPath: backup.path) { try fileManager.moveItem(at: backup, to: destination) }

            let unixName = (name as NSString).deletingPathExtension + ".so"
            let link = unixDirectory.appending(path: unixName)
            if (try? fileManager.destinationOfSymbolicLink(atPath: link.path)) == Self.unixLinkDestination {
                try? fileManager.removeItem(at: link)
            }
            let backupSO = originals.appending(path: unixName)
            if fileManager.fileExists(atPath: backupSO.path) || (try? fileManager.destinationOfSymbolicLink(atPath: backupSO.path)) != nil {
                try? fileManager.moveItem(at: backupSO, to: link)
            }
        }
        try? fileManager.removeItem(at: wineLib.appending(path: "external"))
        try? fileManager.removeItem(at: paths.d3dMetalStore)
    }

    // MARK: - Payload discovery

    static func locatePayload(under url: URL, fileManager: FileManager = .default) -> URL? {
        let candidates = [
            url,
            url.appending(path: "lib"),
            url.appending(path: "redist/lib"),
            url.appending(path: "Contents/Resources/wine/lib"),
        ]
        return candidates.first { candidate in
            fileManager.fileExists(atPath: candidate.appending(path: "external/libd3dshared.dylib").path)
                && fileManager.fileExists(atPath: candidate.appending(path: "wine/x86_64-windows/dxgi.dll").path)
        }
    }

    static func missingFiles(in payload: URL, fileManager: FileManager) -> [String] {
        var missing: [String] = []
        for name in forwarderDLLs where !fileManager.fileExists(atPath: payload.appending(path: "wine/x86_64-windows/\(name)").path) {
            missing.append("wine/x86_64-windows/\(name)")
        }
        for name in ["libd3dshared.dylib", "D3DMetal.framework"] where !fileManager.fileExists(atPath: payload.appending(path: "external/\(name)").path) {
            missing.append("external/\(name)")
        }
        return missing
    }

    static func frameworkVersion(inExternal external: URL) -> String? {
        let framework = external.appending(path: "D3DMetal.framework")
        for plist in ["Versions/A/Resources/Info.plist", "Resources/Info.plist", "Info.plist"] {
            if let data = try? Data(contentsOf: framework.appending(path: plist)),
               let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
               let version = (dict["CFBundleShortVersionString"] ?? dict["CFBundleVersion"]) as? String,
               !version.isEmpty {
                return version
            }
        }
        return nil
    }

    // MARK: - Disk images

    static func attach(_ image: URL) async throws -> URL {
        let result = try await ProcessRunner.run(
            URL(filePath: "/usr/bin/hdiutil"),
            arguments: ["attach", "-readonly", "-nobrowse", "-plist", image.path],
            timeout: .seconds(120)
        )
        // hdiutil prints the plist on stdout; strip anything before it.
        let plistText = result.output.range(of: "<?xml").map { String(result.output[$0.lowerBound...]) } ?? result.output
        guard result.succeeded,
              let plist = try? PropertyListSerialization.propertyList(from: Data(plistText.utf8), format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]],
              let mountPoint = entities.compactMap({ $0["mount-point"] as? String }).first
        else {
            throw LauncherError("Das Disk-Image konnte nicht geöffnet werden.", detail: image.lastPathComponent)
        }
        return URL(filePath: mountPoint)
    }

    static func detach(_ mountPoint: URL) {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/hdiutil")
        process.arguments = ["detach", "-quiet", mountPoint.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }
}
