import Foundation

/// The native macOS Steam client (`/Applications/Steam.app`, data in `~/Library/Application Support/Steam`).
///
/// Its library contains native macOS games — and, with Steam Play enabled by tools such as NotProton, Windows games
/// that the Mac client runs through CrossOver. The launcher only reads the library and asks the client to launch
/// games (`steam://rungameid/<id>`); it never modifies the Mac client.
public struct MacSteamLibrary: Sendable {
    /// Pseudo bottle ID used for games of the native client.
    public static let sourceID = "macos-steam"

    public let home: URL

    public init(home: URL) { self.home = home }

    public var dataFolder: URL { home.appending(path: "Library/Application Support/Steam", directoryHint: .isDirectory) }

    public var appBundle: URL? {
        [URL(filePath: "/Applications/Steam.app"), home.appending(path: "Applications/Steam.app")]
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    public var isInstalled: Bool { appBundle != nil && FileManager.default.fileExists(atPath: dataFolder.path) }

    /// Whether NotProton (Steam Play for macOS) is set up.
    public var hasNotProton: Bool {
        FileManager.default.fileExists(atPath: home.appending(path: "Library/Application Support/notproton").path)
    }

    public func libraryFolders(fileManager: FileManager = .default) -> [URL] {
        let primary = dataFolder.appending(path: "steamapps", directoryHint: .isDirectory)
        var result = fileManager.fileExists(atPath: primary.path) ? [primary] : []
        let vdf = [dataFolder.appending(path: "config/libraryfolders.vdf"), primary.appending(path: "libraryfolders.vdf")]
            .first { fileManager.fileExists(atPath: $0.path) }
        guard let vdf, let root = try? VDF.parse(contentsOf: vdf), let folders = root["libraryfolders"]?.object else { return result }
        for entry in folders.entries {
            guard let path = entry.node["path"]?.string, path.hasPrefix("/") else { continue }
            let steamapps = URL(filePath: path, directoryHint: .isDirectory).appending(path: "steamapps", directoryHint: .isDirectory)
            let standardized = steamapps.resolvingSymlinksInPath().standardizedFileURL
            if fileManager.fileExists(atPath: standardized.path),
               !result.contains(where: { $0.resolvingSymlinksInPath().standardizedFileURL == standardized }) {
                result.append(steamapps)
            }
        }
        return result
    }

    public func games(fileManager: FileManager = .default) -> [SteamGame] {
        var seen = Set<String>()
        return libraryFolders(fileManager: fileManager)
            .flatMap { SteamLibrary.scanManifests(in: $0, bottleID: Self.sourceID, fileManager: fileManager) }
            .filter { seen.insert($0.appID).inserted }
    }

    public func accounts() -> [SteamAccount] {
        guard let root = try? VDF.parse(contentsOf: dataFolder.appending(path: "config/loginusers.vdf")) else { return [] }
        return SteamLibrary.accounts(from: root)
    }

    public static func launchURL(appID: String) -> URL { URL(string: "steam://rungameid/\(appID)")! }

    /// Running processes of a native/Steam-Play game: macOS executables inside the install folder (by their real
    /// executable path — argv[0] may be relative), or Wine processes (Steam Play) whose image lies in the install
    /// folder (`Z:` path) or carries one of the game's executable names.
    public static func runningProcesses(of game: SteamGame, executableNames: Set<String>, snapshot: [RunningProcess]) -> [RunningProcess] {
        let folders = Set([game.installFolder.standardizedFileURL.path, game.installFolder.resolvingSymlinksInPath().path])
        let windowsFolders = folders.map { ("z:" + $0).replacingOccurrences(of: "/", with: "\\").lowercased() + "\\" }
        return snapshot.filter { process in
            if let image = process.windowsImageName {
                let path = process.normalizedWindowsPath
                return windowsFolders.contains { path.hasPrefix($0) } || executableNames.contains(image)
            }
            if folders.contains(where: { process.commandName.hasPrefix($0 + "/") }) { return true }
            guard let path = executablePath(of: process.pid) else { return false }
            return folders.contains { path.hasPrefix($0 + "/") }
        }
    }

    /// Absolute, symlink-resolved executable path of a process.
    static func executablePath(of pid: pid_t) -> String? {
        var buffer = [UInt8](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return URL(filePath: String(decoding: buffer.prefix(Int(length)), as: UTF8.self)).resolvingSymlinksInPath().path
    }
}
