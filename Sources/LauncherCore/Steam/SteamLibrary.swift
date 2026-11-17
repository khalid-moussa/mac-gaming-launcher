import Foundation

/// Reads the Windows Steam installation inside a bottle: install path, library folders, games, accounts.
public struct SteamLibrary: Sendable {
    public let bottle: Bottle

    public init(bottle: Bottle) { self.bottle = bottle }

    /// Tool / runtime app IDs that aren't games.
    static let ignoredAppIDs: Set<String> = [
        "228980", // Steamworks Common Redistributables
        "250820", // SteamVR
        "1007",   // Steam client
        "7",      // Steam client
    ]

    /// Windows path of steam.exe (default install location of the 64-bit client is still `Program Files (x86)`).
    public static let defaultWindowsSteamExe = #"C:\Program Files (x86)\Steam\steam.exe"#

    /// The Steam install folder (macOS path), if Steam is installed in this bottle.
    public func steamFolder(fileManager: FileManager = .default) -> URL? {
        let candidates = ["Program Files (x86)/Steam", "Program Files/Steam"].map { bottle.driveC.appending(path: $0, directoryHint: .isDirectory) }
        return candidates.first { fileManager.fileExists(atPath: $0.appending(path: "steam.exe").path) }
    }

    public var isSteamInstalled: Bool { steamFolder() != nil }

    /// Windows path of steam.exe for launching.
    public func steamExeWindowsPath(fileManager: FileManager = .default) -> String {
        guard let folder = steamFolder(fileManager: fileManager) else { return Self.defaultWindowsSteamExe }
        let relative = folder.path.dropFirst(bottle.driveC.path.count).replacingOccurrences(of: "/", with: "\\")
        let trimmed = relative.hasPrefix("\\") ? String(relative) : "\\" + relative
        return "C:" + trimmed + "\\steam.exe"
    }

    // MARK: - Games

    /// All `steamapps` folders: the default one plus extra libraries from `libraryfolders.vdf`.
    public func libraryFolders(fileManager: FileManager = .default) -> [URL] {
        guard let steam = steamFolder(fileManager: fileManager) else { return [] }
        let primary = steam.appending(path: "steamapps", directoryHint: .isDirectory)
        var result = [primary]
        let vdfCandidates = [steam.appending(path: "config/libraryfolders.vdf"), primary.appending(path: "libraryfolders.vdf")]
        guard let vdfURL = vdfCandidates.first(where: { fileManager.fileExists(atPath: $0.path) }),
              let root = try? VDF.parse(contentsOf: vdfURL),
              let folders = root["libraryfolders"]?.object
        else { return result }

        for entry in folders.entries {
            guard let windowsPath = entry.node["path"]?.string,
                  let macPath = macPath(forWindowsPath: windowsPath, fileManager: fileManager)
            else { continue }
            let steamapps = macPath.appending(path: "steamapps", directoryHint: .isDirectory)
            let standardized = steamapps.resolvingSymlinksInPath().standardizedFileURL
            guard fileManager.fileExists(atPath: standardized.path),
                  !result.contains(where: { $0.resolvingSymlinksInPath().standardizedFileURL == standardized })
            else { continue }
            result.append(steamapps)
        }
        return result
    }

    /// Maps `D:\Games` to the macOS path using the prefix's `dosdevices` links (falls back to `drive_x`).
    public func macPath(forWindowsPath windowsPath: String, fileManager: FileManager = .default) -> URL? {
        let normalized = windowsPath.replacingOccurrences(of: "\\", with: "/")
        let characters = Array(normalized)
        guard characters.count >= 2, characters[0].isLetter, characters[1] == ":" else { return nil }
        let drive = String(characters[0]).lowercased()
        let remainder = String(characters.dropFirst(2)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let components = remainder.split(separator: "/").map(String.init)
        guard !components.contains("..") else { return nil }

        let dosDevice = bottle.url.appending(path: "dosdevices/\(drive):", directoryHint: .isDirectory)
        let base: URL
        if let target = try? fileManager.destinationOfSymbolicLink(atPath: dosDevice.path) {
            base = target.hasPrefix("/") ? URL(filePath: target, directoryHint: .isDirectory)
                : dosDevice.deletingLastPathComponent().appending(path: target, directoryHint: .isDirectory)
        } else if fileManager.fileExists(atPath: bottle.url.appending(path: "drive_\(drive)").path) {
            base = bottle.url.appending(path: "drive_\(drive)", directoryHint: .isDirectory)
        } else {
            return nil
        }
        return components.reduce(base) { $0.appending(path: $1, directoryHint: .isDirectory) }.standardizedFileURL
    }

    /// Every Windows spelling of a macOS folder in this prefix, lower-cased with a trailing backslash
    /// (`c:\program files (x86)\steam\steamapps\common\game\`, `z:\users\…\`, `d:\…\` for mapped drives).
    public func windowsPathPrefixes(forMacFolder folder: URL, fileManager: FileManager = .default) -> Set<String> {
        func normalized(_ path: String) -> String {
            var result = path.replacingOccurrences(of: "/", with: "\\").lowercased()
            if !result.hasSuffix("\\") { result += "\\" }
            return result
        }
        let folderPaths = Set([folder.standardizedFileURL.path, folder.resolvingSymlinksInPath().path])
        var result = Set(folderPaths.map { normalized("z:" + $0) })
        result.insert(normalized(windowsPath(forMacPath: folder)))
        let dosdevices = bottle.url.appending(path: "dosdevices", directoryHint: .isDirectory)
        for entry in (try? fileManager.contentsOfDirectory(atPath: dosdevices.path)) ?? [] where entry.count == 2 && entry.hasSuffix(":") {
            guard let target = try? fileManager.destinationOfSymbolicLink(atPath: dosdevices.appending(path: entry).path) else { continue }
            let base = (target.hasPrefix("/") ? URL(filePath: target) : dosdevices.appending(path: target)).resolvingSymlinksInPath().path
            for path in folderPaths {
                let resolvedBase = base == "/" ? "" : base
                guard path == resolvedBase || path.hasPrefix(resolvedBase + "/") else { continue }
                result.insert(normalized(entry + String(path.dropFirst(resolvedBase.count))))
            }
        }
        return result
    }

    /// Converts a macOS path inside the prefix's drives back to a Windows path (`Z:` maps `/`).
    public func windowsPath(forMacPath url: URL) -> String {
        let path = url.standardizedFileURL.path
        let driveCPath = bottle.driveC.standardizedFileURL.path
        if path.hasPrefix(driveCPath) {
            return "C:" + path.dropFirst(driveCPath.count).replacingOccurrences(of: "/", with: "\\")
        }
        return "Z:" + path.replacingOccurrences(of: "/", with: "\\")
    }

    /// Installed and installing games across all library folders, sorted by name.
    public func games(fileManager: FileManager = .default) -> [SteamGame] {
        var seen = Set<String>()
        var games: [SteamGame] = []
        for folder in libraryFolders(fileManager: fileManager) {
            for game in Self.scanManifests(in: folder, bottleID: bottle.id, fileManager: fileManager) where seen.insert(game.appID).inserted {
                games.append(game)
            }
        }
        return games.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func scanManifests(in steamapps: URL, bottleID: String, fileManager: FileManager) -> [SteamGame] {
        let files = (try? fileManager.contentsOfDirectory(at: steamapps, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.lastPathComponent.hasPrefix("appmanifest_") && $0.pathExtension == "acf" }
            .compactMap { file in
                guard let root = try? VDF.parse(contentsOf: file) else {
                    Log.steam.warning("Manifest unlesbar: \(file.lastPathComponent, privacy: .public)")
                    return nil
                }
                return game(fromManifest: root, libraryFolder: steamapps, bottleID: bottleID)
            }
    }

    static func game(fromManifest root: VDFObject, libraryFolder: URL, bottleID: String) -> SteamGame? {
        guard let state = root["AppState"], let appID = state["appid"]?.string, !ignoredAppIDs.contains(appID) else { return nil }
        let name = state["name"]?.string ?? "App \(appID)"
        // Skip redistributable / tool packages that occasionally get their own manifest.
        if name.localizedCaseInsensitiveContains("redistributable") { return nil }
        // The install dir must be one folder name inside steamapps/common: empty or `..` would make the whole
        // library (or more) count as this game's folder.
        guard let installDir = state["installdir"]?.string, !installDir.isEmpty, installDir != ".", installDir != "..",
              !installDir.contains("/"), !installDir.contains("\\") else { return nil }
        let lastPlayed = state["LastPlayed"]?.string.flatMap(TimeInterval.init).flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0) : nil }
        return SteamGame(
            appID: appID,
            name: name,
            installDir: installDir,
            sizeOnDisk: state["SizeOnDisk"]?.string.flatMap(UInt64.init) ?? 0,
            lastPlayed: lastPlayed,
            stateFlags: state["StateFlags"]?.string.flatMap(Int.init) ?? 0,
            libraryFolder: libraryFolder,
            bottleID: bottleID
        )
    }

    // MARK: - Accounts

    /// Accounts that have logged in to Steam in this bottle (`config/loginusers.vdf`). Most recent first.
    public func accounts(fileManager: FileManager = .default) -> [SteamAccount] {
        guard let steam = steamFolder(fileManager: fileManager),
              let root = try? VDF.parse(contentsOf: steam.appending(path: "config/loginusers.vdf"))
        else { return [] }
        return Self.accounts(from: root)
    }

    static func accounts(from root: VDFObject) -> [SteamAccount] {
        guard let users = root["users"]?.object else { return [] }
        return users.entries.compactMap { entry -> SteamAccount? in
            guard entry.key.allSatisfy(\.isNumber) else { return nil }
            let timestamp = entry.node["Timestamp"]?.string.flatMap(TimeInterval.init)
            return SteamAccount(
                steamID64: entry.key,
                accountName: entry.node["AccountName"]?.string ?? "",
                personaName: entry.node["PersonaName"]?.string ?? entry.node["AccountName"]?.string ?? "Steam-Nutzer",
                mostRecent: entry.node["MostRecent"]?.string == "1",
                lastLogin: timestamp.map(Date.init(timeIntervalSince1970:))
            )
        }
        .sorted { lhs, rhs in
            if lhs.mostRecent != rhs.mostRecent { return lhs.mostRecent }
            return (lhs.lastLogin ?? .distantPast) > (rhs.lastLogin ?? .distantPast)
        }
    }

    // MARK: - Executables

    /// Lower-cased `.exe` names inside a game's install folder, used as a fallback to recognize the running game
    /// (the primary match is the install path). The walk is depth-limited, so huge asset folders can't exhaust it
    /// before the executables are found.
    public static func executableNames(in folder: URL, limit: Int = 400, maxDepth: Int = 5, fileManager: FileManager = .default) -> Set<String> {
        guard let enumerator = fileManager.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        let ignored: Set<String> = ["unitycrashhandler64.exe", "unitycrashhandler32.exe", "crashreportclient.exe", "vc_redist.x64.exe", "vc_redist.x86.exe", "dxsetup.exe", "uninstall.exe", "unins000.exe", "crashpad_handler.exe"]
        var names = Set<String>()
        var visited = 0
        for case let url as URL in enumerator {
            visited += 1
            if visited > 300_000 || names.count >= limit { break }
            if enumerator.level >= maxDepth { enumerator.skipDescendants() }
            // Don't descend into redistributable folders.
            let lowerName = url.lastPathComponent.lowercased()
            if ["_commonredist", "redist", "redistributables", "directx", "__installer"].contains(lowerName) {
                enumerator.skipDescendants()
                continue
            }
            if url.pathExtension.lowercased() == "exe", !ignored.contains(lowerName) {
                names.insert(lowerName)
            }
        }
        return names
    }
}
