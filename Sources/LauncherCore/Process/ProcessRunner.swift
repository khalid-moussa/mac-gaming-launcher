import Foundation

/// Result of a finished child process.
public struct ProcessResult: Sendable {
    public let status: Int32
    public let output: String
    public var succeeded: Bool { status == 0 }
}

/// Spawns child processes. Output never goes to an unread pipe (that blocks Wine once the buffer fills):
/// it is either collected by a reader task or appended to a log file.
public enum ProcessRunner {
    /// Runs a process to completion and returns its combined output (stdout + stderr).
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

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let logHandle = logFile.flatMap(openForAppending)

        // Drain the pipe continuously on a background reader so the child never blocks on write.
        let reader = Task.detached { () -> Data in
            var collected = Data()
            let handle = pipe.fileHandleForReading
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                try? logHandle?.write(contentsOf: chunk)
                // Keep at most the last 256 KB in memory.
                collected.append(chunk)
                if collected.count > 512_000 { collected.removeFirst(collected.count - 256_000) }
            }
            return collected
        }

        let status: Int32 = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { finished in
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
                    Task.detached {
                        try? await Task.sleep(for: timeout)
                        if process.isRunning {
                            Log.wine.warning("Timeout nach \(timeout) – beende \(executable.lastPathComponent, privacy: .public)")
                            process.terminate()
                        }
                    }
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }

        // The write end is closed once the child (and anything that inherited it) exits.
        try? pipe.fileHandleForWriting.close()
        let data = await reader.value
        try? logHandle?.close()
        return ProcessResult(status: status, output: String(decoding: data, as: UTF8.self))
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

    static func openForAppending(_ url: URL) -> FileHandle? {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fileManager.fileExists(atPath: url.path) {
            fileManager.createFile(atPath: url.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return nil }
        _ = try? handle.seekToEnd()
        return handle
    }
}
