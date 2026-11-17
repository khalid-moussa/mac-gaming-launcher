import Foundation
import Testing
@testable import LauncherCore

/// End-to-end setup against the real system (downloads ~460 MB, creates a bottle, installs Steam).
/// Run explicitly: `MGL_INTEGRATION=1 swift test --filter IntegrationTests`
/// Uses the app's standard locations, so the app picks up the result.
@Suite("Integration (real system)", .serialized, .enabled(if: ProcessInfo.processInfo.environment["MGL_INTEGRATION"] == "1"))
struct IntegrationTests {
    let paths = LauncherPaths.standard

    func log(_ message: String) {
        print("[integration] \(Date.now.formatted(date: .omitted, time: .standard)) \(message)")
    }

    @Test(.timeLimit(.minutes(60))) func setUpRuntimeBottleAndSteam() async throws {
        #expect(Rosetta.isInstalled)

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

        // 4. Start Steam visibly (first start self-updates)
        try await client.prepare(gameExecutables: [], dxmtGames: [])
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
