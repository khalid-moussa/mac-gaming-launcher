import Foundation
import Testing
@testable import LauncherCore

/// Builds a fake bottle with a Steam install on disk.
struct BottleFixture {
    let root: URL
    let bottle: Bottle

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "mgl-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let bottleURL = root.appending(path: "Steam", directoryHint: .isDirectory)
        bottle = Bottle(name: "Steam", url: bottleURL, owner: .launcher)
        try FileManager.default.createDirectory(at: steamFolder.appending(path: "steamapps/common"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: steamFolder.appending(path: "config"), withIntermediateDirectories: true)
        try Data().write(to: steamFolder.appending(path: "steam.exe"))
        try FileManager.default.createDirectory(at: bottleURL.appending(path: "dosdevices"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: bottleURL.appending(path: "dosdevices/c:").path, withDestinationPath: "../drive_c")
    }

    var steamFolder: URL { bottle.driveC.appending(path: "Program Files (x86)/Steam", directoryHint: .isDirectory) }

    func write(_ text: String, to relative: String, in base: URL? = nil) throws {
        let url = (base ?? steamFolder).appending(path: relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    func manifest(appID: String, name: String, flags: Int = 4, installDir: String? = nil) -> String {
        """
        "AppState"
        {
            "appid" "\(appID)"
            "name" "\(name)"
            "StateFlags" "\(flags)"
            "installdir" "\(installDir ?? name)"
            "SizeOnDisk" "1000"
            "LastPlayed" "1700000000"
        }
        """
    }

    func cleanup() { try? FileManager.default.removeItem(at: root) }
}

@Suite("Steam library")
struct SteamLibraryTests {
    @Test func findsSteamAndWindowsPath() throws {
        let fixture = try BottleFixture()
        defer { fixture.cleanup() }
        let library = SteamLibrary(bottle: fixture.bottle)
        #expect(library.isSteamInstalled)
        #expect(library.steamExeWindowsPath() == #"C:\Program Files (x86)\Steam\steam.exe"#)
    }

    @Test func scansGamesAcrossLibrariesAndSkipsTools() throws {
        let fixture = try BottleFixture()
        defer { fixture.cleanup() }
        // A second library on drive D: mapped via dosdevices to a folder outside the prefix.
        let external = fixture.root.appending(path: "External", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: external.appending(path: "SteamLibrary/steamapps"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: fixture.bottle.url.appending(path: "dosdevices/d:").path, withDestinationPath: external.path)

        try fixture.write(#"""
        "libraryfolders"
        {
            "0" { "path" "C:\\Program Files (x86)\\Steam" }
            "1" { "path" "D:\\SteamLibrary" }
            "2" { "path" "E:\\Missing" }
        }
        """#, to: "config/libraryfolders.vdf")
        try fixture.write(fixture.manifest(appID: "10", name: "Zeta"), to: "steamapps/appmanifest_10.acf")
        try fixture.write(fixture.manifest(appID: "228980", name: "Steamworks Common Redistributables"), to: "steamapps/appmanifest_228980.acf")
        try fixture.write(fixture.manifest(appID: "20", name: "Alpha", flags: 1026), to: "SteamLibrary/steamapps/appmanifest_20.acf", in: external)
        try fixture.write("garbage {{{", to: "steamapps/appmanifest_30.acf")

        let library = SteamLibrary(bottle: fixture.bottle)
        #expect(library.libraryFolders().count == 2)
        let games = library.games()
        #expect(games.map(\.name) == ["Alpha", "Zeta"])
        let alpha = try #require(games.first)
        #expect(!alpha.isFullyInstalled)
        #expect(alpha.needsUpdate)
        #expect(games[1].isFullyInstalled)
        #expect(games[1].lastPlayed == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(alpha.id != games[1].id)
    }

    @Test func rejectsPathTraversal() throws {
        let fixture = try BottleFixture()
        defer { fixture.cleanup() }
        let library = SteamLibrary(bottle: fixture.bottle)
        #expect(library.macPath(forWindowsPath: #"C:\..\..\etc"#) == nil)
        #expect(library.macPath(forWindowsPath: "relative/path") == nil)
        #expect(library.macPath(forWindowsPath: #"C:\Games"#)?.lastPathComponent == "Games")
    }

    @Test func windowsPathRoundTrip() throws {
        let fixture = try BottleFixture()
        defer { fixture.cleanup() }
        let library = SteamLibrary(bottle: fixture.bottle)
        #expect(library.windowsPath(forMacPath: fixture.steamFolder.appending(path: "steam.exe")) == #"C:\Program Files (x86)\Steam\steam.exe"#)
        #expect(library.windowsPath(forMacPath: URL(filePath: "/tmp/setup.exe")) == #"Z:\tmp\setup.exe"#)
    }

    @Test func readsAccountsMostRecentFirst() throws {
        let fixture = try BottleFixture()
        defer { fixture.cleanup() }
        try fixture.write("""
        "users"
        {
            "76561198000000001" { "AccountName" "old" "PersonaName" "Old" "MostRecent" "0" "Timestamp" "100" }
            "76561198000000002" { "AccountName" "khalid" "PersonaName" "Khalid" "MostRecent" "1" "Timestamp" "50" }
        }
        """, to: "config/loginusers.vdf")
        let accounts = SteamLibrary(bottle: fixture.bottle).accounts()
        #expect(accounts.map(\.personaName) == ["Khalid", "Old"])
        #expect(accounts.first?.steamID64 == "76561198000000002")
    }

    @Test func collectsExecutablesSkippingRedists() throws {
        let fixture = try BottleFixture()
        defer { fixture.cleanup() }
        let game = fixture.steamFolder.appending(path: "steamapps/common/Game", directoryHint: .isDirectory)
        for relative in ["Game.exe", "bin/Game-Win64-Shipping.exe", "_CommonRedist/vcredist.exe", "UnityCrashHandler64.exe", "readme.txt"] {
            try fixture.write("", to: relative, in: game)
        }
        let names = SteamLibrary.executableNames(in: game)
        #expect(names == ["game.exe", "game-win64-shipping.exe"])
    }
}
