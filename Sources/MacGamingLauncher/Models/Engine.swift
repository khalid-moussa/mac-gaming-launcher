import Foundation

public enum EngineType: String, Sendable, CaseIterable {
    case crossOver = "CrossOver (GPTK / Wine-CX)"
    case appleGPTK = "Apple Game Porting Toolkit (GPTK 2 & 4)"
    case whisky = "Whisky (GPTK)"
    case customWine = "Custom Wine / Kegworks"
}

public struct Engine: Identifiable, Hashable, Sendable {
    public var id: String { wineExecutableURL.path }
    public let name: String
    public let type: EngineType
    public let appBundleURL: URL?
    public let wineExecutableURL: URL
    public let wineServerExecutableURL: URL
    public let version: String
    public let hasD3DMetal: Bool
    public let hasMSync: Bool

    public init(
        name: String,
        type: EngineType,
        appBundleURL: URL?,
        wineExecutableURL: URL,
        wineServerExecutableURL: URL,
        version: String,
        hasD3DMetal: Bool = true,
        hasMSync: Bool = true
    ) {
        self.name = name
        self.type = type
        self.appBundleURL = appBundleURL
        self.wineExecutableURL = wineExecutableURL
        self.wineServerExecutableURL = wineServerExecutableURL
        self.version = version
        self.hasD3DMetal = hasD3DMetal
        self.hasMSync = hasMSync
    }
}
