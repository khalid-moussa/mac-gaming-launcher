import Foundation
import Testing
@testable import LauncherCore

@Suite("CrossOver config")
struct CrossOverConfigTests {
    let sample = """
    [Bottle]
    "Template" = "win10_64"

    [EnvironmentVariables]
    "WINEMSYNC" = "1"
    "CX_GRAPHICS_BACKEND" = "dxvk"
    "OTHER" = "keep"

    [Wine]
    "Version" = "x"
    """

    @Test func readsOnlyEnvironmentSection() {
        let settings = CrossOverConfig.settings(from: sample)
        #expect(settings.graphics == .dxvk)
        #expect(settings.msync)
    }

    @Test func roundTripKeepsOtherSectionsAndRemovesAutomaticBackend() {
        var settings = CrossOverConfig.settings(from: sample)
        settings.graphics = .automatic
        settings.msync = false
        settings.metalFX = true
        let updated = CrossOverConfig.updated(sample, with: settings)

        #expect(updated.contains("[Bottle]\n\"Template\" = \"win10_64\""))
        #expect(updated.contains("[Wine]\n\"Version\" = \"x\""))
        #expect(updated.contains("\"OTHER\" = \"keep\""))
        #expect(!updated.contains("CX_GRAPHICS_BACKEND"))
        let reparsed = CrossOverConfig.settings(from: updated)
        #expect(reparsed.graphics == .automatic)
        #expect(!reparsed.msync)
        #expect(reparsed.metalFX)
        // New keys land inside [EnvironmentVariables], before [Wine].
        let envRange = updated.range(of: "[EnvironmentVariables]")!
        let wineRange = updated.range(of: "[Wine]")!
        let metalFX = updated.range(of: "D3DM_ENABLE_METALFX")!
        #expect(envRange.upperBound < metalFX.lowerBound && metalFX.upperBound < wineRange.lowerBound)
    }

    @Test func createsSectionWhenMissing() {
        let updated = CrossOverConfig.updated("[Bottle]\n\"A\" = \"b\"\n", with: BottleSettings())
        #expect(updated.contains("[EnvironmentVariables]"))
        #expect(CrossOverConfig.settings(from: updated).msync)
    }
}

@Suite("Playtime store")
struct PlaytimeStoreTests {
    func tempFile() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "playtime-\(UUID().uuidString).json")
    }

    @Test func accumulatesAndPersists() {
        let file = tempFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let store = PlaytimeStore(file: file)
        let start = Date(timeIntervalSince1970: 1000)
        store.addSession(gameID: "b#1", start: start, end: start.addingTimeInterval(600))
        store.addSession(gameID: "b#1", start: start, end: start.addingTimeInterval(2)) // ignored: too short
        store.addSession(gameID: "b#1", start: start, end: start.addingTimeInterval(3000))

        let reloaded = PlaytimeStore(file: file)
        #expect(reloaded.record(for: "b#1").total == 3600)
        #expect(reloaded.record(for: "b#1").lastPlayed == start.addingTimeInterval(3000))
        #expect(reloaded.record(for: "other").total == 0)
    }

    @Test func backsUpCorruptFile() throws {
        let file = tempFile()
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("{not json".utf8).write(to: file)
        let store = PlaytimeStore(file: file)
        #expect(store.record(for: "x").total == 0)
        let siblings = try FileManager.default.contentsOfDirectory(at: file.deletingLastPathComponent(), includingPropertiesForKeys: nil)
        let backups = siblings.filter { $0.lastPathComponent.hasPrefix(file.deletingPathExtension().lastPathComponent + ".corrupt-") }
        #expect(!backups.isEmpty)
        backups.forEach { try? FileManager.default.removeItem(at: $0) }
    }

    @Test func formatsDurations() {
        #expect(PlaytimeStore.format(0) == "—")
        #expect(PlaytimeStore.format(30) == "< 1 Min.")
        #expect(PlaytimeStore.format(3 * 3600 + 5 * 60).contains("3"))
    }
}

@Suite("Bottle settings & store")
struct BottleStoreTests {
    @Test func decodesPartialSettingsWithDefaults() throws {
        let settings = try JSONDecoder().decode(BottleSettings.self, from: Data(#"{"graphics":"dxmt","metalHUD":true}"#.utf8))
        #expect(settings.graphics == .dxmt)
        #expect(settings.metalHUD)
        #expect(settings.msync)
        #expect(settings.windowsVersion == "win10")
    }

    @Test func discoversAndPersistsLauncherBottles() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "mgl-store-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = LauncherPaths(root: root, logs: root.appending(path: "logs"), home: root.appending(path: "home"))
        try paths.createOwnedFolders()
        let store = BottleStore(paths: paths)

        let url = store.newBottleURL(named: "Steam")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var bottle = Bottle(name: "Steam", url: url, owner: .launcher)
        bottle.settings.graphics = .dxvk
        try store.save(bottle)

        #expect(store.newBottleURL(named: "Steam").lastPathComponent == "Steam 2")
        #expect(store.newBottleURL(named: "a/b").lastPathComponent == "a-b")
        let found = store.discover()
        #expect(found.count == 1)
        #expect(found.first?.settings.graphics == .dxvk)
        #expect(found.first?.engineKind == .managed)
    }
}

@Suite("Runtime")
struct RuntimeTests {
    @Test func versionComparison() {
        #expect(RuntimeInstaller.isNewer("4.8.3", than: "4.8.2"))
        #expect(RuntimeInstaller.isNewer("4.10.0", than: "4.9.9"))
        #expect(!RuntimeInstaller.isNewer("4.8.3", than: "4.8.3"))
        #expect(!RuntimeInstaller.isNewer("4.8", than: "4.8.1"))
    }

    @Test func detectsCompleteRuntimeAndD3DMetalVersion() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "mgl-rt-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = LauncherPaths(root: root, logs: root, home: root)
        let fm = FileManager.default
        let bin = paths.librariesFolder.appending(path: "Wine/bin")
        try fm.createDirectory(at: bin, withIntermediateDirectories: true)
        #expect(RuntimeInstaller(paths: paths).installedVersion() == nil)

        for name in ["wine64", "wineserver"] {
            fm.createFile(atPath: bin.appending(path: name).path, contents: Data(), attributes: [.posixPermissions: 0o755])
        }
        let plist: [String: Any] = ["version": ["major": 4, "minor": 8, "patch": 3], "gptkCapable": true]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: paths.librariesFolder.appending(path: "WhiskyWineVersion.plist"))
        try fm.createDirectory(at: paths.librariesFolder.appending(path: "DXMT/x64"), withIntermediateDirectories: true)

        let engine = try #require(EngineLocator(paths: paths).managedEngine())
        #expect(engine.version == "4.8.3")
        #expect(engine.dxmtFolder != nil)
        #expect(engine.dxvkFolder == nil)
        #expect(engine.d3dMetal == nil)
        #expect(engine.supportsMSync)
    }

    @Test func locatesGPTKPayloadLayouts() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "mgl-gptk-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let lib = root.appending(path: "redist/lib")
        let fm = FileManager.default
        try fm.createDirectory(at: lib.appending(path: "external/D3DMetal.framework/Versions/A/Resources"), withIntermediateDirectories: true)
        try fm.createDirectory(at: lib.appending(path: "wine/x86_64-windows"), withIntermediateDirectories: true)
        fm.createFile(atPath: lib.appending(path: "external/libd3dshared.dylib").path, contents: Data())
        for dll in D3DMetalInstaller.forwarderDLLs { fm.createFile(atPath: lib.appending(path: "wine/x86_64-windows/\(dll)").path, contents: Data()) }
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleShortVersionString": "4.0b3"], format: .xml, options: 0)
            .write(to: lib.appending(path: "external/D3DMetal.framework/Versions/A/Resources/Info.plist"))

        let located = try #require(D3DMetalInstaller.locatePayload(under: root))
        #expect(located.standardizedFileURL == lib.standardizedFileURL)
        #expect(D3DMetalInstaller.missingFiles(in: located, fileManager: fm).isEmpty)
        let version = try #require(D3DMetalInstaller.frameworkVersion(inExternal: located.appending(path: "external")))
        #expect(D3DMetalInfo(version: version).isMetal4)
        #expect(!D3DMetalInfo(version: "3.0").isMetal4)
    }
}

@Suite("Process list")
struct ProcessListTests {
    func procArgs(argc: Int32, exec: String, args: [String], env: [String]) -> [UInt8] {
        var bytes = withUnsafeBytes(of: argc) { Array($0) }
        bytes += Array(exec.utf8) + [0, 0, 0]
        for arg in args { bytes += Array(arg.utf8) + [0] }
        for entry in env { bytes += Array(entry.utf8) + [0] }
        return bytes + [0]
    }

    @Test func parsesWineProcessArguments() throws {
        let buffer = procArgs(
            argc: 2,
            exec: "/Runtime/Libraries/Wine/bin/wine64",
            args: [#"C:\Program Files (x86)\Steam\steamapps\common\Game\Game.exe"#, "-dx12"],
            env: ["HOME=/Users/x", "WINEPREFIX=/Users/x/Bottles/Steam"]
        )
        let process = try #require(ProcessList.parseProcArgs(buffer, pid: 42))
        #expect(process.windowsImageName == "game.exe")
        #expect(process.arguments == [#"C:\Program Files (x86)\Steam\steamapps\common\Game\Game.exe"#, "-dx12"])
        #expect(process.winePrefix == "/Users/x/Bottles/Steam")
        #expect(process.normalizedWindowsPath.contains(#"steamapps\common\game\"#))
    }

    /// Real layout observed on macOS 27 (steam.exe, KERN_PROCARGS2): Wine moved argv down, so with the kernel's
    /// original argc=2 the second slot is an empty string, followed by a run of NUL padding, then the environment.
    @Test func handlesWineRewrittenArgv() throws {
        var buffer = withUnsafeBytes(of: Int32(2)) { Array($0) }
        buffer += Array("/rt/Wine/lib/wine/x86_64-unix/wine".utf8) + [0, 0, 0]
        buffer += Array(#"C:\Program Files (x86)\Steam\steam.exe"#.utf8) + [0]
        buffer += [UInt8](repeating: 0, count: 37) // padding where the old, longer argv lived
        buffer += Array("TMPDIR=/var/tmp".utf8) + [0]
        buffer += Array("WINEPREFIX=/b/Steam".utf8) + [0, 0]
        let process = try #require(ProcessList.parseProcArgs(buffer, pid: 7))
        #expect(process.windowsImageName == "steam.exe")
        #expect(process.winePrefix == "/b/Steam")
        #expect(process.arguments == [#"C:\Program Files (x86)\Steam\steam.exe"#])
    }

    /// Against the live system: any running Wine process must be attributed to its prefix.
    @Test func liveWineProcessesHavePrefix() {
        let wine = ProcessList.current().filter { $0.windowsImageName != nil }
        for process in wine {
            #expect(process.winePrefix != nil, "\(process.commandName) ohne WINEPREFIX")
        }
    }

    @Test func listsOwnProcess() {
        let processes = ProcessList.current()
        #expect(processes.contains { $0.pid == getpid() })
    }
}
