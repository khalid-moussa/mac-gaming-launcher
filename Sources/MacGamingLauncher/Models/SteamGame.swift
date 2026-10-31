import Foundation

public struct SteamGame: Identifiable, Hashable, Sendable {
    public var id: String { appId }
    public let appId: String
    public let name: String
    public let installDir: String
    public let sizeOnDisk: UInt64
    public let lastPlayed: Date?
    public let bottleName: String
    public let bottlePath: URL
    public var isRunning: Bool = false

    public init(
        appId: String,
        name: String,
        installDir: String,
        sizeOnDisk: UInt64,
        lastPlayed: Date?,
        bottleName: String,
        bottlePath: URL,
        isRunning: Bool = false
    ) {
        self.appId = appId
        self.name = name
        self.installDir = installDir
        self.sizeOnDisk = sizeOnDisk
        self.lastPlayed = lastPlayed
        self.bottleName = bottleName
        self.bottlePath = bottlePath
        self.isRunning = isRunning
    }

    /// Official 600x900 2x vertical capsule poster from Steam CDN
    public var posterURL: URL? {
        URL(string: "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/\(appId)/library_600x900_2x.jpg")
    }

    /// Wide landscape hero banner from Steam CDN
    public var heroURL: URL? {
        URL(string: "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/\(appId)/library_hero.jpg")
    }

    /// Standard header image
    public var headerURL: URL? {
        URL(string: "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/\(appId)/header.jpg")
    }

    public var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(sizeOnDisk))
    }

    public var formattedLastPlayed: String {
        guard let lastPlayed = lastPlayed else { return "Noch nie gespielt" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: lastPlayed, relativeTo: Date())
    }
}
