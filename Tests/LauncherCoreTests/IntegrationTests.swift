import Foundation
import Testing
@testable import LauncherCore

/// End-to-end setup against the real system (downloads ~460 MB, creates a bottle, installs Steam).
/// Run explicitly: `MGL_INTEGRATION=1 swift test --filter IntegrationTests`
///
/// By default everything lives in an isolated folder (kept between runs to avoid re-downloading) and Steam is shut
/// down at the end. `MGL_INTEGRATION_REAL=1` uses the app's standard locations instead — only do that while the app
/// is not running, because the test rewrites the bottle's registry overrides.
@Suite("Integration (real system)", .serialized, .enabled(if: ProcessInfo.processInfo.environment["MGL_INTEGRATION"] == "1"))
struct IntegrationTests {
    static let useRealLocations = ProcessInfo.processInfo.environment["MGL_INTEGRATION_REAL"] == "1"
    let paths: LauncherPaths = {
        if useRealLocations { return .standard }
        let root = FileManager.default.temporaryDirectory.appending(path: "MGL-Integration", directoryHint: .isDirectory)
        return LauncherPaths(root: root, logs: root.appending(path: "Logs"), home: root.appending(path: "home"))
    }()

    func log(_ message: String) {
        print("[integration] \(Date.now.formatted(date: .omitted, time: .standard)) \(message)")
    }

    @Test(.timeLimit(.minutes(60))) func setUpRuntimeBottleAndSteam() async throws {
        try #require(Rosetta.isInstalled, "Rosetta 2 fehlt: softwareupdate --install-rosetta")
        log("Ablage: \(paths.root.path)")

        // 1. Runtime
        let installer = RuntimeInstaller(paths: paths)
        if installer.installedVersion() == nil {
            let release = (try? await installer.fetchLatestRelease()) ?? RuntimeInstaller.fallbackRelease
            log("Runtime \(release.version) wird installiert")
            let lastLogged = LockedValue(-1)
            try await installer.install(release) { phase in
                if case .downloading(let fraction, _, _) = phase {
                    let percent = Int(fraction * 100)
                    if percent / 10 != lastLogged.value / 10 { lastLogged.value = percent; print("[integration] Download \(percent) %") }
                } else {
                    print("[integration] \(phase)")
                }
            }
        }
        let engine = try #require(EngineLocator(paths: paths).managedEngine())
        log("Engine: \(engine.displayName), DXMT: \(engine.dxmtFolder != nil), DXVK: \(engine.dxvkFolder != nil), D3DMetal: \(engine.d3dMetal?.version ?? "–")")

        // 2. Bottle
        var bottle = BottleStore(paths: paths).discover().first { $0.owner == .launcher }
        if bottle == nil {
            log("Bottle wird erstellt")
            bottle = try await BottleProvisioner(engine: engine, paths: paths).createBottle(named: "Steam")
        }
        let steamBottle = try #require(bottle)
        #expect(steamBottle.isInitialized())
        log("Bottle: \(steamBottle.url.path)")

        // 3. Steam
        let client = SteamClient(wine: Wine(engine: engine, bottle: steamBottle, paths: paths))
        if !client.library.isSteamInstalled {
            log("Steam wird installiert")
            try await client.install()
        }
        #expect(client.library.isSteamInstalled)

        // 4. Start Steam visibly (first start self-updates). DXMT copies next to games are left alone.
        try await client.prepare(gameExecutables: [], dxmtGames: nil)
        log("Steam wird gestartet")
        try await client.ensureRunning(visible: true, timeout: .seconds(900))
        log("steam.exe läuft: \(client.steamProcesses().map(\.pid))")
        #expect(client.isRunning)

        // 5. Commands to the running client must return although Steam/wineserver keep running (inherited output).
        let clock = ContinuousClock()
        let elapsed = try await clock.measure { try await client.showMainWindow() }
        log("steam://open/main zurück nach \(elapsed)")
        #expect(elapsed < .seconds(60))
        #expect(client.isRunning)

        if !Self.useRealLocations {
            await client.shutdown()
            #expect(!client.isRunning)
        }
    }
}

final class LockedValue<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T
    init(_ value: T) { stored = value }
    var value: T {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}
