import Foundation

/// Result of a finished child process.
public struct ProcessResult: Sendable {
    public let status: Int32
    public let output: String
    public var succeeded: Bool { status == 0 }
}

/// Spawns child processes.
///
/// Output always goes to a file, never to a pipe: Wine forks `wineserver` and Windows programs (Steam) that inherit
/// stdout/stderr and outlive the command. With a pipe, the reader would never see EOF (hang), and an unread pipe
/// blocks writers once its buffer fills (frozen game). A file has neither problem.
public enum ProcessRunner {
    /// Runs a process to completion and returns its combined output (stdout + stderr), read back from the log.
    /// The process is terminated if the surrounding task is cancelled or `timeout` elapses.
    public static func run(
        _ executable: URL,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        currentDirectory: URL? = nil,
        logFile: URL? = nil,
        timeout: Duration? = nil
    ) async throws -> ProcessResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let environment { process.environment = environment }
        if let currentDirectory { process.currentDirectoryURL = currentDirectory }
        process.standardInput = FileHandle.nullDevice

        let temporary = logFile == nil
        let outputFile = logFile ?? FileManager.default.temporaryDirectory.appending(path: "mgl-\(UUID().uuidString).log")
        guard let handle = openForAppending(outputFile) else {
            throw LauncherError("Logdatei konnte nicht geöffnet werden.", detail: outputFile.path)
        }
        let startOffset = (try? handle.offset()) ?? 0
        process.standardOutput = handle
        process.standardError = handle
        defer {
            try? handle.close()
            if temporary { try? FileManager.default.removeItem(at: outputFile) }
        }

        let timeoutTask = LockedBox<Task<Void, Never>?>(nil)
        let status: Int32 = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { finished in
                    timeoutTask.value?.cancel()
                    continuation.resume(returning: finished.terminationStatus)
                }
                do {
                    try process.run()
                } catch {
                    process.terminationHandler = nil
                    continuation.resume(throwing: error)
                    return
                }
                if let timeout {
                    timeoutTask.value = Task.detached {
                        try? await Task.sleep(for: timeout)
                        guard !Task.isCancelled, process.isRunning else { return }
                        Log.wine.warning("Timeout nach \(timeout) – beende \(executable.lastPathComponent, privacy: .public)")
                        process.terminate()
                    }
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }

        return ProcessResult(status: status, output: readTail(of: outputFile, from: startOffset))
    }

    /// Reads what was appended to `file` since `offset` (at most the last 256 KB).
    static func readTail(of file: URL, from offset: UInt64, limit: UInt64 = 256_000) -> String {
        guard let reader = try? FileHandle(forReadingFrom: file) else { return "" }
        defer { try? reader.close() }
        let end = (try? reader.seekToEnd()) ?? offset
        let start = end > offset + limit ? end - limit : offset
        try? reader.seek(toOffset: start)
        let data = (try? reader.read(upToCount: Int(end - start))) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    /// Starts a long-running process (e.g. the Steam client) without waiting. Output goes to `logFile`.
    @discardableResult
    public static func spawn(
        _ executable: URL,
        arguments: [String],
        environment: [String: String],
        currentDirectory: URL? = nil,
        logFile: URL
    ) throws -> Process {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        if let currentDirectory { process.currentDirectoryURL = currentDirectory }
        process.standardInput = FileHandle.nullDevice
        if let handle = openForAppending(logFile) {
            process.standardOutput = handle
            process.standardError = handle
        } else {
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
        }
        try process.run()
        return process
    }

    /// Opens with `O_APPEND` so every writer (we, Wine, Steam — each with its own descriptor) appends atomically
    /// instead of overwriting from a stale offset.
    static func openForAppending(_ url: URL) -> FileHandle? {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let descriptor = open(url.path, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0o644)
        guard descriptor >= 0 else { return nil }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        _ = try? handle.seekToEnd()
        return handle
    }
}
