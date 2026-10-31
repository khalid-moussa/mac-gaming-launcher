import Foundation

public struct Bottle: Identifiable, Hashable, Sendable {
    public var id: String { name }
    public let name: String
    public let path: URL
    public var msyncEnabled: Bool
    public var d3dMetalEnabled: Bool
    public var metalFxEnabled: Bool
    public var metalHudEnabled: Bool
    public var retinaEnabled: Bool
    public var isDefault: Bool
    public var wineVersion: String?

    public init(
        name: String,
        path: URL,
        msyncEnabled: Bool = true,
        d3dMetalEnabled: Bool = true,
        metalFxEnabled: Bool = false,
        metalHudEnabled: Bool = false,
        retinaEnabled: Bool = true,
        isDefault: Bool = false,
        wineVersion: String? = nil
    ) {
        self.name = name
        self.path = path
        self.msyncEnabled = msyncEnabled
        self.d3dMetalEnabled = d3dMetalEnabled
        self.metalFxEnabled = metalFxEnabled
        self.metalHudEnabled = metalHudEnabled
        self.retinaEnabled = retinaEnabled
        self.isDefault = isDefault
        self.wineVersion = wineVersion
    }

    public var steamAppsURL: URL {
        path.appendingPathComponent("drive_c/Program Files (x86)/Steam/steamapps")
    }

    public var steamExeURL: URL {
        path.appendingPathComponent("drive_c/Program Files (x86)/Steam/steam.exe")
    }

    public var hasSteamInstalled: Bool {
        FileManager.default.fileExists(atPath: steamExeURL.path)
    }
}
