import Darwin
import Foundation

/// Recognizes a running game from the process list.
///
/// Wine sets each process's `argv[0]` to the Windows image path, so bottle games are matched by image name
/// (from a scan of the install folder) and by `WINEPREFIX`. Steam's `-applaunch` / `steam://rungameid` hand off and
/// return immediately, so the launcher process says nothing about the game's lifetime.
public struct GameMonitor: Sendable {
    private let match: @Sendable ([RunningProcess]) -> [RunningProcess]

    /// A game inside a launcher or CrossOver bottle.
    public init(bottle: Bottle, executableNames: Set<String>) {
        let names = executableNames.subtracting(GraphicsPlan.steamExecutables)
        let prefix = bottle.url
        match = { snapshot in
            guard !names.isEmpty else { return [] }
            return ProcessList.wineProcesses(inPrefix: prefix, from: snapshot)
                .filter { $0.windowsImageName.map(names.contains) ?? false }
        }
    }

    /// A game of the native macOS Steam client (native, or Windows via Steam Play).
    public init(macGame game: SteamGame, executableNames: Set<String>) {
        let names = executableNames.subtracting(GraphicsPlan.steamExecutables)
        match = { MacSteamLibrary.runningProcesses(of: game, executableNames: names, snapshot: $0) }
    }

    public func runningProcesses(_ snapshot: [RunningProcess]? = nil) -> [RunningProcess] {
        match(snapshot ?? ProcessList.current())
    }

    public var isRunning: Bool { !runningProcesses().isEmpty }

    /// Waits for the game to appear. Returns `false` on timeout.
    public func waitForStart(timeout: Duration = .seconds(180), poll: Duration = .seconds(2)) async throws -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if isRunning { return true }
            try await Task.sleep(for: poll)
        }
        return isRunning
    }

    /// Waits until no game process is left. Tolerates short gaps (launcher → game handover).
    public func waitForExit(poll: Duration = .seconds(3), grace: Int = 2) async throws {
        var misses = 0
        while misses <= grace {
            try await Task.sleep(for: poll)
            misses = isRunning ? 0 : misses + 1
        }
    }

    /// SIGTERM, then SIGKILL after `grace` for survivors.
    public static func terminate(_ processes: [RunningProcess], grace: Duration = .seconds(5)) async {
        guard !processes.isEmpty else { return }
        for process in processes { kill(process.pid, SIGTERM) }
        try? await Task.sleep(for: grace)
        for process in processes where kill(process.pid, 0) == 0 { kill(process.pid, SIGKILL) }
    }

    public func terminate() async {
        await Self.terminate(runningProcesses())
    }
}
