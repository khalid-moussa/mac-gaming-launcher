import Foundation

/// Direct3D → Metal translation used for games.
public enum GraphicsBackend: String, Codable, Sendable, CaseIterable, Identifiable {
    /// D3DMetal if imported, otherwise DXMT.
    case automatic
    /// Apple D3DMetal (Game Porting Toolkit): D3D11 + D3D12, Metal 4 with GPTK 4.
    case d3dMetal
    /// DXMT: D3D11 → Metal, open source.
    case dxmt
    /// DXVK → MoltenVK → Metal. D3D9–11, widest compatibility, slower.
    case dxvk
    /// Wine's built-in OpenGL translation. Last resort.
    case wined3d

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .automatic: "Automatisch"
        case .d3dMetal: "D3DMetal (Apple GPTK)"
        case .dxmt: "DXMT"
        case .dxvk: "DXVK (MoltenVK)"
        case .wined3d: "WineD3D (OpenGL)"
        }
    }

    public var summary: String {
        switch self {
        case .automatic: "D3DMetal, falls importiert, sonst DXMT."
        case .d3dMetal: "DirectX 11/12 über Apples Metal-Übersetzung. Nötig für die meisten DX12-Spiele."
        case .dxmt: "DirectX 11 direkt auf Metal. Schnell, Open Source."
        case .dxvk: "DirectX 9–11 über Vulkan/MoltenVK. Für ältere Spiele."
        case .wined3d: "OpenGL-Fallback, nur für sehr alte Spiele."
        }
    }
}

/// Per-bottle settings. Stored as `bottle.json` inside launcher-owned bottles.
public struct BottleSettings: Codable, Sendable, Hashable {
    public var graphics: GraphicsBackend = .automatic
    /// Mach-semaphore sync (`WINEMSYNC`). Big CPU win for multi-threaded games.
    public var msync = true
    /// Let Rosetta 2 report AVX/AVX2 support (many current games require it).
    public var advertiseAVX = true
    public var metalHUD = false
    /// MetalFX upscaling for games using DLSS (needs D3DMetal).
    public var metalFX = false
    public var retina = false
    public var windowsVersion = "win10"
    /// Extra arguments for steam.exe (advanced).
    public var extraSteamArguments: [String] = []

    public init() {}

    // Tolerate missing keys so older/newer files still decode.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = BottleSettings()
        graphics = try container.decodeIfPresent(GraphicsBackend.self, forKey: .graphics) ?? defaults.graphics
        msync = try container.decodeIfPresent(Bool.self, forKey: .msync) ?? defaults.msync
        advertiseAVX = try container.decodeIfPresent(Bool.self, forKey: .advertiseAVX) ?? defaults.advertiseAVX
        metalHUD = try container.decodeIfPresent(Bool.self, forKey: .metalHUD) ?? defaults.metalHUD
        metalFX = try container.decodeIfPresent(Bool.self, forKey: .metalFX) ?? defaults.metalFX
        retina = try container.decodeIfPresent(Bool.self, forKey: .retina) ?? defaults.retina
        windowsVersion = try container.decodeIfPresent(String.self, forKey: .windowsVersion) ?? defaults.windowsVersion
        extraSteamArguments = try container.decodeIfPresent([String].self, forKey: .extraSteamArguments) ?? defaults.extraSteamArguments
    }
}

/// Who created a bottle — decides which engine runs it.
public enum BottleOwner: String, Codable, Sendable {
    case launcher
    case crossOver
}

/// A Wine prefix.
public struct Bottle: Identifiable, Sendable, Hashable {
    /// Bottles are identified by their folder; names may collide across owners.
    public var id: String { url.standardizedFileURL.path }
    public let name: String
    public let url: URL
    public let owner: BottleOwner
    public var settings: BottleSettings

    public init(name: String, url: URL, owner: BottleOwner, settings: BottleSettings = BottleSettings()) {
        self.name = name
        self.url = url
        self.owner = owner
        self.settings = settings
    }

    public var driveC: URL { url.appending(path: "drive_c", directoryHint: .isDirectory) }
    public var settingsFile: URL { url.appending(path: "bottle.json") }

    /// Engine kind required to run this bottle.
    public var engineKind: EngineKind {
        switch owner {
        case .launcher: .managed
        case .crossOver: .crossOver
        }
    }

    /// Whether `wineboot` has populated the prefix.
    public func isInitialized(fileManager: FileManager = .default) -> Bool {
        fileManager.fileExists(atPath: driveC.appending(path: "windows/system32").path)
    }
}
