import Darwin
import Foundation

/// A running process as seen by the kernel.
public struct RunningProcess: Sendable, Hashable {
    public let pid: pid_t
    /// `argv[0]`. Wine rewrites it to the Windows image path, e.g. `C:\Program Files (x86)\Steam\steam.exe`.
    public let commandName: String
    public let arguments: [String]
    /// `WINEPREFIX` from the process environment (only readable for the current user's processes).
    public let winePrefix: String?

    public init(pid: pid_t, commandName: String, arguments: [String], winePrefix: String?) {
        self.pid = pid
        self.commandName = commandName
        self.arguments = arguments
        self.winePrefix = winePrefix
    }

    /// Lower-cased Windows image name (`steam.exe`), if `argv[0]` looks like a Windows path.
    public var windowsImageName: String? {
        let normalized = commandName.replacingOccurrences(of: "/", with: "\\")
        guard normalized.lowercased().hasSuffix(".exe") else { return nil }
        return normalized.split(separator: "\\").last.map { $0.lowercased() }
    }

    /// Lower-cased, backslash-normalized Windows path of the image.
    public var normalizedWindowsPath: String {
        commandName.replacingOccurrences(of: "/", with: "\\").lowercased()
    }
}

/// Enumerates the current user's processes via `sysctl` (no `ps` subprocess).
public enum ProcessList {
    public static func current() -> [RunningProcess] {
        allPIDs().compactMap(processArguments(pid:))
    }

    /// Processes belonging to a given Wine prefix.
    public static func wineProcesses(inPrefix prefix: URL, from processes: [RunningProcess]? = nil) -> [RunningProcess] {
        // Resolve symlinks on both sides: CrossOver passes the unresolved path (e.g. Bottles moved to another disk).
        let target = prefix.resolvingSymlinksInPath().standardizedFileURL.path
        return (processes ?? current()).filter { process in
            guard let winePrefix = process.winePrefix else { return false }
            return URL(filePath: winePrefix).resolvingSymlinksInPath().standardizedFileURL.path == target
        }
    }

    static func allPIDs() -> [pid_t] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_UID, Int32(getuid())]
        var size = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0, size > 0 else { return [] }
        // Allow for processes started between the two calls.
        size += 16 * MemoryLayout<kinfo_proc>.stride
        let count = size / MemoryLayout<kinfo_proc>.stride
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: count)
        guard sysctl(&mib, UInt32(mib.count), &procs, &size, nil, 0) == 0 else { return [] }
        let actual = size / MemoryLayout<kinfo_proc>.stride
        return procs.prefix(actual).map { $0.kp_proc.p_pid }.filter { $0 > 0 }
    }

    /// Reads argv and environment via `KERN_PROCARGS2`.
    /// Layout: `int argc`, exec path, NUL padding, `argc` NUL-terminated args, then NUL-terminated env strings.
    static func processArguments(pid: pid_t) -> RunningProcess? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        return parseProcArgs(Array(buffer.prefix(size)), pid: pid)
    }

    /// Separated for testing.
    static func parseProcArgs(_ buffer: [UInt8], pid: pid_t) -> RunningProcess? {
        guard buffer.count > 4 else { return nil }
        let argc = buffer.withUnsafeBytes { Int($0.loadUnaligned(as: Int32.self)) }
        var index = 4
        // Skip exec path.
        while index < buffer.count, buffer[index] != 0 { index += 1 }
        // Skip NUL padding.
        while index < buffer.count, buffer[index] == 0 { index += 1 }

        func nextString() -> String? {
            guard index < buffer.count else { return nil }
            let start = index
            while index < buffer.count, buffer[index] != 0 { index += 1 }
            let string = String(decoding: buffer[start..<index], as: UTF8.self)
            index += 1
            return string
        }

        // Wine rewrites argv in place (argv[0] becomes the Windows image path) and pads the freed tail with NUL
        // bytes, while the kernel keeps the original argc. So arguments may contain empty strings, and the
        // environment starts after an arbitrary run of NULs — keep scanning past empty strings.
        var arguments: [String] = []
        for _ in 0..<max(argc, 0) {
            guard let argument = nextString() else { break }
            arguments.append(argument)
        }
        arguments.removeAll { $0.isEmpty }
        guard let commandName = arguments.first else { return nil }

        var winePrefix: String?
        while winePrefix == nil, let entry = nextString() {
            if entry.hasPrefix("WINEPREFIX=") { winePrefix = String(entry.dropFirst("WINEPREFIX=".count)) }
        }
        return RunningProcess(pid: pid, commandName: commandName, arguments: arguments, winePrefix: winePrefix)
    }
}
