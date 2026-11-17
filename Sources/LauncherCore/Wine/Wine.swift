import Foundation

/// Runs Wine commands for one bottle with its owning engine.
public struct Wine: Sendable {
    public let engine: Engine
    public let bottle: Bottle
    public let paths: LauncherPaths

    public init(engine: Engine, bottle: Bottle, paths: LauncherPaths) {
        precondition(engine.kind == bottle.engineKind, "Bottle \(bottle.name) needs a \(bottle.engineKind) engine")
        self.engine = engine
        self.bottle = bottle
        self.paths = paths
    }

    public var environment: [String: String] { WineEnvironment.make(engine: engine, bottle: bottle) }

    /// Log file for this bottle (`~/Library/Logs/MacGamingLauncher/<bottle>.log`).
    public var logFile: URL { paths.logs.appending(path: "\(bottle.name).log") }

    /// Arguments for `wine` to run a Windows program (`program` is a Windows path or a Wine builtin like `winecfg`).
    func arguments(program: String, _ arguments: [String]) -> [String] {
        switch engine.kind {
        case .managed:
            return [program] + arguments
        case .crossOver:
            return ["--bottle", bottle.name, "--cx-app", program] + arguments
        }
    }

    /// Runs a Windows program or Wine tool and waits for it.
    @discardableResult
    public func run(_ program: String, _ args: [String] = [], timeout: Duration? = .seconds(300)) async throws -> ProcessResult {
        Log.wine.info("[\(bottle.name, privacy: .public)] wine \(program, privacy: .public) \(args.joined(separator: " "), privacy: .public)")
        appendToLog("$ wine \(program) \(args.joined(separator: " "))")
        return try await ProcessRunner.run(
            engine.wineBinary,
            arguments: arguments(program: program, args),
            environment: environment,
            currentDirectory: engine.wineBinary.deletingLastPathComponent(),
            logFile: logFile,
            timeout: timeout
        )
    }

    /// Starts a Windows program detached via `start /unix` (returns as soon as the program is launched).
    public func start(unixPath: URL, _ args: [String] = []) async throws {
        switch engine.kind {
        case .managed:
            let result = try await run("start", ["/unix", unixPath.path] + args, timeout: .seconds(60))
            if !result.succeeded {
                throw LauncherError("Start fehlgeschlagen: \(unixPath.lastPathComponent)", detail: Self.tail(result.output))
            }
        case .crossOver:
            // CrossOver's wrapper detaches by itself.
            let windowsPath = SteamLibrary(bottle: bottle).windowsPath(forMacPath: unixPath)
            try ProcessRunner.spawn(engine.wineBinary, arguments: arguments(program: windowsPath, args), environment: environment, logFile: logFile)
        }
    }

    /// Imports registry edits (via a UTF-16 `.reg` file inside the prefix).
    public func importRegistry(_ file: RegistryFile) async throws {
        guard !file.isEmpty else { return }
        let temp = bottle.driveC.appending(path: "windows/temp", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        let name = "mgl-\(UUID().uuidString).reg"
        let url = temp.appending(path: name)
        try file.data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let result = try await run("reg", ["import", #"C:\windows\temp\"# + name], timeout: .seconds(120))
        guard result.succeeded else {
            throw LauncherError("Registry-Einstellungen konnten nicht übernommen werden.", detail: Self.tail(result.output))
        }
    }

    /// Whether the bottle's wineserver is running.
    public func isRunning() async -> Bool {
        guard engine.kind == .managed else { return !ProcessList.wineProcesses(inPrefix: bottle.url).isEmpty }
        let result = try? await ProcessRunner.run(engine.wineserverBinary, arguments: ["-k0"], environment: ["WINEPREFIX": bottle.url.path], timeout: .seconds(10))
        return result?.succeeded ?? false
    }

    /// Waits until every process in the bottle has exited.
    public func waitForExit(timeout: Duration = .seconds(300)) async {
        guard engine.kind == .managed else { return }
        _ = try? await ProcessRunner.run(engine.wineserverBinary, arguments: ["-w"], environment: ["WINEPREFIX": bottle.url.path], timeout: timeout)
    }

    /// Kills every process in the bottle (Steam and games).
    public func killAll() async {
        Log.wine.info("[\(bottle.name, privacy: .public)] wineserver -k")
        switch engine.kind {
        case .managed:
            _ = try? await ProcessRunner.run(engine.wineserverBinary, arguments: ["-k"], environment: ["WINEPREFIX": bottle.url.path], timeout: .seconds(15))
        case .crossOver:
            // CrossOver exports WINEPREFIX to its processes, so they can be found and terminated directly.
            await GameMonitor.terminate(ProcessList.wineProcesses(inPrefix: bottle.url))
        }
    }

    func appendToLog(_ line: String) {
        guard let handle = ProcessRunner.openForAppending(logFile) else { return }
        let stamp = Date.now.formatted(.iso8601)
        try? handle.write(contentsOf: Data("\n[\(stamp)] \(line)\n".utf8))
        try? handle.close()
    }

    static func tail(_ output: String, lines: Int = 12) -> String {
        output.split(separator: "\n").suffix(lines).joined(separator: "\n")
    }
}
