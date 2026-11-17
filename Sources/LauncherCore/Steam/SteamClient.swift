import Foundation

/// Installs and drives the Windows Steam client inside a bottle.
public struct SteamClient: Sendable {
    public static let installerURL = URL(string: "https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe")!

    public let wine: Wine
    public var bottle: Bottle { wine.bottle }
    public var library: SteamLibrary { SteamLibrary(bottle: wine.bottle) }

    public init(wine: Wine) { self.wine = wine }

    // MARK: - Install

    /// Downloads SteamSetup.exe and installs Steam silently (NSIS `/S`).
    public func install(session: URLSession = .shared) async throws {
        let paths = wine.paths
        try paths.createOwnedFolders()
        let installer = paths.downloadsFolder.appending(path: "SteamSetup.exe")
        if !FileManager.default.fileExists(atPath: installer.path) {
            Log.steam.info("Lade SteamSetup.exe")
            let (temporary, response) = try await session.download(from: Self.installerURL)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw LauncherError("Steam-Installer konnte nicht geladen werden.")
            }
            try? FileManager.default.removeItem(at: installer)
            try FileManager.default.moveItem(at: temporary, to: installer)
        }

        let windowsPath = library.windowsPath(forMacPath: installer)
        let result = try await wine.run(windowsPath, ["/S"], timeout: .seconds(900))
        await wine.waitForExit(timeout: .seconds(300))
        guard library.isSteamInstalled else {
            throw LauncherError("Steam wurde nicht installiert.", detail: Wine.tail(result.output))
        }
        Log.steam.info("Steam installiert in \(bottle.name, privacy: .public)")
    }

    // MARK: - Status

    /// Running `steam.exe` processes of this bottle.
    public func steamProcesses(_ processes: [RunningProcess]? = nil) -> [RunningProcess] {
        ProcessList.wineProcesses(inPrefix: bottle.url, from: processes).filter { $0.windowsImageName == "steam.exe" }
    }

    public var isRunning: Bool { !steamProcesses().isEmpty }

    // MARK: - Control

    /// Prepares DLLs/registry for Steam and its games. Run before starting Steam or a game.
    /// `dxmtGames` must list every game of the bottle (copies for unlisted games are removed); `nil` leaves them alone.
    public func prepare(gameExecutables: Set<String>, dxmtGames: [(installFolder: URL, executables: [URL])]?) async throws {
        guard wine.engine.kind == .managed else { return }
        let plan = GraphicsPlan(engine: wine.engine, bottle: bottle, paths: wine.paths)
        try plan.deployClientDLLs()
        if let dxmtGames { plan.syncDXMTGameFolders(games: dxmtGames) }
        try await wine.importRegistry(plan.registry(gameExecutables: gameExecutables))
    }

    /// Starts Steam unless running and waits until `steam.exe` is up (Steam may update and restart itself first).
    /// `visible` shows the main window (first start / login); otherwise Steam starts minimized to the tray.
    /// `command` (e.g. `-applaunch <id>`) is passed on this first start, where Steam queues it until login and
    /// self-update are done — sending it to a client that is still starting can lose it.
    /// Returns `true` if Steam was started (and received `command`), `false` if it was already running.
    @discardableResult
    public func ensureRunning(visible: Bool, command: [String] = [], timeout: Duration = .seconds(120)) async throws -> Bool {
        if isRunning { return false }
        guard let steamFolder = library.steamFolder() else {
            throw LauncherError("Steam ist in diesem Bottle nicht installiert.")
        }
        var args = visible ? [] : ["-silent"]
        args += bottle.settings.extraSteamArguments + command
        try await wine.start(unixPath: steamFolder.appending(path: "steam.exe"), args)
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            try await Task.sleep(for: .seconds(2))
            if isRunning { return true }
        }
        throw LauncherError("Steam reagiert nicht.", detail: "steam.exe ist nach \(timeout) nicht gestartet. Details im Log: \(wine.logFile.path)")
    }

    /// Passes a command to the running client (`-applaunch`, `steam://` URLs, `-shutdown`).
    public func send(_ args: [String]) async throws {
        guard let steamFolder = library.steamFolder() else {
            throw LauncherError("Steam ist in diesem Bottle nicht installiert.")
        }
        try await wine.start(unixPath: steamFolder.appending(path: "steam.exe"), args)
    }

    public func launch(appID: String, arguments: [String] = []) async throws {
        try await send(["-applaunch", appID] + arguments)
    }

    /// Opens Steam's install dialog for an app.
    public func install(appID: String) async throws {
        try await send(["steam://install/\(appID)"])
    }

    public func showMainWindow() async throws {
        try await send(["steam://open/main"])
    }

    /// Asks Steam to quit (it may finish a cloud sync first). After `timeout`, only the Steam client's own processes
    /// are terminated — never the whole bottle, which could hold a running game.
    public func shutdown(timeout: Duration = .seconds(60)) async {
        guard isRunning else { return }
        try? await send(["-shutdown"])
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline, isRunning {
            try? await Task.sleep(for: .seconds(1))
        }
        guard isRunning else { return }
        let client = ProcessList.wineProcesses(inPrefix: bottle.url).filter {
            $0.windowsImageName.map(GraphicsPlan.steamExecutables.contains) ?? false
        }
        await GameMonitor.terminate(client)
    }
}
