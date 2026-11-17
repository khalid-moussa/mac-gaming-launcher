import Foundation
import Testing
@testable import LauncherCore

/// Regression tests for defects found in the component reviews (11/2026).

/// A fake runtime tree plus scratch launcher paths.
private struct RuntimeFixture {
    let root: URL
    let paths: LauncherPaths
    let fm = FileManager.default

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "mgl-reg-\(UUID().uuidString)", directoryHint: .isDirectory)
        paths = LauncherPaths(root: root, logs: root.appending(path: "logs"), home: root.appending(path: "home"))
        let wine = paths.librariesFolder.appending(path: "Wine")
        for folder in ["bin", "lib/wine/x86_64-windows", "lib/wine/x86_64-unix", "lib/wine/i386-windows", "lib/external"] {
            try fm.createDirectory(at: wine.appending(path: folder), withIntermediateDirectories: true)
        }
        for name in ["wine64", "wineserver"] {
            fm.createFile(atPath: wine.appending(path: "bin/\(name)").path, contents: Data(), attributes: [.posixPermissions: 0o755])
        }
        try PropertyListSerialization.data(fromPropertyList: ["version": ["major": 4, "minor": 8, "patch": 3], "gptkCapable": true], format: .xml, options: 0)
            .write(to: paths.librariesFolder.appending(path: "WhiskyWineVersion.plist"))
        try installWineDLLs(tag: "WINE1")
    }

    var pe: URL { paths.librariesFolder.appending(path: "Wine/lib/wine/x86_64-windows") }
    var unix: URL { paths.librariesFolder.appending(path: "Wine/lib/wine/x86_64-unix") }

    /// Wine's own D3D DLLs: "Wine builtin DLL" marker at 0x40, like the real ones.
    func wineDLL(_ tag: String) -> Data {
        var bytes = [UInt8](repeating: 0, count: 0x40) + Array("Wine builtin DLL".utf8)
        bytes += Array(tag.utf8)
        return Data(bytes)
    }

    func installWineDLLs(tag: String) throws {
        for name in ["d3d10.dll", "d3d11.dll", "d3d12.dll", "dxgi.dll"] {
            try wineDLL("\(tag)-\(name)").write(to: pe.appending(path: name))
        }
    }

    /// A GPTK payload of the given version.
    func payload(_ version: String) throws -> URL {
        let lib = root.appending(path: "payload-\(version)/redist/lib")
        try fm.createDirectory(at: lib.appending(path: "external/D3DMetal.framework/Versions/A/Resources"), withIntermediateDirectories: true)
        try fm.createDirectory(at: lib.appending(path: "wine/x86_64-windows"), withIntermediateDirectories: true)
        try Data("dylib-\(version)".utf8).write(to: lib.appending(path: "external/libd3dshared.dylib"))
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleShortVersionString": version], format: .xml, options: 0)
            .write(to: lib.appending(path: "external/D3DMetal.framework/Versions/A/Resources/Info.plist"))
        for dll in D3DMetalInstaller.forwarderDLLs + [D3DMetalInstaller.metalFXSource, D3DMetalInstaller.nvapiName] {
            try Data("APPLE-\(version)-\(dll)".utf8).write(to: lib.appending(path: "wine/x86_64-windows/\(dll)"))
        }
        return lib
    }

    func read(_ url: URL) -> String? {
        (try? Data(contentsOf: url)).map { String(decoding: $0, as: UTF8.self) }
    }

    func cleanup() { try? fm.removeItem(at: root) }
}

@Suite("D3DMetal deploy/remove")
struct D3DMetalRoundTripTests {
    @Test func redeployReimportRuntimeUpdateAndRemoveRestoreWine() throws {
        let fx = try RuntimeFixture()
        defer { fx.cleanup() }
        let installer = D3DMetalInstaller(paths: fx.paths)
        let dxgi = fx.pe.appending(path: "dxgi.dll")
        let backup = fx.paths.d3dMetalStore.appending(path: "originals/dxgi.dll")

        // Import A, deploy twice (idempotent).
        _ = try installer.copyToStore(try fx.payload("4.0b1"))
        try installer.deploy()
        try installer.deploy()
        #expect(fx.read(dxgi) == "APPLE-4.0b1-dxgi.dll")
        #expect(fx.read(backup)?.hasSuffix("WINE1-dxgi.dll") == true)
        #expect(fx.read(fx.pe.appending(path: "nvngx.dll")) == "APPLE-4.0b1-nvngx-on-metalfx.dll")
        #expect((try? fx.fm.destinationOfSymbolicLink(atPath: fx.unix.appending(path: "dxgi.so").path)) == D3DMetalInstaller.unixLinkDestination)
        #expect(installer.deployedInfo()?.version == "4.0b1")

        // Re-import B: the backup must still be Wine's original, not A's forwarder.
        _ = try installer.copyToStore(try fx.payload("4.0b2"))
        try installer.deploy()
        #expect(fx.read(dxgi) == "APPLE-4.0b2-dxgi.dll")
        #expect(fx.read(backup)?.hasSuffix("WINE1-dxgi.dll") == true)

        // Runtime update: a fresh Wine tree replaces everything; redeploy must back up the NEW Wine files.
        for name in ["d3d10.so", "d3d11.so", "d3d12.so", "dxgi.so", "nvngx.so", "nvapi64.so"] {
            try? fx.fm.removeItem(at: fx.unix.appending(path: name))
        }
        for name in ["nvngx.dll", "nvapi64.dll"] { try? fx.fm.removeItem(at: fx.pe.appending(path: name)) }
        try fx.installWineDLLs(tag: "WINE2")
        try installer.deployIfImported()
        #expect(fx.read(dxgi) == "APPLE-4.0b2-dxgi.dll")
        #expect(fx.read(backup)?.hasSuffix("WINE2-dxgi.dll") == true)

        // Remove restores Wine 2 everywhere and leaves nothing of Apple's behind.
        try installer.remove()
        for name in ["d3d10.dll", "d3d11.dll", "d3d12.dll", "dxgi.dll"] {
            #expect(fx.read(fx.pe.appending(path: name))?.hasSuffix("WINE2-\(name)") == true, "\(name)")
        }
        #expect(!fx.fm.fileExists(atPath: fx.pe.appending(path: "nvngx.dll").path))
        #expect((try? fx.fm.destinationOfSymbolicLink(atPath: fx.unix.appending(path: "dxgi.so").path)) == nil)
        #expect(!fx.fm.fileExists(atPath: fx.paths.librariesFolder.appending(path: "Wine/lib/external/libd3dshared.dylib").path))
        #expect(!fx.fm.fileExists(atPath: fx.paths.d3dMetalStore.path))
    }

    @Test func removeAfterInterruptedDeployRestoresBackup() throws {
        let fx = try RuntimeFixture()
        defer { fx.cleanup() }
        let installer = D3DMetalInstaller(paths: fx.paths)
        _ = try installer.copyToStore(try fx.payload("4.0b1"))
        try installer.deploy()
        // Crash between "move original to backup" and "copy forwarder": destination missing.
        try fx.fm.removeItem(at: fx.pe.appending(path: "d3d11.dll"))
        try installer.remove()
        #expect(fx.read(fx.pe.appending(path: "d3d11.dll"))?.hasSuffix("WINE1-d3d11.dll") == true)
    }

    @Test func removeWithoutDeployNeverDeletesWineDLLs() throws {
        let fx = try RuntimeFixture()
        defer { fx.cleanup() }
        let installer = D3DMetalInstaller(paths: fx.paths)
        _ = try installer.copyToStore(try fx.payload("4.0b1")) // imported, never deployed
        try installer.remove()
        for name in ["d3d10.dll", "d3d11.dll", "d3d12.dll", "dxgi.dll"] {
            #expect(fx.read(fx.pe.appending(path: name))?.hasSuffix("WINE1-\(name)") == true, "\(name)")
        }
    }

    @Test func plistParsingIgnoresTrailingWarnings() {
        let output = "<?xml version=\"1.0\"?><plist version=\"1.0\"><dict><key>a</key><string>b</string></dict></plist>\nhdiutil: warning: deprecated\n"
        #expect(D3DMetalInstaller.plistDictionary(in: output)?["a"] as? String == "b")
    }
}

@Suite("Graphics plan files")
struct GraphicsPlanFileTests {
    private func engine(_ fx: RuntimeFixture, d3dMetal: Bool) -> Engine {
        let libraries = fx.paths.librariesFolder
        return Engine(
            kind: .managed, version: "4.8.3",
            wineBinary: libraries.appending(path: "Wine/bin/wine64"),
            wineserverBinary: libraries.appending(path: "Wine/bin/wineserver"),
            dxvkFolder: nil,
            dxmtFolder: libraries.appending(path: "DXMT"),
            d3dMetal: d3dMetal ? D3DMetalInfo(version: "4.0b1") : nil
        )
    }

    private func bottle(_ fx: RuntimeFixture, graphics: GraphicsBackend = .automatic) throws -> Bottle {
        let url = fx.root.appending(path: "Bottle", directoryHint: .isDirectory)
        for folder in ["drive_c/windows/system32", "drive_c/windows/syswow64"] {
            try fx.fm.createDirectory(at: url.appending(path: folder), withIntermediateDirectories: true)
        }
        var bottle = Bottle(name: "Bottle", url: url, owner: .launcher)
        bottle.settings.graphics = graphics
        return bottle
    }

    @Test func originalsArePatchedToLoadAsNative() throws {
        let fx = try RuntimeFixture()
        defer { fx.cleanup() }
        let installer = D3DMetalInstaller(paths: fx.paths)
        _ = try installer.copyToStore(try fx.payload("4.0b1"))
        try installer.deploy()
        let plan = GraphicsPlan(engine: engine(fx, d3dMetal: true), bottle: try bottle(fx), paths: fx.paths)
        try plan.fixUpBuiltins(fileManager: fx.fm)
        try plan.fixUpBuiltins(fileManager: fx.fm) // idempotent
        for name in GraphicsPlan.patchedOriginals {
            let bytes = try [UInt8](Data(contentsOf: plan.system32.appending(path: name)))
            #expect(Array(bytes[0x40..<0x50]) == GraphicsPlan.dosStub, "\(name)")
            #expect(String(decoding: bytes[0x50...], as: UTF8.self) == "WINE1-\(name)")
        }
    }

    @Test func dxmtSyncNeverTouchesGameOwnedFiles() throws {
        let fx = try RuntimeFixture()
        defer { fx.cleanup() }
        let dxmt = fx.paths.librariesFolder.appending(path: "DXMT/x64")
        try fx.fm.createDirectory(at: dxmt, withIntermediateDirectories: true)
        for dll in GraphicsPlan.dxmtGameDLLs { try Data("DXMT-\(dll)".utf8).write(to: dxmt.appending(path: dll)) }

        let game = fx.root.appending(path: "Game", directoryHint: .isDirectory)
        try fx.fm.createDirectory(at: game, withIntermediateDirectories: true)
        let exe = game.appending(path: "game.exe")
        try Data().write(to: exe)
        try Data("GAME-OWN".utf8).write(to: game.appending(path: "dxgi.dll"))

        let dxmtPlan = GraphicsPlan(engine: engine(fx, d3dMetal: false), bottle: try bottle(fx, graphics: .dxmt), paths: fx.paths)
        dxmtPlan.syncDXMTGameFolders(games: [(game, [exe])])
        #expect(fx.read(game.appending(path: "dxgi.dll")) == "GAME-OWN")
        #expect(fx.read(game.appending(path: "d3d11.dll")) == "DXMT-d3d11.dll")

        // A mod (e.g. ReShade) replaces our d3d10core copy → it now belongs to the user.
        try Data("RESHADE".utf8).write(to: game.appending(path: "d3d10core.dll"))
        let dxvkPlan = GraphicsPlan(engine: engine(fx, d3dMetal: false), bottle: try bottle(fx, graphics: .wined3d), paths: fx.paths)
        dxvkPlan.syncDXMTGameFolders(games: [(game, [exe])])
        #expect(!fx.fm.fileExists(atPath: game.appending(path: "d3d11.dll").path))
        #expect(fx.read(game.appending(path: "d3d10core.dll")) == "RESHADE")
        #expect(fx.read(game.appending(path: "dxgi.dll")) == "GAME-OWN")
    }
}

@Suite("Review regressions")
struct ReviewRegressionTests {
    @Test func crossOverConfigKeepsCRLF() {
        let text = "[Bottle]\r\n\"Template\" = \"win10_64\"\r\n\r\n[EnvironmentVariables]\r\n\"WINEMSYNC\" = \"1\"\r\n"
        var settings = CrossOverConfig.settings(from: text)
        settings.msync = false
        let updated = CrossOverConfig.updated(text, with: settings)
        #expect(updated.components(separatedBy: "[EnvironmentVariables]").count == 2)
        #expect(updated.contains("\"WINEMSYNC\" = \"0\"\r\n"))
        #expect(!updated.replacingOccurrences(of: "\r\n", with: "").contains("\n"))
    }

    @Test func truncatedVDFValueIsDropped() throws {
        let root = try VDF.parse("\"AppState\"\n{\n\"appid\" \"10\"\n\"StateFlags\" \"10")
        #expect(root["AppState"]?["appid"]?.string == "10")
        #expect(root["AppState"]?["StateFlags"] == nil)
    }

    @Test func vdfFallsBackToLatin1PerToken() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "latin1-\(UUID().uuidString).vdf")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data([0x22, 0x6E, 0x22, 0x20, 0x22, 0x63, 0x61, 0x66, 0xE9, 0x22]).write(to: url) // "n" "café" in Latin-1
        #expect(try VDF.parse(contentsOf: url)["n"]?.string == "café")
    }

    @Test func unknownBackendKeepsOtherSettings() throws {
        let json = #"{"graphics":"metal5","msync":false,"metalHUD":true,"windowsVersion":"win11","retina":"yes"}"#
        let settings = try JSONDecoder().decode(BottleSettings.self, from: Data(json.utf8))
        #expect(settings.graphics == .automatic)
        #expect(!settings.msync)
        #expect(settings.metalHUD)
        #expect(settings.windowsVersion == "win11")
        #expect(!settings.retina) // mistyped → default, without resetting the rest
    }

    @Test func legacyPlaytimeIsKeptAndFoldedIn() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "playtime-legacy-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data(#"{"1245620": 3600.5}"#.utf8).write(to: file)
        let store = PlaytimeStore(file: file)
        #expect(store.total(for: "/b/Steam#1245620") == 3600.5)
        let start = Date(timeIntervalSince1970: 1000)
        store.addSession(gameID: "/b/Steam#1245620", start: start, end: start.addingTimeInterval(60))
        #expect(PlaytimeStore(file: file).total(for: "/b/Steam#1245620") == 3660.5)
    }

    @Test func manifestWithUnsafeInstallDirIsIgnored() throws {
        for installDir in ["", "..", "../../..", "a/b"] {
            let root = try VDF.parse("\"AppState\" { \"appid\" \"5\" \"name\" \"X\" \"installdir\" \"\(installDir)\" }")
            #expect(SteamLibrary.game(fromManifest: root, libraryFolder: URL(filePath: "/lib/steamapps"), bottleID: "b") == nil, "\(installDir)")
        }
    }

    @Test func gameIsRecognizedByInstallPathInAnyDriveSpelling() throws {
        let fixture = try BottleFixture()
        defer { fixture.cleanup() }
        let library = SteamLibrary(bottle: fixture.bottle)
        let folder = fixture.steamFolder.appending(path: "steamapps/common/Big Game", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let prefixes = library.windowsPathPrefixes(forMacFolder: folder)
        #expect(prefixes.contains(#"c:\program files (x86)\steam\steamapps\common\big game\"#))
        #expect(prefixes.contains { $0.hasPrefix("z:") && $0.hasSuffix(#"\steamapps\common\big game\"#) })

        let prefix = fixture.bottle.url.path
        let snapshot = [
            RunningProcess(pid: 1, commandName: #"C:\Program Files (x86)\Steam\steamapps\common\Big Game\Binaries\Win64\BigGame-Win64-Shipping.exe"#, arguments: [], winePrefix: prefix),
            RunningProcess(pid: 2, commandName: #"C:\Program Files (x86)\Steam\steam.exe"#, arguments: [], winePrefix: prefix),
            RunningProcess(pid: 3, commandName: #"C:\Program Files (x86)\Steam\steamapps\common\Big Game\Game.exe"#, arguments: [], winePrefix: "/other"),
        ]
        // No executable names known (huge asset tree): the path alone identifies the game, Steam is never the game.
        let monitor = GameMonitor(bottle: fixture.bottle, installFolder: folder, executableNames: [])
        #expect(monitor.runningProcesses(snapshot).map(\.pid) == [1])
    }

    @Test func macPathResolvesDriveLinks() throws {
        let fixture = try BottleFixture()
        defer { fixture.cleanup() }
        let library = SteamLibrary(bottle: fixture.bottle)
        let games = try #require(library.macPath(forWindowsPath: #"C:\Games\X"#))
        #expect(games.path == fixture.bottle.driveC.appending(path: "Games/X").standardizedFileURL.path)
        let external = fixture.root.appending(path: "External", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: fixture.bottle.url.appending(path: "dosdevices/d:").path, withDestinationPath: external.path)
        #expect(library.macPath(forWindowsPath: #"d:\Lib"#)?.path == external.appending(path: "Lib").standardizedFileURL.path)
    }
}
