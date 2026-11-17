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
    /// Games of the native macOS Steam client.
    case macSteam
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
    /// Native macOS Steam client found (its library is shown alongside the bottles).
    private(set) var macSteamInstalled = false
    private(set) var sessions: [SteamGame.ID: SessionState] = [:]
    private(set) var hasLoaded = false

    private(set) var runtimeVersion: String?
    private(set) var availableRuntime: RuntimeRelease?
    private(set) var d3dMetalImported: D3DMetalInfo?
    private(set) var rosettaInstalled = Rosetta.isInstalled

    /// Changing the sidebar selection or the search leaves an open game detail (otherwise the click seems to do nothing).
    var selection: SidebarItem? = .library(.all) {
        didSet { if selection != oldValue { selectedGameID = nil } }
    }
    var selectedGameID: SteamGame.ID?
    var searchText = "" {
        didSet { if searchText != oldValue, !searchText.isEmpty { selectedGameID = nil } }
    }
    private var refreshGeneration = 0
    private var launchTasks: [SteamGame.ID: Task<Void, Never>] = [:]
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
    func isMacSteamGame(_ game: SteamGame) -> Bool { game.bottleID == MacSteamLibrary.sourceID }
    /// Where a game lives, for display: bottle name or "Steam (macOS)".
    func sourceName(for game: SteamGame) -> String? {
        isMacSteamGame(game) ? "Steam (macOS)" : bottle(for: game)?.name
    }
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
        case .runtime: managedEngine != nil || (crossOverEngine != nil && bottles.contains { $0.owner == .crossOver })
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
        case .macSteam: result = result.filter(isMacSteamGame)
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
        PlaytimeStore.format(playtime.total(for: game.id))
    }

    /// Why a state-changing action can't run right now, or `nil`.
    var busyMessage: String? {
        activity.map { "Bitte warten, bis „\($0.title.trimmingCharacters(in: CharacterSet(charactersIn: " …")))“ abgeschlossen ist." }
    }

    func hasRunningSession(in bottle: Bottle) -> Bool {
        sessions.keys.contains { id in games.first { $0.id == id }?.bottleID == bottle.id }
    }

    /// Whether any process runs in a bottle that uses the managed runtime (fresh scan, off the main actor).
    private func managedRuntimeInUse() async -> Bool {
        let prefixes = bottles.filter { $0.engineKind == .managed }.map(\.url)
        return await Task.detached {
            let processes = ProcessList.current()
            return prefixes.contains { !ProcessList.wineProcesses(inPrefix: $0, from: processes).isEmpty }
        }.value
    }

    func effectiveBackend(for game: SteamGame) -> GraphicsBackend? {
        guard let bottle = bottle(for: game), let engine = engine(for: bottle) else { return nil }
        return engine.kind == .crossOver ? bottle.settings.graphics : GraphicsPlan.gameBackend(for: bottle.settings.graphics, engine: engine)
    }

    // MARK: - Loading

    /// Rescans engines, bottles, Steam libraries and accounts (file I/O off the main actor).
    func refresh() async {
        // Overlapping refreshes (monitor loop, ⌘R, after an action): only the newest one may publish.
        refreshGeneration += 1
        let generation = refreshGeneration
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
            let macSteam = MacSteamLibrary(home: paths.home)
            if macSteam.isInstalled { games += macSteam.games() }
            let processes = ProcessList.current()
            let running = Set(bottles.filter { bottle in
                ProcessList.wineProcesses(inPrefix: bottle.url, from: processes).contains { $0.windowsImageName == "steam.exe" }
            }.map(\.id))
            return Snapshot(
                engines: engines, bottles: bottles, games: games, accounts: accounts, steamInstalled: installed, steamRunning: running,
                macSteamInstalled: macSteam.isInstalled,
                runtimeVersion: RuntimeInstaller(paths: paths).installedVersion(),
                d3dMetal: D3DMetalInstaller(paths: paths).importedInfo()
            )
        }.value
        guard generation == refreshGeneration else { return }

        engines = snapshot.engines
        bottles = snapshot.bottles
        games = snapshot.games.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        accounts = snapshot.accounts
        steamInstalled = snapshot.steamInstalled
        steamRunning = snapshot.steamRunning
        macSteamInstalled = snapshot.macSteamInstalled
        runtimeVersion = snapshot.runtimeVersion
        d3dMetalImported = snapshot.d3dMetal
        rosettaInstalled = Rosetta.isInstalled
        if let id = selectedGameID, !games.contains(where: { $0.id == id }) { selectedGameID = nil }
        if case .bottle(let id) = selection, bottle(id: id) == nil { selection = .library(.all) }
        if selection == .macSteam, !macSteamInstalled { selection = .library(.all) }
        hasLoaded = true
    }

    private struct Snapshot: Sendable {
        let engines: [Engine]
        let bottles: [Bottle]
        let games: [SteamGame]
        let accounts: [Bottle.ID: SteamAccount]
        let steamInstalled: Set<Bottle.ID>
        let steamRunning: Set<Bottle.ID>
        let macSteamInstalled: Bool
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
        guard activity == nil else { return }
        do {
            let release = try await RuntimeInstaller(paths: paths).fetchLatestRelease()
            guard activity == nil else { return } // an install finished meanwhile; its result wins
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
        if let busyMessage {
            errorMessage = busyMessage
            return
        }
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
            if result.output.contains("(-128)") { throw CancellationError() } // user cancelled the password prompt
            guard result.succeeded else { throw LauncherError("Rosetta konnte nicht installiert werden.", detail: result.output) }
        }
    }

    /// Replacing files in the shared Wine tree under a running wineserver breaks the bottles that use it.
    private func ensureRuntimeIdle(_ action: String) async -> Bool {
        if let busyMessage { errorMessage = busyMessage; return false }
        let inUse = await managedRuntimeInUse()
        if !sessions.isEmpty || inUse {
            errorMessage = "Bitte zuerst Steam, alle Spiele und Wine-Programme beenden, bevor \(action)."
            return false
        }
        return true
    }

    func installRuntime() async {
        guard await ensureRuntimeIdle("die Runtime aktualisiert wird") else { return }
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
            availableRuntime = nil
            let paths = paths
            do {
                try await Task.detached { try D3DMetalInstaller(paths: paths).deployIfImported() }.value
            } catch {
                throw LauncherError("Die Runtime wurde aktualisiert, aber D3DMetal konnte nicht wieder eingebunden werden.", detail: error.localizedDescription)
            }
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
        let games = games.filter { $0.bottleID == bottle.id }
        return await Task.detached(priority: .userInitiated) {
            games
                .filter { FileManager.default.fileExists(atPath: $0.installFolder.path) }
                .map { game in (game, Self.executables(in: game.installFolder)) }
        }.value
    }

    /// Game executables (depth-limited walk, so large asset folders can't hide them).
    nonisolated static func executables(in folder: URL, maxDepth: Int = 5) -> [URL] {
        let names = SteamLibrary.executableNames(in: folder, maxDepth: maxDepth)
        guard !names.isEmpty,
              let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsPackageDescendants])
        else { return [] }
        var result: [URL] = []
        var visited = 0
        for case let url as URL in enumerator {
            visited += 1
            if visited > 300_000 || result.count >= names.count * 2 { break }
            if enumerator.level >= maxDepth { enumerator.skipDescendants() }
            if names.contains(url.lastPathComponent.lowercased()) { result.append(url) }
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
        if hasRunningSession(in: bottle) {
            errorMessage = "In „\(bottle.name)“ läuft noch ein Spiel. Bitte zuerst das Spiel beenden."
            return
        }
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

    /// Starts a game from the UI; the launch can be cancelled while it is still preparing.
    func launch(_ game: SteamGame) {
        guard launchTasks[game.id] == nil else { return }
        launchTasks[game.id] = Task {
            await play(game)
            launchTasks[game.id] = nil
        }
    }

    /// Cancels a launch that hasn't reached the running game yet (Steam keeps whatever it already received).
    func cancelLaunch(_ game: SteamGame) {
        guard case .preparing = sessions[game.id] else { return }
        launchTasks[game.id]?.cancel()
    }

    func play(_ game: SteamGame) async {
        guard sessions[game.id] == nil else { return }
        // Runtime updates, GPTK import and bottle deletion change files the game would run on.
        if let busyMessage { errorMessage = busyMessage; return }
        if isMacSteamGame(game) { return await playWithMacSteam(game) }
        guard let bottle = bottle(for: game) else { return }
        do {
            let client = try client(for: bottle)
            sessions[game.id] = .preparing("Wird vorbereitet …")
            try await prepareSteam(client)
            let executables = await Task.detached { SteamLibrary.executableNames(in: game.installFolder) }.value
            let monitor = GameMonitor(bottle: bottle, installFolder: game.installFolder, executableNames: executables)

            let command = ["-applaunch", game.appID]
            if !client.isRunning {
                sessions[game.id] = .preparing("Steam startet …")
                // The launch rides on the first start; Steam runs it once login and self-update are done.
                let started = try await client.ensureRunning(visible: accounts[bottle.id] == nil, command: command, timeout: .seconds(300))
                if !started { try await client.send(command) }
            } else {
                try await client.send(command)
            }
            sessions[game.id] = .preparing("Spiel startet …")

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
        let names = await Task.detached { SteamLibrary.executableNames(in: game.installFolder) }.value
        if isMacSteamGame(game) {
            await GameMonitor(macGame: game, executableNames: names, excludedPrefixes: bottles.map(\.url)).terminate()
        } else if let bottle = bottle(for: game) {
            await GameMonitor(bottle: bottle, installFolder: game.installFolder, executableNames: names).terminate()
        }
    }

    /// Hands the launch to the native macOS Steam client (which starts itself if needed) and tracks the session.
    private func playWithMacSteam(_ game: SteamGame) async {
        sessions[game.id] = .preparing("Steam (macOS) startet das Spiel …")
        defer { sessions[game.id] = nil }
        let executables = await Task.detached { SteamLibrary.executableNames(in: game.installFolder) }.value
        let monitor = GameMonitor(macGame: game, executableNames: executables, excludedPrefixes: bottles.map(\.url))
        do {
            // Open the URL explicitly with the Mac client, whichever app claims the steam: scheme.
            guard let app = MacSteamLibrary(home: paths.home).appBundle else {
                throw LauncherError("Steam (macOS) wurde nicht gefunden.")
            }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            _ = try await NSWorkspace.shared.open([MacSteamLibrary.launchURL(appID: game.appID)], withApplicationAt: app, configuration: configuration)
            guard try await monitor.waitForStart(timeout: .seconds(240)) else {
                errorMessage = "„\(game.name)“ wurde nicht erkannt. Falls Steam ein Fenster zeigt (Update, EULA, Cloud-Sync), bitte dort bestätigen."
                return
            }
            let start = Date.now
            sessions[game.id] = .running(since: start)
            try await monitor.waitForExit()
            playtime.addSession(gameID: game.id, start: start)
        } catch is CancellationError {
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func installGame(appID: String, in bottle: Bottle) async {
        await perform("Installation wird in Steam geöffnet …") {
            let client = try client(for: bottle)
            let command = ["steam://install/\(appID)"]
            if client.isRunning {
                try await client.send(command)
            } else {
                try await prepareSteam(client)
                let started = try await client.ensureRunning(visible: true, command: command, timeout: .seconds(300))
                if !started { try await client.send(command) }
            }
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
        if hasRunningSession(in: bottle) {
            errorMessage = "In „\(bottle.name)“ läuft noch ein Spiel. Die Änderungen gelten ab dem nächsten Steam-Start."
            return
        }
        await quitSteam(in: bottle)
        await openSteam(in: bottle)
    }

    func run(executable: URL, in bottle: Bottle) async {
        await perform("\(executable.lastPathComponent) wird gestartet …") {
            try await client(for: bottle).wine.start(unixPath: executable)
        }
    }

    func runTool(_ tool: String, in bottle: Bottle) async {
        if let busyMessage { errorMessage = busyMessage; return }
        do {
            let wine = try client(for: bottle).wine
            Task.detached { _ = try? await wine.run(tool, timeout: nil) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func applyWindowsVersion(in bottle: Bottle) async {
        await perform("Windows-Version wird gesetzt …") {
            try await client(for: bottle).wine.run("winecfg", ["-v", bottle.settings.windowsVersion])
        }
    }

    func importD3DMetal(from url: URL) async {
        guard await ensureRuntimeIdle("D3DMetal importiert wird") else { return }
        await perform("Game Porting Toolkit wird importiert …") {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let paths = paths
            let info = try await Task.detached { try await D3DMetalInstaller(paths: paths).importPayload(from: url) }.value
            d3dMetalImported = info
        }
    }

    func removeD3DMetal() async {
        guard await ensureRuntimeIdle("D3DMetal entfernt wird") else { return }
        await perform("D3DMetal wird entfernt …") {
            let paths = paths
            try await Task.detached { try D3DMetalInstaller(paths: paths).remove() }.value
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
