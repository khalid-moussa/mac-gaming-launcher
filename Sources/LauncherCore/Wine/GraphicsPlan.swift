import CryptoKit
import Foundation

/// Decides and deploys graphics translation per executable.
///
/// The Steam client (Chromium) only renders on DXVK, so DXVK's native DLLs live in the prefix's `system32` and the
/// Steam executables are pinned to them via `AppDefaults` registry overrides. Games use the bottle's backend:
/// - D3DMetal: Wine builtins (Apple's forwarders deployed into the runtime) — overrides reset to `b`.
/// - DXMT: DXMT's DLLs are placed next to the game's executables (app folder wins over system32).
/// - DXVK: the system32 copies.
/// - WineD3D: Wine builtins (not offered while D3DMetal is deployed, because Apple's forwarders replace them).
///
/// With D3DMetal deployed, Apple's forwarders are the runtime's builtins. Non-D3DMetal games therefore must not fall
/// back to them: NVAPI/NGX are hidden (else games enable DLSS and load Apple's nvngx without a D3DMetal device), and
/// `d3d10`/`dxgi` resolve to Wine's originals, patched to load as native from system32.
public struct GraphicsPlan: Sendable {
    public static let steamExecutables = ["steam.exe", "steamwebhelper.exe", "steamservice.exe", "gameoverlayui64.exe", "gameoverlayui.exe"]
    /// Chromium probes for an NVIDIA GPU; answering makes it load D3DMetal and crash.
    static let chromiumHelpers: Set<String> = ["steamwebhelper.exe", "steamservice.exe", "gameoverlayui64.exe", "gameoverlayui.exe"]
    static let managedDLLs = ["d3d9", "d3d10", "d3d10core", "d3d11", "d3d12", "dxgi", "winemetal", "nvapi", "nvapi64", "nvngx"]
    /// Wine DLLs that Apple's forwarders replace and that DXVK/DXMT need in their original form.
    static let patchedOriginals = ["dxgi.dll", "d3d10.dll"]
    static let dxmtGameDLLs = ["d3d11.dll", "d3d10core.dll", "dxgi.dll"]
    static let builtinMarker = Array("Wine builtin DLL".utf8)
    /// First 16 bytes of the standard MS-DOS stub, replacing the builtin marker to make a Wine DLL load as native.
    static let dosStub: [UInt8] = [0x0E, 0x1F, 0xBA, 0x0E, 0x00, 0xB4, 0x09, 0xCD, 0x21, 0xB8, 0x01, 0x4C, 0xCD, 0x21, 0x54, 0x68]

    public let engine: Engine
    public let bottle: Bottle
    public let paths: LauncherPaths

    public init(engine: Engine, bottle: Bottle, paths: LauncherPaths) {
        self.engine = engine
        self.bottle = bottle
        self.paths = paths
    }

    /// Resolves `.automatic` against what the engine provides.
    public static func gameBackend(for requested: GraphicsBackend, engine: Engine) -> GraphicsBackend {
        let available = engine.availableBackends
        switch requested {
        case .automatic:
            if engine.d3dMetal != nil { return .d3dMetal }
            if available.contains(.dxmt) { return .dxmt }
            if available.contains(.dxvk) { return .dxvk }
            return .wined3d
        default:
            return available.contains(requested) ? requested : gameBackend(for: .automatic, engine: engine)
        }
    }

    public var effectiveGameBackend: GraphicsBackend { Self.gameBackend(for: bottle.settings.graphics, engine: engine) }

    var system32: URL { bottle.driveC.appending(path: "windows/system32", directoryHint: .isDirectory) }
    var syswow64: URL { bottle.driveC.appending(path: "windows/syswow64", directoryHint: .isDirectory) }
    var wineLib: URL { engine.wineBinary.deletingLastPathComponent().deletingLastPathComponent().appending(path: "lib/wine", directoryHint: .isDirectory) }
    var dxmtRecordFile: URL { bottle.url.appending(path: ".mgl-dxmt-copies.json") }

    // MARK: - Registry overrides

    /// Override strings for one executable, by backend.
    static func overrides(for backend: GraphicsBackend, d3dMetalDeployed: Bool) -> [String: String?] {
        var values: [String: String?] = Dictionary(uniqueKeysWithValues: managedDLLs.map { ($0, String?.none) })
        // D3D9 always runs on Wine's builtin (the runtime's DXVK ships no d3d9.dll; D3DMetal has no D3D9).
        switch backend {
        case .dxvk, .dxmt:
            for dll in ["dxgi", "d3d10core", "d3d11"] { values[dll] = "n,b" }
            if backend == .dxmt { values["winemetal"] = "b" }
            if d3dMetalDeployed {
                values["d3d10"] = "n,b" // Wine's original from system32, not Apple's forwarder
                for dll in ["d3d12", "nvapi", "nvapi64", "nvngx"] { values[dll] = "" }
            }
        case .d3dMetal:
            for dll in ["dxgi", "d3d10", "d3d10core", "d3d11", "d3d12"] { values[dll] = "b" }
        case .wined3d, .automatic:
            for dll in ["dxgi", "d3d10", "d3d10core", "d3d11", "d3d12"] { values[dll] = "b" }
        }
        return values
    }

    /// Registry edits for the Steam client and the given game executables.
    public func registry(gameExecutables: Set<String>) -> RegistryFile {
        var file = RegistryFile()
        let deployed = engine.d3dMetal != nil
        func apply(_ exe: String, _ values: [String: String?], extra: [String: String] = [:]) {
            let key = #"HKEY_CURRENT_USER\Software\Wine\AppDefaults\"# + exe + #"\DllOverrides"#
            for name in values.keys.sorted() {
                if let value = values[name] ?? nil { file.set(key, name, .string(value)) } else { file.set(key, name, .delete) }
            }
            for (name, value) in extra.sorted(by: { $0.key < $1.key }) { file.set(key, name, .string(value)) }
        }
        for exe in Self.steamExecutables {
            let extra = Self.chromiumHelpers.contains(exe) ? ["nvapi": "", "nvapi64": "", "nvngx": ""] : [:]
            apply(exe, Self.overrides(for: .dxvk, d3dMetalDeployed: deployed), extra: extra)
        }
        let backend = effectiveGameBackend
        for exe in gameExecutables.sorted() where !Self.steamExecutables.contains(exe) {
            apply(exe, Self.overrides(for: backend, d3dMetalDeployed: deployed))
        }
        // Retina / HiDPI for the Mac driver.
        file.set(#"HKEY_CURRENT_USER\Software\Wine\Mac Driver"#, "RetinaMode", .string(bottle.settings.retina ? "y" : "n"))
        return file
    }

    // MARK: - File deployment

    /// Puts DXVK into the prefix for the Steam client (idempotent; run before every Steam start).
    public func deployClientDLLs(fileManager: FileManager = .default) throws {
        guard engine.kind == .managed else { return }
        if let dxvk = engine.dxvkFolder {
            // dxgi is handled by fixUpBuiltins (DXVK's 32-bit dxgi would be replaced right away).
            try copyDLLs(from: dxvk.appending(path: "x64"), to: system32, except: ["dxgi.dll"], fileManager: fileManager)
            try copyDLLs(from: dxvk.appending(path: "x32"), to: syswow64, except: ["dxgi.dll"], fileManager: fileManager)
        }
        try fixUpBuiltins(fileManager: fileManager)
        if effectiveGameBackend == .dxmt, let dxmt = engine.dxmtFolder {
            // winemetal stays in system32; the D3D DLLs go next to the games.
            for (arch, folder) in [("x64", system32), ("x32", syswow64)] {
                let source = dxmt.appending(path: "\(arch)/winemetal.dll")
                if fileManager.fileExists(atPath: source.path), fileManager.fileExists(atPath: folder.path) {
                    try replace(folder.appending(path: "winemetal.dll"), with: source, fileManager: fileManager)
                }
            }
        }
    }

    /// DXVK-macOS ships no 64-bit dxgi.dll. Pairing its d3d11 with a foreign dxgi breaks Chromium, so system32 gets
    /// Wine's own dxgi: the builtin, or — when Apple's forwarders replaced the builtins — Wine's original dxgi and
    /// d3d10 patched to load as native DLLs (see `patchedOriginals`).
    func fixUpBuiltins(fileManager: FileManager) throws {
        for name in Self.patchedOriginals {
            let original = paths.d3dMetalStore.appending(path: "originals/\(name)")
            let target = system32.appending(path: name)
            if engine.d3dMetal != nil, fileManager.fileExists(atPath: original.path) {
                try writeIfChanged(Data(Self.patchedAsNative(try [UInt8](Data(contentsOf: original)))), to: target)
            } else if name == "dxgi.dll" {
                let builtin = wineLib.appending(path: "x86_64-windows/dxgi.dll")
                if fileManager.fileExists(atPath: builtin.path) {
                    try replace(target, with: builtin, fileManager: fileManager)
                }
            }
        }
        let builtin32 = wineLib.appending(path: "i386-windows/dxgi.dll")
        if fileManager.fileExists(atPath: builtin32.path), fileManager.fileExists(atPath: syswow64.path) {
            try replace(syswow64.appending(path: "dxgi.dll"), with: builtin32, fileManager: fileManager)
        }
    }

    /// Places DXMT next to each game executable folder (only when the game backend is DXMT) and removes copies that
    /// are no longer wanted. The record stores the SHA-256 of every copy, so files the game (or a mod such as ReShade)
    /// put there are never overwritten or deleted. Failures in one folder (read-only, unmounted volume) are logged and
    /// skipped; the record is always saved.
    public func syncDXMTGameFolders(games: [(installFolder: URL, executables: [URL])], fileManager: FileManager = .default) {
        var record = loadDXMTRecord()
        defer {
            if let data = try? JSONEncoder().encode(record) { try? data.write(to: dxmtRecordFile, options: .atomic) }
        }
        func isOurs(_ path: String) -> Bool {
            guard let expected = record[path] else { return false }
            guard Self.isSHA256(expected) else { return true } // record from an older version: path-only
            return (try? Self.sha256(of: URL(filePath: path))) == expected
        }
        let wantDXMT = engine.kind == .managed && effectiveGameBackend == .dxmt && engine.dxmtFolder != nil
        var wanted = Set<String>()

        if wantDXMT, let dxmt = engine.dxmtFolder {
            for game in games {
                let byFolder = Dictionary(grouping: game.executables) { $0.deletingLastPathComponent().standardizedFileURL }
                for (folder, executables) in byFolder {
                    // A folder can hold only one architecture's DLLs; prefer x64 if both are present.
                    let machines = executables.map { Self.peMachine(of: $0) }
                    let arch = machines.contains(.i386) && !machines.contains(.amd64) ? "x32" : "x64"
                    for dll in Self.dxmtGameDLLs {
                        let source = dxmt.appending(path: "\(arch)/\(dll)")
                        let target = folder.appending(path: dll)
                        guard fileManager.fileExists(atPath: source.path) else { continue }
                        if fileManager.fileExists(atPath: target.path), !isOurs(target.path) {
                            record[target.path] = nil // the game's own DLL
                            continue
                        }
                        wanted.insert(target.path)
                        do {
                            try replace(target, with: source, fileManager: fileManager)
                            record[target.path] = try Self.sha256(of: target)
                        } catch {
                            Log.wine.error("DXMT nach \(target.path, privacy: .public) kopieren fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
                        }
                    }
                }
            }
        }
        // Remove our copies that are no longer wanted. Keep the entry while the file can't be reached
        // (e.g. external library unmounted), so it is cleaned up once it is back.
        for path in record.keys where !wanted.contains(path) {
            if !fileManager.fileExists(atPath: path) {
                if fileManager.fileExists(atPath: URL(filePath: path).deletingLastPathComponent().path) { record[path] = nil }
                continue
            }
            guard isOurs(path) else { record[path] = nil; continue }
            if (try? fileManager.removeItem(atPath: path)) != nil { record[path] = nil }
        }
    }

    func loadDXMTRecord() -> [String: String] {
        guard let data = try? Data(contentsOf: dxmtRecordFile) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    static func isSHA256(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy(\.isHexDigit)
    }

    static func sha256(of url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url, options: .mappedIfSafe)).map { String(format: "%02x", $0) }.joined()
    }

    /// Replaces Wine's "builtin" marker with a DOS stub so the DLL loads as a native one.
    static func patchedAsNative(_ bytes: [UInt8]) -> [UInt8] {
        var bytes = bytes
        if bytes.count > 0x50, Array(bytes[0x40..<0x50]) == builtinMarker {
            bytes.replaceSubrange(0x40..<0x50, with: dosStub)
        }
        return bytes
    }

    // MARK: - Helpers

    enum Machine { case amd64, i386, unknown }

    static func peMachine(of url: URL?) -> Machine {
        guard let url, let handle = try? FileHandle(forReadingFrom: url) else { return .unknown }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 0x40), header.count == 0x40 else { return .unknown }
        let offset = Int(header[0x3C]) | Int(header[0x3D]) << 8 | Int(header[0x3E]) << 16 | Int(header[0x3F]) << 24
        guard (try? handle.seek(toOffset: UInt64(offset))) != nil, let pe = try? handle.read(upToCount: 6), pe.count == 6,
              pe[0] == 0x50, pe[1] == 0x45 else { return .unknown }
        switch UInt16(pe[4]) | UInt16(pe[5]) << 8 {
        case 0x8664: return .amd64
        case 0x014C: return .i386
        default: return .unknown
        }
    }

    private func copyDLLs(from source: URL, to destination: URL, except: Set<String> = [], fileManager: FileManager) throws {
        guard fileManager.fileExists(atPath: source.path), fileManager.fileExists(atPath: destination.path) else { return }
        for dll in try fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
        where dll.pathExtension.lowercased() == "dll" && !except.contains(dll.lastPathComponent.lowercased()) {
            try replace(destination.appending(path: dll.lastPathComponent), with: dll, fileManager: fileManager)
        }
    }

    private func replace(_ target: URL, with source: URL, fileManager: FileManager) throws {
        if fileManager.fileExists(atPath: target.path) || (try? fileManager.destinationOfSymbolicLink(atPath: target.path)) != nil {
            if fileManager.contentsEqual(atPath: target.path, andPath: source.path) { return }
            try fileManager.removeItem(at: target)
        }
        try fileManager.copyItem(at: source, to: target)
    }

    private func writeIfChanged(_ data: Data, to url: URL) throws {
        if let existing = try? Data(contentsOf: url), existing == data { return }
        try? FileManager.default.removeItem(at: url)
        try data.write(to: url)
    }
}
