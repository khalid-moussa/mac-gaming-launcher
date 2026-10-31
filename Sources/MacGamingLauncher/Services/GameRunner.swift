import Foundation

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

    /// Launch a Steam game inside a bottle using the specified engine
    public func launchGame(
        game: SteamGame,
        bottle: Bottle,
        engine: Engine,
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

        // Prepare environment variables for GPTK / CrossOver
        var env = ProcessInfo.processInfo.environment
        env["CX_BOTTLE"] = bottle.name
        env["WINEPREFIX"] = bottle.path.path
        env["WINEMSYNC"] = bottle.msyncEnabled ? "1" : "0"
        env["WINED3DMETAL"] = bottle.d3dMetalEnabled ? "1" : "0"
        env["D3DM_ENABLE_METALFX"] = bottle.metalFxEnabled ? "1" : "0"
        env["MTL_HUD_ENABLED"] = bottle.metalHudEnabled ? "1" : "0"

        process.environment = env

        // Command arguments to execute Steam with applaunch
        process.arguments = [
            "--bottle", bottle.name,
            "--",
            "C:/Program Files (x86)/Steam/steam.exe",
            "-applaunch", game.appId
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        process.terminationHandler = { [weak self] proc in
            self?.lock.lock()
            self?.activeProcesses.removeValue(forKey: game.appId)
            self?.lock.unlock()
            onTerminated?()
        }

        try process.run()

        lock.lock()
        activeProcesses[game.appId] = process
        lock.unlock()
    }

    /// Launch the Steam client UI inside the bottle directly
    public func launchSteamClient(bottle: Bottle, engine: Engine) throws {
        let process = Process()
        process.executableURL = engine.wineExecutableURL

        var env = ProcessInfo.processInfo.environment
        env["CX_BOTTLE"] = bottle.name
        env["WINEPREFIX"] = bottle.path.path
        env["WINEMSYNC"] = bottle.msyncEnabled ? "1" : "0"
        env["WINED3DMETAL"] = bottle.d3dMetalEnabled ? "1" : "0"
        process.environment = env

        process.arguments = [
            "--bottle", bottle.name,
            "--",
            "C:/Program Files (x86)/Steam/steam.exe"
        ]

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
