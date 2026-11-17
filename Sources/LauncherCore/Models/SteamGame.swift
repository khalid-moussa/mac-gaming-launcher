import Foundation

/// An installed (or installing) Steam app found via `appmanifest_<id>.acf`.
public struct SteamGame: Identifiable, Sendable, Hashable {
    /// Unique across bottles: the same app may be installed in several bottles.
    public var id: String { "\(bottleID)#\(appID)" }
    public let appID: String
    public let name: String
    public let installDir: String
    public let sizeOnDisk: UInt64
    public let lastPlayed: Date?
    public let stateFlags: Int
    /// `.../steamapps` folder the manifest was found in (macOS path).
    public let libraryFolder: URL
    public let bottleID: String

    public init(
        appID: String,
        name: String,
        installDir: String,
        sizeOnDisk: UInt64,
        lastPlayed: Date?,
        stateFlags: Int,
        libraryFolder: URL,
        bottleID: String
    ) {
        self.appID = appID
        self.name = name
        self.installDir = installDir
        self.sizeOnDisk = sizeOnDisk
        self.lastPlayed = lastPlayed
        self.stateFlags = stateFlags
        self.libraryFolder = libraryFolder
        self.bottleID = bottleID
    }

    /// `StateFlags` bit 4 = fully installed. Anything else is downloading, updating, or broken.
    public var isFullyInstalled: Bool { stateFlags & 4 != 0 }

    public var installFolder: URL {
        libraryFolder.appending(path: "common", directoryHint: .isDirectory).appending(path: installDir, directoryHint: .isDirectory)
    }

    /// Steam CDN artwork. Works for most apps; newer apps use hashed paths and fall back to a placeholder.
    public var posterURL: URL? { Self.cdnURL(appID, "library_600x900_2x.jpg") }
    public var heroURL: URL? { Self.cdnURL(appID, "library_hero.jpg") }
    public var headerURL: URL? { Self.cdnURL(appID, "header.jpg") }
    public var storeURL: URL? { URL(string: "https://store.steampowered.com/app/\(appID)") }

    static func cdnURL(_ appID: String, _ file: String) -> URL? {
        URL(string: "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/\(appID)/\(file)")
    }
}

/// A Steam account that has logged in inside a bottle (from `config/loginusers.vdf`).
public struct SteamAccount: Sendable, Hashable, Identifiable {
    public var id: String { steamID64 }
    public let steamID64: String
    public let accountName: String
    public let personaName: String
    public let mostRecent: Bool
    public let lastLogin: Date?

    public init(steamID64: String, accountName: String, personaName: String, mostRecent: Bool, lastLogin: Date?) {
        self.steamID64 = steamID64
        self.accountName = accountName
        self.personaName = personaName
        self.mostRecent = mostRecent
        self.lastLogin = lastLogin
    }

    public var profileURL: URL? { URL(string: "https://steamcommunity.com/profiles/\(steamID64)") }
}
