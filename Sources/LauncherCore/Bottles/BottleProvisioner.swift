import Foundation

/// Creates and prepares launcher-owned Wine prefixes.
public struct BottleProvisioner: Sendable {
    public let engine: Engine
    public let paths: LauncherPaths

    public init(engine: Engine, paths: LauncherPaths) {
        precondition(engine.kind == .managed)
        self.engine = engine
        self.paths = paths
    }

    /// Creates a 64-bit (WoW64) Windows 10 prefix. Takes 30–90 s on first run under Rosetta.
    public func createBottle(named name: String, settings: BottleSettings = BottleSettings()) async throws -> Bottle {
        let store = BottleStore(paths: paths)
        try paths.createOwnedFolders()
        let url = store.newBottleURL(named: name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let marker = url.appending(path: BottleStore.creatingMarker)
        FileManager.default.createFile(atPath: marker.path, contents: nil)
        let bottle = Bottle(name: url.lastPathComponent, url: url, owner: .launcher, settings: settings)
        try store.save(bottle)

        do {
            try await initialize(bottle)
        } catch {
            await Wine(engine: engine, bottle: bottle, paths: paths).killAll()
            try? FileManager.default.removeItem(at: url)
            throw error
        }
        try? FileManager.default.removeItem(at: marker)
        return bottle
    }

    /// Boots the prefix (`winecfg -v` creates it and sets the Windows version), then applies base tweaks.
    public func initialize(_ bottle: Bottle) async throws {
        let wine = Wine(engine: engine, bottle: bottle, paths: paths)
        Log.bottles.info("Erstelle Prefix \(bottle.url.path, privacy: .public)")
        let result = try await wine.run("winecfg", ["-v", bottle.settings.windowsVersion], timeout: .seconds(600))
        await wine.waitForExit(timeout: .seconds(120))
        guard bottle.isInitialized() else {
            throw LauncherError("Das Bottle konnte nicht erstellt werden.", detail: Wine.tail(result.output))
        }
        installFonts(into: bottle)
        linkUserProfile(in: bottle)
    }

    /// Steam and many games expect Arial/Tahoma; macOS ships them.
    func installFonts(into bottle: Bottle, fileManager: FileManager = .default) {
        let fonts = bottle.driveC.appending(path: "windows/Fonts", directoryHint: .isDirectory)
        try? fileManager.createDirectory(at: fonts, withIntermediateDirectories: true)
        let sources = ["/Library/Fonts", "/System/Library/Fonts/Supplemental"].map { URL(filePath: $0, directoryHint: .isDirectory) }
        for font in ["Arial.ttf", "Arial Bold.ttf", "Arial Unicode.ttf", "Tahoma.ttf", "Tahoma Bold.ttf", "Verdana.ttf"] {
            let target = fonts.appending(path: font)
            guard !fileManager.fileExists(atPath: target.path),
                  let source = sources.map({ $0.appending(path: font) }).first(where: { fileManager.fileExists(atPath: $0.path) })
            else { continue }
            try? fileManager.copyItem(at: source, to: target)
        }
    }

    /// The runtime names the Windows user `crossover`; link it with the macOS user name so either resolves to the
    /// same profile (otherwise apps can boot into an empty profile).
    func linkUserProfile(in bottle: Bottle, fileManager: FileManager = .default) {
        let users = bottle.driveC.appending(path: "users", directoryHint: .isDirectory)
        let macUser = NSUserName()
        let crossover = users.appending(path: "crossover")
        let mine = users.appending(path: macUser)
        let crossoverExists = fileManager.fileExists(atPath: crossover.path)
        let mineExists = fileManager.fileExists(atPath: mine.path)
        if crossoverExists, !mineExists {
            try? fileManager.createSymbolicLink(atPath: mine.path, withDestinationPath: "crossover")
        } else if mineExists, !crossoverExists, macUser != "crossover" {
            try? fileManager.createSymbolicLink(atPath: crossover.path, withDestinationPath: macUser)
        }
    }
}
