import Foundation
import AppKit

public final class GameRunner: @unchecked Sendable {
    public static let shared = GameRunner()

    private var activeProcesses: [String: Process] = [:]
    private let lock = NSLock()

    public init() {}

    /// Check if an app/game is currently running
    public func isRunning(appId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if let proc = activeProcesses[appId] {
            return proc.isRunning
        }
        return false
    }

    // MARK: - Argument & Environment helpers

    /// Build wine arguments based on engine type.
    /// CrossOver uses --bottle <name> -- <args...>; all others pass args directly (WINEPREFIX suffices).
    private func wineArguments(engine: Engine, bottle: Bottle, execArgs: [String]) -> [String] {
        switch engine.type {
        case .crossOver:
            return ["--bottle", bottle.name, "--"] + execArgs
        case .appleGPTK, .whisky, .customWine:
            // Plain wine style: just the executable and arguments
            return execArgs
        }
    }

    /// Prepare standard environment variables for GPTK / CrossOver / Whisky
    private func wineEnvironment(bottle: Bottle, overrideHUD: Bool? = nil) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["CX_BOTTLE"] = bottle.name
        env["WINEPREFIX"] = bottle.path.path
        env["WINEMSYNC"] = bottle.msyncEnabled ? "1" : "0"
        env["WINED3DMETAL"] = bottle.d3dMetalEnabled ? "1" : "0"
        env["D3DM_ENABLE_METALFX"] = bottle.metalFxEnabled ? "1" : "0"

        // Advertise AVX / AVX2 instructions under Rosetta 2 (Apple Game Porting Toolkit standard)
        env["ROSETTA_ADVERTISE_AVX"] = "1"

        if let overrideHUD = overrideHUD {
            env["MTL_HUD_ENABLED"] = overrideHUD ? "1" : "0"
        } else if bottle.metalHudEnabled {
            env["MTL_HUD_ENABLED"] = "1"
        }

        return env
    }

    /// Launch a Steam game inside a bottle using the specified engine
    public func launchGame(
        game: SteamGame,
        bottle: Bottle,
        engine: Engine,
        overrideHUD: Bool? = nil,
        onTerminated: (@Sendable () -> Void)? = nil
    ) throws {
        lock.lock()
        if let existing = activeProcesses[game.appId], existing.isRunning {
            lock.unlock()
            return
        }
        lock.unlock()

        let process = Process()
        process.executableURL = engine.wineExecutableURL
        process.environment = wineEnvironment(bottle: bottle, overrideHUD: overrideHUD)

        let steamExec = "C:/Program Files (x86)/Steam/steam.exe"
        process.arguments = wineArguments(
            engine: engine,
            bottle: bottle,
            execArgs: [steamExec, "-applaunch", game.appId]
        )

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        process.terminationHandler = { [weak self] proc in
            PlaytimeTracker.shared.sessionEnded(appId: game.appId)
            self?.lock.lock()
            self?.activeProcesses.removeValue(forKey: game.appId)
            self?.lock.unlock()
            onTerminated?()
        }

        try process.run()

        // Start session tracking after process has successfully spawned
        PlaytimeTracker.shared.sessionStarted(appId: game.appId)

        lock.lock()
        activeProcesses[game.appId] = process
        lock.unlock()
    }

    /// Launch arbitrary Windows executable (.exe or installer) inside the bottle
    public func launchCustomExecutable(
        exeURL: URL,
        bottle: Bottle,
        engine: Engine
    ) throws {
        let process = Process()
        process.executableURL = engine.wineExecutableURL
        process.environment = wineEnvironment(bottle: bottle)

        process.arguments = wineArguments(
            engine: engine,
            bottle: bottle,
            execArgs: [exeURL.path]
        )

        try process.run()
    }

    /// Launch wine configuration (winecfg)
    public func launchWineCfg(bottle: Bottle, engine: Engine) throws {
        let process = Process()
        process.executableURL = engine.wineExecutableURL
        process.environment = wineEnvironment(bottle: bottle)

        process.arguments = wineArguments(
            engine: engine,
            bottle: bottle,
            execArgs: ["winecfg"]
        )

        try process.run()
    }

    /// Launch the Steam client UI inside the bottle directly
    public func launchSteamClient(bottle: Bottle, engine: Engine) throws {
        let process = Process()
        process.executableURL = engine.wineExecutableURL
        process.environment = wineEnvironment(bottle: bottle)

        let steamExec = "C:/Program Files (x86)/Steam/steam.exe"
        process.arguments = wineArguments(
            engine: engine,
            bottle: bottle,
            execArgs: [steamExec]
        )

        try process.run()
    }

    /// Stop/kill a running game process
    public func terminateGame(appId: String) {
        lock.lock()
        let proc = activeProcesses[appId]
        lock.unlock()

        proc?.terminate()
    }
}
