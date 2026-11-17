import Foundation

/// Where a Wine engine comes from.
public enum EngineKind: String, Codable, Sendable, CaseIterable {
    /// The runtime this launcher downloads and manages itself (Wine 11 built from CrossOver sources, DXMT, DXVK).
    case managed
    /// CodeWeavers CrossOver (commercial). Only used for CrossOver's own bottles.
    case crossOver

    public var displayName: String {
        switch self {
        case .managed: "Launcher-Runtime"
        case .crossOver: "CrossOver"
        }
    }
}

/// Information about an imported Apple D3DMetal (Game Porting Toolkit) payload.
public struct D3DMetalInfo: Sendable, Hashable, Codable {
    /// Framework version, e.g. `4.0b3`.
    public let version: String

    public init(version: String) { self.version = version }

    /// D3DMetal 4 (GPTK 4) — requires macOS 27 and enables the Metal 4 code path.
    public var isMetal4: Bool { version.hasPrefix("4") || (Int(version.prefix { $0.isNumber }) ?? 0) >= 4 }
}

/// A Wine installation that can run bottles.
public struct Engine: Identifiable, Sendable, Hashable {
    public var id: String { kind.rawValue + ":" + wineBinary.path }
    public let kind: EngineKind
    public let version: String
    /// The `wine` launcher (for CrossOver: CrossOver's `wine` wrapper that understands `--bottle`).
    public let wineBinary: URL
    public let wineserverBinary: URL
    /// Folder with native DXVK DLLs (`x64`, `x32`), if the engine ships them.
    public let dxvkFolder: URL?
    /// Folder with DXMT DLLs (`x64`, `x32`), if the engine ships them.
    public let dxmtFolder: URL?
    /// Present when Apple's D3DMetal is installed into this engine.
    public let d3dMetal: D3DMetalInfo?
    /// Whether the build supports Mach-semaphore synchronisation (`WINEMSYNC`).
    public let supportsMSync: Bool
    public let appBundle: URL?

    public init(
        kind: EngineKind,
        version: String,
        wineBinary: URL,
        wineserverBinary: URL,
        dxvkFolder: URL? = nil,
        dxmtFolder: URL? = nil,
        d3dMetal: D3DMetalInfo? = nil,
        supportsMSync: Bool = true,
        appBundle: URL? = nil
    ) {
        self.kind = kind
        self.version = version
        self.wineBinary = wineBinary
        self.wineserverBinary = wineserverBinary
        self.dxvkFolder = dxvkFolder
        self.dxmtFolder = dxmtFolder
        self.d3dMetal = d3dMetal
        self.supportsMSync = supportsMSync
        self.appBundle = appBundle
    }

    public var displayName: String { "\(kind.displayName) \(version)" }

    /// Backends this engine can actually provide.
    public var availableBackends: [GraphicsBackend] {
        var result: [GraphicsBackend] = [.automatic]
        if d3dMetal != nil || kind == .crossOver { result.append(.d3dMetal) }
        if dxmtFolder != nil || kind == .crossOver { result.append(.dxmt) }
        if dxvkFolder != nil || kind == .crossOver { result.append(.dxvk) }
        // With D3DMetal deployed, Wine's builtin D3D DLLs are Apple's forwarders, so WineD3D is not available.
        if d3dMetal == nil || kind == .crossOver { result.append(.wined3d) }
        return result
    }
}
