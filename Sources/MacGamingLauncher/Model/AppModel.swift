import AppKit
import LauncherCore
import Observation
import SwiftUI

enum LibraryFilter: String, CaseIterable, Identifiable, Hashable {
    case all, installed, recent
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "Alle Spiele"
        case .installed: "Spielbereit"
        case .recent: "Zuletzt gespielt"
        }
    }
    var icon: String {
        switch self {
        case .all: "square.grid.2x2"
        case .installed: "checkmark.circle"
        case .recent: "clock"
        }
    }
}

enum SidebarItem: Hashable {
    case library(LibraryFilter)
    case bottle(Bottle.ID)
}

enum SessionState: Equatable {
    case preparing(String)
    case running(since: Date)
}

/// A long-running operation shown in the UI.
struct Activity: Equatable {
    var title: String
    var detail: String?
    var progress: Double?
}

/// Setup progress for the onboarding assistant.
enum SetupStep: Int, CaseIterable, Identifiable {
    case rosetta, runtime, bottle, steam, login
    var id: Int { rawValue }
}

@Observable
final class AppModel {
    let paths: LauncherPaths
    let playtime: PlaytimeStore

    private(set) var engines: [Engine] = []
    private(set) var bottles: [Bottle] = []
    private(set) var games: [SteamGame] = []
    private(set) var accounts: [Bottle.ID: SteamAccount] = [:]
    private(set) var steamInstalled: Set<Bottle.ID> = []
    private(set) var steamRunning: Set<Bottle.ID> = []
    private(set) var sessions: [SteamGame.ID: SessionState] = [:]
    private(set) var hasLoaded = false

    private(set) var runtimeVersion: String?
    private(set) var availableRuntime: RuntimeRelease?
    private(set) var d3dMetalImported: D3DMetalInfo?
    private(set) var rosettaInstalled = Rosetta.isInstalled

    var selection: SidebarItem? = .library(.all)
    var selectedGameID: SteamGame.ID?
    var searchText = ""
    var activity: Activity?
    var errorMessage: String?
    var bottleSettingsTarget: Bottle?

    init(paths: LauncherPaths = .standard) {
        self.paths = paths
        self.playtime = PlaytimeStore(file: paths.playtimeFile)
        try? paths.createOwnedFolders()
    }

    // MARK: - Derived state

    var managedEngine: Engine? { engines.first { $0.kind == .managed } }
    var crossOverEngine: Engine? { engines.first { $0.kind == .crossOver } }

    func engine(for bottle: Bottle) -> Engine? { engines.first { $0.kind == bottle.engineKind } }
    func bottle(id: Bottle.ID) -> Bottle? { bottles.first { $0.id == id } }
    func bottle(for game: SteamGame) -> Bottle? { bottle(id: game.bottleID) }
    var selectedGame: SteamGame? { selectedGameID.flatMap { id in games.first { $0.id == id } } }

    /// The bottle used for Steam by default: the first one with Steam, else the first launcher bottle.
    var primaryBottle: Bottle? {
        bottles.first { steamInstalled.contains($0.id) && $0.owner == .launcher }
            ?? bottles.first { steamInstalled.contains($0.id) }
            ?? bottles.first { $0.owner == .launcher }
    }

    var primaryAccount: SteamAccount? { primaryBottle.flatMap { accounts[$0.id] } ?? accounts.values.first }

    func isDone(_ step: SetupStep) -> Bool {
        switch step {
        case .rosetta: rosettaInstalled
        case .runtime: managedEngine != nil || crossOverEngine != nil
        case .bottle: !bottles.isEmpty
        case .steam: !steamInstalled.isEmpty
        case .login: !accounts.isEmpty
        }
    }

    var currentSetupStep: SetupStep? { SetupStep.allCases.first { !isDone($0) } }
    var isSetupComplete: Bool { currentSetupStep == nil }

    var visibleGames: [SteamGame] {
        var result = games
        switch selection {
        case .library(.installed): result = result.filter(\.isFullyInstalled)
        case .library(.recent):
            result = result.filter { lastPlayed(for: $0) != nil }
                .sorted { (lastPlayed(for: $0) ?? .distantPast) > (lastPlayed(for: $1) ?? .distantPast) }
        case .bottle(let id): result = result.filter { $0.bottleID == id }
        case .library(.all), .none: break
        }
        if !searchText.isEmpty {
            result = result.filter { $0.name.localizedStandardContains(searchText) }
        }
        return result
    }

    func lastPlayed(for game: SteamGame) -> Date? {
        [game.lastPlayed, playtime.record(for: game.id).lastPlayed].compactMap { $0 }.max()
    }

    func playtimeText(for game: SteamGame) -> String {
        PlaytimeStore.format(playtime.record(for: game.id).total)
    }

    func effectiveBackend(for game: SteamGame) -> GraphicsBackend? {
        guard let bottle = bottle(for: game), let engine = engine(for: bottle) else { return nil }
        return engine.kind == .crossOver ? bottle.settings.graphics : GraphicsPlan.gameBackend(for: bottle.settings.graphics, engine: engine)
    }

    // MARK: - Loading

    /// Rescans engines, bottles, Steam libraries and accounts (file I/O off the main actor).
    func refresh() async {
        let paths = paths
        let snapshot = await Task.detached(priority: .userInitiated) { () -> Snapshot in
            let engines = EngineLocator(paths: paths).discover()
            let bottles = BottleStore(paths: paths).discover()
            var games: [SteamGame] = []
            var accounts: [Bottle.ID: SteamAccount] = [:]
            var installed: Set<Bottle.ID> = []
            for bottle in bottles {
                let library = SteamLibrary(bottle: bottle)
                guard library.isSteamInstalled else { continue }
                installed.insert(bottle.id)
                games += library.games()
                accounts[bottle.id] = library.accounts().first
            }
            let processes = ProcessList.current()
            let running = Set(bottles.filter { bottle in
                ProcessList.wineProcesses(inPrefix: bottle.url, from: processes).contains { $0.windowsImageName == "steam.exe" }
            }.map(\.id))
            return Snapshot(
                engines: engines, bottles: bottles, games: games, accounts: accounts, steamInstalled: installed, steamRunning: running,
                runtimeVersion: RuntimeInstaller(paths: paths).installedVersion(),
                d3dMetal: D3DMetalInstaller(paths: paths).importedInfo()
            )
        }.value

        engines = snapshot.engines
        bottles = snapshot.bottles
        games = snapshot.games.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        accounts = snapshot.accounts
        steamInstalled = snapshot.steamInstalled
        steamRunning = snapshot.steamRunning
        runtimeVersion = snapshot.runtimeVersion
        d3dMetalImported = snapshot.d3dMetal
        rosettaInstalled = Rosetta.isInstalled
        if let id = selectedGameID, !games.contains(where: { $0.id == id }) { selectedGameID = nil }
        if case .bottle(let id) = selection, bottle(id: id) == nil { selection = .library(.all) }
        hasLoaded = true
    }

    private struct Snapshot: Sendable {
        let engines: [Engine]
        let bottles: [Bottle]
        let games: [SteamGame]
        let accounts: [Bottle.ID: SteamAccount]
        let steamInstalled: Set<Bottle.ID>
        let steamRunning: Set<Bottle.ID>
        let runtimeVersion: String?
        let d3dMetal: D3DMetalInfo?
    }

    /// Background refresh loop: picks up Steam logins, new installs and Steam start/stop.
    func monitor() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(5))
            guard activity == nil else { continue }
            await refresh()
        }
    }

    func checkForRuntimeUpdate() async {
        do {
            let release = try await RuntimeInstaller(paths: paths).fetchLatestRelease()
            if let installed = runtimeVersion, !RuntimeInstaller.isNewer(release.version, than: installed) {
                availableRuntime = nil
            } else {
                availableRuntime = release
            }
        } catch {
            Log.runtime.error("Update-Prüfung fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Setup actions

    /// Runs `operation` with an activity indicator and error reporting. Only one at a time.
    private func perform(_ title: String, _ operation: () async throws -> Void) async {
        guard activity == nil else { return }
        activity = Activity(title: title)
        defer { activity = nil }
        do {
            try await operation()
        } catch is CancellationError {
        } catch {
            errorMessage = error.localizedDescription
            Log.session.error("\(title, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
        await refresh()
    }

    func installRosetta() async {
        await perform("Rosetta 2 wird installiert …") {
            // softwareupdate needs admin rights; macOS asks for the password.
            let script = "do shell script \"\(Rosetta.installCommand)\" with administrator privileges"
            let result = try await ProcessRunner.run(URL(filePath: "/usr/bin/osascript"), arguments: ["-e", script], timeout: .seconds(900))
            guard result.succeeded else { throw LauncherError("Rosetta konnte nicht installiert werden.", detail: result.output) }
        }
    }

    func installRuntime() async {
        await perform("Runtime wird geladen …") {
            let installer = RuntimeInstaller(paths: paths)
            let release: RuntimeRelease
            if let availableRuntime {
                release = availableRuntime
            } else {
                release = (try? await installer.fetchLatestRelease()) ?? RuntimeInstaller.fallbackRelease
            }
            activity?.detail = "Version \(release.version) · Wine 11 · DXMT \(release.dxmtVersion ?? "–") · DXVK \(release.dxvkVersion ?? "–")"
            try await installer.install(release) { [weak self] phase in
                Task { @MainActor in self?.update(phase) }
            }
            try D3DMetalInstaller(paths: paths).deployIfImported()
            availableRuntime = nil
        }
    }

    private func update(_ phase: RuntimeInstallPhase) {
        guard activity != nil else { return }
        switch phase {
        case .downloading(let fraction, let bytes, let total):
            activity?.title = "Runtime wird geladen …"
            activity?.progress = fraction
            let format = ByteCountFormatStyle(style: .file)
            activity?.detail = "\(bytes.formatted(format)) von \(total.formatted(format))"
        case .verifying:
            activity?.title = "Prüfsumme wird kontrolliert …"; activity?.progress = nil
        case .extracting:
            activity?.title = "Runtime wird entpackt …"; activity?.progress = nil
        case .finishing:
            activity?.title = "Runtime wird eingerichtet …"; activity?.progress = nil
        }
    }

    func createSteamBottle(named name: String = "Steam") async {
        guard let engine = managedEngine else { errorMessage = "Bitte zuerst die Runtime installieren."; return }
        await perform("Windows-Umgebung wird erstellt …") {
            activity?.detail = "Das dauert beim ersten Mal 1–2 Minuten."
            let bottle = try await BottleProvisioner(engine: engine, paths: paths).createBottle(named: name)
            selection = .bottle(bottle.id)
        }
    }

    func installSteam(in bottle: Bottle) async {
        guard let engine = engine(for: bottle) else { return }
        await perform("Steam wird installiert …") {
            activity?.detail = "SteamSetup.exe wird geladen und installiert."
            let client = SteamClient(wine: Wine(engine: engine, bottle: bottle, paths: paths))
            try await client.install()
        }
    }

    // MARK: - Steam

    private func client(for bottle: Bottle) throws -> SteamClient {
        guard let engine = engine(for: bottle) else {
            throw LauncherError("Keine passende Engine für „\(bottle.name)“ installiert.", detail: bottle.owner == .crossOver ? "CrossOver wird benötigt." : "Bitte die Runtime installieren.")
        }
        return SteamClient(wine: Wine(engine: engine, bottle: bottle, paths: paths))
    }

    /// Executable names of all installed games in the bottle (for per-game DLL overrides).
    private func gameExecutables(in bottle: Bottle) async -> [(game: SteamGame, executables: [URL])] {
        let games = games.filter { $0.bottleID == bottle.id && $0.isFullyInstalled }
        return await Task.detached(priority: .userInitiated) {
            games.map { game in (game, Self.executables(in: game.installFolder)) }
        }.value
    }

    nonisolated static func executables(in folder: URL) -> [URL] {
        let names = SteamLibrary.executableNames(in: folder)
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return [] }
        var result: [URL] = []
        for case let url as URL in enumerator where names.contains(url.lastPathComponent.lowercased()) {
            result.append(url)
            if result.count >= names.count * 2 { break }
        }
        return result
    }

    private func prepareSteam(_ client: SteamClient) async throws {
        let entries = await gameExecutables(in: client.bottle)
        let names = Set(entries.flatMap { $0.executables.map { $0.lastPathComponent.lowercased() } })
        try await client.prepare(
            gameExecutables: names,
            dxmtGames: entries.map { ($0.game.installFolder, $0.executables) }
        )
    }

    /// Starts Steam visibly (for login, store, installing games).
    func openSteam(in bottle: Bottle) async {
        await perform("Steam wird gestartet …") {
            let client = try client(for: bottle)
            if client.isRunning {
                try await client.showMainWindow()
                return
            }
            activity?.detail = "Beim ersten Start aktualisiert sich Steam selbst – das kann einige Minuten dauern."
            try await prepareSteam(client)
            try await client.ensureRunning(visible: true, timeout: .seconds(600))
        }
    }

    func quitSteam(in bottle: Bottle) async {
        await perform("Steam wird beendet …") {
            try await client(for: bottle).shutdown()
        }
    }

    func killBottle(_ bottle: Bottle) async {
        await perform("Alle Prozesse in „\(bottle.name)“ werden beendet …") {
            try await client(for: bottle).wine.killAll()
        }
    }

    // MARK: - Games

    func play(_ game: SteamGame) async {
        guard sessions[game.id] == nil else { return }
        guard let bottle = bottle(for: game) else { return }
        do {
            let client = try client(for: bottle)
            sessions[game.id] = .preparing("Wird vorbereitet …")
            try await prepareSteam(client)

            if !client.isRunning {
                sessions[game.id] = .preparing("Steam startet …")
                try await client.ensureRunning(visible: accounts[bottle.id] == nil, timeout: .seconds(300))
                // Give the client a moment to finish logging in before handing over the launch.
                try await Task.sleep(for: .seconds(8))
            }
            sessions[game.id] = .preparing("Spiel startet …")
            let executables = await Task.detached { SteamLibrary.executableNames(in: game.installFolder) }.value
            let monitor = GameMonitor(bottle: bottle, executableNames: executables)
            try await client.launch(appID: game.appID)

            guard try await monitor.waitForStart(timeout: .seconds(240)) else {
                sessions[game.id] = nil
                errorMessage = "„\(game.name)“ wurde nicht erkannt.\nFalls Steam ein Fenster (z. B. Update, EULA oder Cloud-Sync) zeigt, bitte dort bestätigen. Details im Log: \(client.wine.logFile.path)"
                return
            }
            let start = Date.now
            sessions[game.id] = .running(since: start)
            Log.session.info("\(game.name, privacy: .public) läuft")
            try await monitor.waitForExit()
            playtime.addSession(gameID: game.id, start: start)
            Log.session.info("\(game.name, privacy: .public) beendet")
        } catch is CancellationError {
        } catch {
            errorMessage = error.localizedDescription
        }
        sessions[game.id] = nil
    }

    func stop(_ game: SteamGame) async {
        guard let bottle = bottle(for: game) else { return }
        let names = await Task.detached { SteamLibrary.executableNames(in: game.installFolder) }.value
        await GameMonitor(bottle: bottle, executableNames: names).terminate()
    }

    func installGame(appID: String, in bottle: Bottle) async {
        await perform("Installation wird in Steam geöffnet …") {
            let client = try client(for: bottle)
            if !client.isRunning {
                try await prepareSteam(client)
                try await client.ensureRunning(visible: true, timeout: .seconds(300))
            }
            try await client.install(appID: appID)
        }
    }

    // MARK: - Bottles & tools

    func save(_ bottle: Bottle) {
        do {
            try BottleStore(paths: paths).save(bottle)
            if let index = bottles.firstIndex(where: { $0.id == bottle.id }) { bottles[index] = bottle }
        } catch {
            errorMessage = "Einstellungen konnten nicht gespeichert werden: \(error.localizedDescription)"
        }
    }

    func restartSteam(in bottle: Bottle) async {
        await quitSteam(in: bottle)
        await openSteam(in: bottle)
    }

    func run(executable: URL, in bottle: Bottle) async {
        await perform("\(executable.lastPathComponent) wird gestartet …") {
            try await client(for: bottle).wine.start(unixPath: executable)
        }
    }

    func runTool(_ tool: String, in bottle: Bottle) async {
        await perform("\(tool) wird geöffnet …") {
            try await client(for: bottle).wine.run(tool, timeout: nil)
        }
    }

    func applyWindowsVersion(in bottle: Bottle) async {
        await perform("Windows-Version wird gesetzt …") {
            try await client(for: bottle).wine.run("winecfg", ["-v", bottle.settings.windowsVersion])
        }
    }

    func importD3DMetal(from url: URL) async {
        await perform("Game Porting Toolkit wird importiert …") {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let info = try await D3DMetalInstaller(paths: paths).importPayload(from: url)
            d3dMetalImported = info
        }
    }

    func removeD3DMetal() async {
        await perform("D3DMetal wird entfernt …") {
            try D3DMetalInstaller(paths: paths).remove()
        }
    }

    func deleteBottle(_ bottle: Bottle) async {
        await perform("„\(bottle.name)“ wird gelöscht …") {
            let client = try? client(for: bottle)
            await client?.wine.killAll()
            try BottleStore(paths: paths).delete(bottle)
        }
    }

    func revealLog(for bottle: Bottle) {
        let log = paths.logs.appending(path: "\(bottle.name).log")
        if FileManager.default.fileExists(atPath: log.path) {
            NSWorkspace.shared.activateFileViewerSelecting([log])
        } else {
            NSWorkspace.shared.open(paths.logs)
        }
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Stops sessions cleanly when the app quits (records play time of running games).
    func applicationWillTerminate() {
        for (id, state) in sessions {
            if case .running(let since) = state { playtime.addSession(gameID: id, start: since) }
        }
    }
}
