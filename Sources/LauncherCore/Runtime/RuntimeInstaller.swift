import CryptoKit
import Foundation

/// A downloadable runtime release (Wine 11 built from CrossOver sources + DXMT + DXVK),
/// published by the actively maintained Whisky fork (https://github.com/frankea/Whisky).
public struct RuntimeRelease: Sendable, Equatable {
    public let version: String
    public let sha256: String?
    public let dxmtVersion: String?
    public let dxvkVersion: String?
    public let gptkCapable: Bool
    public let downloadURL: URL
}

/// Contents of `Libraries/WhiskyWineVersion.plist` (and of the update channel plist).
struct RuntimeVersionFile: Decodable {
    struct Version: Decodable { let major: Int; let minor: Int; let patch: Int }
    let version: Version
    let sha256: String?
    let dxmtVersion: String?
    let dxvkVersion: String?
    let gptkCapable: Bool?

    var versionString: String { "\(version.major).\(version.minor).\(version.patch)" }
}

/// Download progress phases reported to the UI.
public enum RuntimeInstallPhase: Sendable, Equatable {
    case downloading(fraction: Double, bytes: Int64, total: Int64)
    case verifying
    case extracting
    case finishing
}

/// Downloads, verifies and installs the managed runtime into `LauncherPaths.librariesFolder`.
public struct RuntimeInstaller: Sendable {
    /// Update channel of the runtime (contains version + SHA-256).
    public static let channelURL = URL(string: "https://frankea.github.io/Whisky/WhiskyWineVersion-v4.plist")!

    /// Known-good release used if the channel is unreachable.
    public static let fallbackRelease = RuntimeRelease(
        version: "4.8.3",
        sha256: "08ffabd7b7c352470faee2b1d51061b341316e401439ca805c5302acc2fb8818",
        dxmtVersion: "0.80",
        dxvkVersion: "1.10.3",
        gptkCapable: true,
        downloadURL: downloadURL(forVersion: "4.8.3")
    )

    public static func downloadURL(forVersion version: String) -> URL {
        URL(string: "https://github.com/frankea/Whisky/releases/download/v\(version)/Libraries.tar.gz")!
    }

    public let paths: LauncherPaths

    public init(paths: LauncherPaths) {
        self.paths = paths
    }

    // MARK: - Status

    public var versionFile: URL { paths.librariesFolder.appending(path: "WhiskyWineVersion.plist") }

    /// Installed runtime version, or `nil` if not installed or incomplete.
    public func installedVersion(fileManager: FileManager = .default) -> String? {
        guard Self.isComplete(libraries: paths.librariesFolder, fileManager: fileManager),
              let data = try? Data(contentsOf: versionFile),
              let file = try? PropertyListDecoder().decode(RuntimeVersionFile.self, from: data)
        else { return nil }
        return file.versionString
    }

    public func isGPTKCapable() -> Bool {
        guard let data = try? Data(contentsOf: versionFile),
              let file = try? PropertyListDecoder().decode(RuntimeVersionFile.self, from: data)
        else { return false }
        return file.gptkCapable ?? false
    }

    static func isComplete(libraries: URL, fileManager: FileManager) -> Bool {
        let bin = libraries.appending(path: "Wine/bin")
        let hasWine = ["wine64", "wine"].contains { fileManager.isExecutableFile(atPath: bin.appending(path: $0).path) }
        return hasWine
            && fileManager.fileExists(atPath: bin.appending(path: "wineserver").path)
            && fileManager.fileExists(atPath: libraries.appending(path: "WhiskyWineVersion.plist").path)
    }

    // MARK: - Update channel

    public func fetchLatestRelease(session: URLSession = .shared) async throws -> RuntimeRelease {
        var request = URLRequest(url: Self.channelURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("MacGamingLauncher", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw LauncherError("Runtime-Versionsinformationen konnten nicht geladen werden.")
        }
        let file = try PropertyListDecoder().decode(RuntimeVersionFile.self, from: data)
        let version = file.versionString
        return RuntimeRelease(
            version: version,
            sha256: file.sha256,
            dxmtVersion: file.dxmtVersion,
            dxvkVersion: file.dxvkVersion,
            gptkCapable: file.gptkCapable ?? false,
            downloadURL: Self.downloadURL(forVersion: version)
        )
    }

    /// Whether `candidate` is newer than `installed` (semantic `major.minor.patch`).
    public static func isNewer(_ candidate: String, than installed: String) -> Bool {
        let lhs = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let rhs = installed.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(lhs.count, rhs.count) {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left != right { return left > right }
        }
        return false
    }

    // MARK: - Install

    /// Downloads and installs `release`. Replaces an existing runtime atomically; an imported D3DMetal payload is
    /// re-deployed afterwards by the caller (see `D3DMetalInstaller.deployIfImported`).
    public func install(
        _ release: RuntimeRelease,
        session: URLSession = .shared,
        progress: @escaping @Sendable (RuntimeInstallPhase) -> Void
    ) async throws {
        let fileManager = FileManager.default
        try paths.createOwnedFolders(fileManager: fileManager)
        try Self.ensureFreeSpace(at: paths.root, bytes: 3_000_000_000)

        // 1. Download
        let archive = paths.downloadsFolder.appending(path: "Libraries-\(release.version).tar.gz")
        try? fileManager.removeItem(at: archive)
        Log.runtime.info("Lade Runtime \(release.version, privacy: .public) von \(release.downloadURL, privacy: .public)")
        let delegate = DownloadProgressDelegate(progress: progress)
        let (temporary, response) = try await session.download(from: release.downloadURL, delegate: delegate)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw LauncherError("Download der Runtime fehlgeschlagen.", detail: "HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        try fileManager.moveItem(at: temporary, to: archive)
        defer { try? fileManager.removeItem(at: archive) }

        // 2. Verify
        progress(.verifying)
        if let expected = release.sha256?.lowercased() {
            let actual = try await Self.sha256(of: archive)
            guard actual == expected else {
                throw LauncherError("Die heruntergeladene Runtime ist beschädigt (Prüfsumme stimmt nicht).", detail: "erwartet \(expected), erhalten \(actual)")
            }
        }

        // 3. Extract into staging
        progress(.extracting)
        let staging = paths.root.appending(path: "Runtime.staging", directoryHint: .isDirectory)
        try? fileManager.removeItem(at: staging)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }
        let tar = try await ProcessRunner.run(URL(filePath: "/usr/bin/tar"), arguments: ["-xzf", archive.path, "-C", staging.path])
        guard tar.succeeded else {
            throw LauncherError("Entpacken der Runtime fehlgeschlagen.", detail: tar.output)
        }
        let stagedLibraries = staging.appending(path: "Libraries", directoryHint: .isDirectory)
        guard Self.isComplete(libraries: stagedLibraries, fileManager: fileManager) else {
            throw LauncherError("Die Runtime ist unvollständig (Wine-Binärdateien fehlen).")
        }

        // 4. Swap into place
        progress(.finishing)
        _ = try? await ProcessRunner.run(URL(filePath: "/usr/bin/xattr"), arguments: ["-dr", "com.apple.quarantine", stagedLibraries.path])
        try fileManager.createDirectory(at: paths.runtimeFolder, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: paths.librariesFolder.path) {
            let old = paths.runtimeFolder.appending(path: "Libraries.old-\(UUID().uuidString)")
            try fileManager.moveItem(at: paths.librariesFolder, to: old)
            try? fileManager.removeItem(at: old)
        }
        try fileManager.moveItem(at: stagedLibraries, to: paths.librariesFolder)
        Log.runtime.info("Runtime \(release.version, privacy: .public) installiert")
    }

    public func uninstall() throws {
        try FileManager.default.removeItem(at: paths.runtimeFolder)
    }

    // MARK: - Helpers

    static func sha256(of file: URL) async throws -> String {
        try await Task.detached(priority: .utility) {
            let handle = try FileHandle(forReadingFrom: file)
            defer { try? handle.close() }
            var hasher = SHA256()
            while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty {
                hasher.update(data: chunk)
            }
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        }.value
    }

    static func ensureFreeSpace(at url: URL, bytes: Int64) throws {
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let available = values?.volumeAvailableCapacityForImportantUsage, available < bytes {
            let formatter = ByteCountFormatter()
            throw LauncherError("Nicht genug freier Speicherplatz.", detail: "Benötigt: \(formatter.string(fromByteCount: bytes)), frei: \(formatter.string(fromByteCount: available))")
        }
    }
}

/// Reports download progress from `URLSession.download(from:delegate:)`.
final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate, Sendable {
    let progress: @Sendable (RuntimeInstallPhase) -> Void

    init(progress: @escaping @Sendable (RuntimeInstallPhase) -> Void) {
        self.progress = progress
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let fraction = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0
        progress(.downloading(fraction: fraction, bytes: totalBytesWritten, total: totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Handled by the async `download(from:delegate:)` call.
    }
}
