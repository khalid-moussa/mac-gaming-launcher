import Darwin
import Foundation

/// Recognizes a running game by its Windows executable names inside the bottle.
///
/// Wine sets each process's `argv[0]` to the Windows image path, so game processes are matched by image name
/// (from a scan of the install folder) and by `WINEPREFIX`. Steam's `-applaunch` hands off and exits immediately,
/// so the wrapper process says nothing about the game's lifetime.
public struct GameMonitor: Sendable {
    public let bottle: Bottle
    public let executableNames: Set<String>

    public init(bottle: Bottle, executableNames: Set<String>) {
        self.bottle = bottle
        self.executableNames = executableNames.subtracting(GraphicsPlan.steamExecutables)
    }

    public func runningProcesses(_ snapshot: [RunningProcess]? = nil) -> [RunningProcess] {
        guard !executableNames.isEmpty else { return [] }
        return ProcessList.wineProcesses(inPrefix: bottle.url, from: snapshot ?? ProcessList.current())
            .filter { $0.windowsImageName.map(executableNames.contains) ?? false }
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
