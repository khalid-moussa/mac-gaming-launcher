import Foundation

/// Every location the launcher reads or writes. Injected everywhere so tests can point it at a temp directory.
public struct LauncherPaths: Sendable, Hashable {
    /// `~/Library/Application Support/MacGamingLauncher`
    public let root: URL
    /// `~/Library/Logs/MacGamingLauncher`
    public let logs: URL
    /// The user's home directory (used to find third-party installs such as CrossOver bottles).
    public let home: URL

    public init(root: URL, logs: URL, home: URL) {
        self.root = root
        self.logs = logs
        self.home = home
    }

    public static var standard: LauncherPaths {
        LauncherPaths(
            root: URL.applicationSupportDirectory.appending(path: "MacGamingLauncher", directoryHint: .isDirectory),
            logs: URL.libraryDirectory.appending(path: "Logs/MacGamingLauncher", directoryHint: .isDirectory),
            home: URL.homeDirectory
        )
    }

    /// Folder holding the managed runtime; contains `Libraries/`.
    public var runtimeFolder: URL { root.appending(path: "Runtime", directoryHint: .isDirectory) }
    /// `Runtime/Libraries` — the extracted runtime tarball.
    public var librariesFolder: URL { runtimeFolder.appending(path: "Libraries", directoryHint: .isDirectory) }
    /// The user-imported Apple GPTK payload (`lib/external`, `lib/wine`), kept outside the runtime so updates don't erase it.
    public var d3dMetalStore: URL { root.appending(path: "D3DMetal", directoryHint: .isDirectory) }
    public var bottlesFolder: URL { root.appending(path: "Bottles", directoryHint: .isDirectory) }
    public var downloadsFolder: URL { root.appending(path: "Downloads", directoryHint: .isDirectory) }
    public var playtimeFile: URL { root.appending(path: "playtime.json") }

    public var crossOverBottlesFolder: URL {
        home.appending(path: "Library/Application Support/CrossOver/Bottles", directoryHint: .isDirectory)
    }

    /// Creates the folders the launcher owns.
    public func createOwnedFolders(fileManager: FileManager = .default) throws {
        for folder in [root, logs, bottlesFolder, downloadsFolder] {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        }
    }
}
