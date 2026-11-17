import Darwin
import Foundation

/// Recognizes a running game from the process list.
///
/// Wine sets each process's `argv[0]` to the Windows image path, so bottle games are matched by image name
/// (from a scan of the install folder) and by `WINEPREFIX`. Steam's `-applaunch` / `steam://rungameid` hand off and
/// return immediately, so the launcher process says nothing about the game's lifetime.
public struct GameMonitor: Sendable {
    private let match: @Sendable ([RunningProcess]) -> [RunningProcess]

    /// A game inside a launcher or CrossOver bottle. Primary match: the process image lies inside the install folder
    /// (any Windows spelling of it); fallback: a known executable name (games started via a helper elsewhere).
    public init(bottle: Bottle, installFolder: URL, executableNames: Set<String>) {
        let names = executableNames.subtracting(GraphicsPlan.steamExecutables)
        let prefixes = SteamLibrary(bottle: bottle).windowsPathPrefixes(forMacFolder: installFolder)
        let prefix = bottle.url
        match = { snapshot in
            ProcessList.wineProcesses(inPrefix: prefix, from: snapshot).filter { process in
                guard let image = process.windowsImageName, !GraphicsPlan.steamExecutables.contains(image) else { return false }
                let path = process.normalizedWindowsPath
                return prefixes.contains { path.hasPrefix($0) } || names.contains(image)
            }
        }
    }

    /// A game of the native macOS Steam client (native, or Windows via Steam Play). Processes in `excludedPrefixes`
    /// (the launcher's own bottles) are never attributed to it.
    public init(macGame game: SteamGame, executableNames: Set<String>, excludedPrefixes: [URL] = []) {
        let names = executableNames.subtracting(GraphicsPlan.steamExecutables)
        let excluded = Set(excludedPrefixes.map { $0.resolvingSymlinksInPath().standardizedFileURL.path })
        match = { snapshot in
            MacSteamLibrary.runningProcesses(of: game, executableNames: names, snapshot: snapshot).filter { process in
                process.winePrefix.map { !excluded.contains(URL(filePath: $0).resolvingSymlinksInPath().standardizedFileURL.path) } ?? true
            }
        }
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

    /// Waits until no game process is left. Tolerates gaps: long ones during the first `startupWindow` (a small
    /// bootstrapper hands over to a third-party launcher, which starts the game minutes later), short ones after.
    public func waitForExit(poll: Duration = .seconds(3), grace: Int = 2, startupWindow: Duration = .seconds(90)) async throws {
        let clock = ContinuousClock()
        let started = clock.now
        var misses = 0
        while true {
            try await Task.sleep(for: poll)
            misses = isRunning ? 0 : misses + 1
            let allowed = clock.now - started < startupWindow ? Int(startupWindow / poll) : grace
            if misses > allowed { return }
        }
    }

    /// SIGTERM, then SIGKILL after `grace` for survivors. Survivors are re-identified from a fresh snapshot (same PID
    /// and image), so a PID reused in the meantime is never killed.
    public static func terminate(_ processes: [RunningProcess], grace: Duration = .seconds(5)) async {
        guard !processes.isEmpty else { return }
        for process in processes { kill(process.pid, SIGTERM) }
        try? await Task.sleep(for: grace)
        let wanted = Set(processes.map { "\($0.pid)|\($0.commandName)" })
        for process in ProcessList.current() where wanted.contains("\(process.pid)|\(process.commandName)") {
            kill(process.pid, SIGKILL)
        }
    }

    public func terminate() async {
        await Self.terminate(runningProcesses())
    }
}
