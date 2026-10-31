import Foundation

public final class SteamService: @unchecked Sendable {
    public static let shared = SteamService()

    private let fileManager = FileManager.default

    public init() {}

    /// Known helper / tool app IDs that are not games
    private let ignoredAppIDs: Set<String> = [
        "228980", // Steamworks Common Redistributables
        "1070560", // Steam Linux Runtime
        "1391110", // Steam Linux Runtime - Soldier
        "1628350", // Steam Linux Runtime - Sniper
        "250820"  // SteamVR
    ]

    /// Scans a bottle for installed Steam games
    public func scanGames(in bottle: Bottle) -> [SteamGame] {
        guard bottle.hasSteamInstalled else { return [] }

        var games: [SteamGame] = []
        let steamAppsDir = bottle.steamAppsURL

        guard fileManager.fileExists(atPath: steamAppsDir.path) else {
            return []
        }

        // 1. Scan default steamapps folder
        games.append(contentsOf: scanDirectory(steamAppsDir, bottle: bottle))

        // 2. Scan additional library folders from libraryfolders.vdf if present
        let libraryVDF = steamAppsDir.appendingPathComponent("libraryfolders.vdf")
        if let vdfContent = try? String(contentsOf: libraryVDF, encoding: .utf8),
           let parsed = try? VDFParser.parse(string: vdfContent),
           let libraryfolders = parsed["libraryfolders"]?.dictionaryValue {

            for (_, folderData) in libraryfolders {
                guard let dict = folderData.dictionaryValue,
                      let winPath = dict["path"]?.stringValue else { continue }

                // Convert Windows path inside bottle to Mac path if needed
                let cleanWinPath = winPath.replacingOccurrences(of: "\\\\", with: "/").replacingOccurrences(of: "\\", with: "/")
                var localURL: URL?

                if cleanWinPath.lowercased().hasPrefix("c:/") {
                    let relative = String(cleanWinPath.dropFirst(3))
                    localURL = bottle.path.appendingPathComponent("drive_c").appendingPathComponent(relative)
                }

                if let localURL = localURL {
                    let extraSteamApps = localURL.appendingPathComponent("steamapps")
                    if extraSteamApps != steamAppsDir && fileManager.fileExists(atPath: extraSteamApps.path) {
                        games.append(contentsOf: scanDirectory(extraSteamApps, bottle: bottle))
                    }
                }
            }
        }

        // Deduplicate by appId
        var seenIDs = Set<String>()
        return games.filter { game in
            guard !seenIDs.contains(game.appId) else { return false }
            seenIDs.insert(game.appId)
            return true
        }
    }

    private func scanDirectory(_ directory: URL, bottle: Bottle) -> [SteamGame] {
        var games: [SteamGame] = []
        guard let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }

        for file in files where file.lastPathComponent.hasPrefix("appmanifest_") && file.pathExtension == "acf" {
            guard let content = try? String(contentsOf: file, encoding: .utf8),
                  let parsed = try? VDFParser.parse(string: content),
                  let appState = parsed["AppState"]?.dictionaryValue else {
                continue
            }

            guard let appId = appState["appid"]?.stringValue, !ignoredAppIDs.contains(appId) else {
                continue
            }

            let name = appState["name"]?.stringValue ?? "Unbekanntes Spiel (\(appId))"
            let installDir = appState["installdir"]?.stringValue ?? ""
            let sizeOnDisk = UInt64(appState["SizeOnDisk"]?.stringValue ?? "0") ?? 0

            var lastPlayedDate: Date? = nil
            if let lastPlayedStr = appState["LastPlayed"]?.stringValue,
               let timestamp = Double(lastPlayedStr), timestamp > 0 {
                lastPlayedDate = Date(timeIntervalSince1970: timestamp)
            }

            let game = SteamGame(
                appId: appId,
                name: name,
                installDir: installDir,
                sizeOnDisk: sizeOnDisk,
                lastPlayed: lastPlayedDate,
                bottleName: bottle.name,
                bottlePath: bottle.path
            )

            games.append(game)
        }

        return games
    }
}
