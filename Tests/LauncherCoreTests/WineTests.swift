import Foundation
import Testing
@testable import LauncherCore

private func engine(d3dMetal: String? = nil, dxmt: Bool = true, dxvk: Bool = true, kind: EngineKind = .managed) -> Engine {
    let root = URL(filePath: "/rt/Libraries")
    return Engine(
        kind: kind,
        version: "4.8.3",
        wineBinary: root.appending(path: "Wine/bin/wine64"),
        wineserverBinary: root.appending(path: "Wine/bin/wineserver"),
        dxvkFolder: dxvk ? root.appending(path: "DXVK") : nil,
        dxmtFolder: dxmt ? root.appending(path: "DXMT") : nil,
        d3dMetal: d3dMetal.map(D3DMetalInfo.init(version:))
    )
}

private func bottle(_ configure: (inout BottleSettings) -> Void = { _ in }) -> Bottle {
    var settings = BottleSettings()
    configure(&settings)
    return Bottle(name: "Steam", url: URL(filePath: "/b/Steam"), owner: .launcher, settings: settings)
}

@Suite("Graphics plan")
struct GraphicsPlanTests {
    @Test func automaticPrefersD3DMetalThenDXMT() {
        #expect(GraphicsPlan.gameBackend(for: .automatic, engine: engine(d3dMetal: "4.0b3")) == .d3dMetal)
        #expect(GraphicsPlan.gameBackend(for: .automatic, engine: engine()) == .dxmt)
        #expect(GraphicsPlan.gameBackend(for: .automatic, engine: engine(dxmt: false)) == .dxvk)
        #expect(GraphicsPlan.gameBackend(for: .automatic, engine: engine(dxmt: false, dxvk: false)) == .wined3d)
        // Unavailable request falls back to automatic.
        #expect(GraphicsPlan.gameBackend(for: .d3dMetal, engine: engine()) == .dxmt)
    }

    @Test func steamStaysOnDXVKAndChromiumHelpersLoseNVAPI() {
        let plan = GraphicsPlan(engine: engine(d3dMetal: "4.0b3"), bottle: bottle(), paths: .standard)
        let text = plan.registry(gameExecutables: ["game.exe", "steam.exe"]).text
        let steamKey = #"[HKEY_CURRENT_USER\Software\Wine\AppDefaults\steam.exe\DllOverrides]"#
        let helperKey = #"[HKEY_CURRENT_USER\Software\Wine\AppDefaults\steamwebhelper.exe\DllOverrides]"#
        let gameKey = #"[HKEY_CURRENT_USER\Software\Wine\AppDefaults\game.exe\DllOverrides]"#
        let steamValues = [#""d3d10"="n,b""#, #""d3d10core"="n,b""#, #""d3d11"="n,b""#, #""d3d12"="""#, #""d3d9"=-"#,
                           #""dxgi"="n,b""#, #""nvapi"="""#, #""nvapi64"="""#, #""nvngx"="""#, #""winemetal"=-"#]
        #expect(text.contains(steamKey + "\r\n" + steamValues.joined(separator: "\r\n")))
        #expect(text.contains(helperKey))
        // D3DMetal games use the builtins (Apple's forwarders), NVAPI/NGX included.
        let gameValues = [#""d3d10"="b""#, #""d3d10core"="b""#, #""d3d11"="b""#, #""d3d12"="b""#, #""d3d9"=-"#,
                          #""dxgi"="b""#, #""nvapi"=-"#, #""nvapi64"=-"#, #""nvngx"=-"#, #""winemetal"=-"#]
        #expect(text.contains(gameKey + "\r\n" + gameValues.joined(separator: "\r\n")))
        // steam.exe passed as a "game" must not be overwritten with game overrides.
        #expect(text.components(separatedBy: steamKey).count == 2)
        #expect(text.contains("\"RetinaMode\"=\"n\""))
    }

    /// With Apple's forwarders deployed as builtins, DXVK/DXMT games must not fall back to them.
    @Test func nonD3DMetalGamesAvoidAppleForwarders() {
        for backend in [GraphicsBackend.dxvk, .dxmt] {
            let deployed = GraphicsPlan.overrides(for: backend, d3dMetalDeployed: true)
            #expect(deployed["d3d10"] == "n,b")
            for dll in ["d3d12", "nvapi", "nvapi64", "nvngx"] { #expect(deployed[dll] == "", "\(backend) \(dll)") }
            let plain = GraphicsPlan.overrides(for: backend, d3dMetalDeployed: false)
            for dll in ["d3d10", "d3d12", "nvapi", "nvapi64", "nvngx"] { #expect(plain[dll] == String?.none, "\(backend) \(dll)") }
        }
        // WineD3D would silently run on Apple's forwarders → not offered while D3DMetal is deployed.
        #expect(!engine(d3dMetal: "4.0b3").availableBackends.contains(.wined3d))
        #expect(engine().availableBackends.contains(.wined3d))
        #expect(GraphicsPlan.gameBackend(for: .wined3d, engine: engine(d3dMetal: "4.0b3")) == .d3dMetal)
    }

    @Test func dxmtGamesUseNativeDXMTAndBuiltinWinemetal() {
        let plan = GraphicsPlan(engine: engine(), bottle: bottle { $0.retina = true }, paths: .standard)
        let text = plan.registry(gameExecutables: ["game.exe"]).text
        #expect(text.contains(#"AppDefaults\game.exe\DllOverrides]"#))
        #expect(text.contains("\"winemetal\"=\"b\""))
        #expect(!text.contains("\"d3d12\"=\"\"")) // no D3DMetal deployed → nothing to disable
        #expect(text.contains("\"RetinaMode\"=\"y\""))
    }

    @Test func peMachineDetection() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "pe-\(UUID().uuidString).exe")
        defer { try? FileManager.default.removeItem(at: url) }
        var bytes = [UInt8](repeating: 0, count: 0x90)
        bytes[0] = 0x4D; bytes[1] = 0x5A
        bytes[0x3C] = 0x80
        bytes[0x80] = 0x50; bytes[0x81] = 0x45
        bytes[0x84] = 0x4C; bytes[0x85] = 0x01 // i386
        try Data(bytes).write(to: url)
        #expect(GraphicsPlan.peMachine(of: url) == .i386)
        bytes[0x84] = 0x64; bytes[0x85] = 0x86
        try Data(bytes).write(to: url)
        #expect(GraphicsPlan.peMachine(of: url) == .amd64)
    }
}

@Suite("Wine environment")
struct WineEnvironmentTests {
    @Test func baseEnvironment() {
        let env = WineEnvironment.make(engine: engine(), bottle: bottle(), host: ["HOME": "/Users/k", "DYLD_INSERT_LIBRARIES": "evil", "WINEPREFIX": "/wrong"], timeZone: TimeZone(identifier: "Europe/Berlin")!)
        #expect(env["WINEPREFIX"] == "/b/Steam")
        #expect(env["HOME"] == "/Users/k")
        #expect(env["DYLD_INSERT_LIBRARIES"] == nil)
        #expect(env["WINEDLLOVERRIDES"] == nil)
        #expect(env["WINEMSYNC"] == "1")
        #expect(env["WINEESYNC"] == "1")
        #expect(env["ROSETTA_ADVERTISE_AVX"] == "1")
        #expect(env["STEAM_DISABLE_CEF_SANDBOX"] == "1")
        #expect(env["TZ"] == "Europe/Berlin")
        #expect(env["MTL_HUD_ENABLED"] == nil)
        #expect(env["D3DM_MTL4"] == nil)
    }

    @Test func d3dMetal4AndToggles() {
        let env = WineEnvironment.make(engine: engine(d3dMetal: "4.0b3"), bottle: bottle { $0.metalHUD = true; $0.metalFX = true; $0.msync = false; $0.advertiseAVX = false }, host: [:])
        #expect(env["D3DM_MTL4"] == "1")
        #expect(env["D3DM_ENABLE_METALFX"] == "1")
        #expect(env["MTL_HUD_ENABLED"] == "1")
        #expect(env["WINEMSYNC"] == nil)
        #expect(env["ROSETTA_ADVERTISE_AVX"] == nil)
    }

    @Test func crossOverGetsMinimalEnvironment() {
        let crossOverBottle = Bottle(name: "Steam", url: URL(filePath: "/cx/Steam"), owner: .crossOver)
        let env = WineEnvironment.make(engine: engine(kind: .crossOver), bottle: crossOverBottle, host: ["HOME": "/h"])
        #expect(env["WINEPREFIX"] == nil)
        #expect(env["HOME"] == "/h")
    }

    @Test func crossOverCommandLine() {
        let crossOverBottle = Bottle(name: "My Steam", url: URL(filePath: "/cx/My Steam"), owner: .crossOver)
        let wine = Wine(engine: engine(kind: .crossOver), bottle: crossOverBottle, paths: .standard)
        #expect(wine.arguments(program: #"C:\Steam\steam.exe"#, ["-silent"]) == ["--bottle", "My Steam", "--cx-app", #"C:\Steam\steam.exe"#, "-silent"])
        let managed = Wine(engine: engine(), bottle: bottle(), paths: .standard)
        #expect(managed.arguments(program: "winecfg", ["-v", "win10"]) == ["winecfg", "-v", "win10"])
    }
}

@Suite("Registry file")
struct RegistryFileTests {
    @Test func utf16WithBOMAndEscaping() throws {
        var file = RegistryFile()
        file.set(#"HKEY_CURRENT_USER\Software\Test"#, "Path", .string(#"C:\a "b""#))
        file.set(#"HKEY_CURRENT_USER\Software\Test"#, "Count", .dword(255))
        file.set(#"hkey_current_user\software\test"#, "Path", .delete)
        let data = file.data
        #expect(Array(data.prefix(2)) == [0xFF, 0xFE])
        let text = try #require(String(data: data.dropFirst(2), encoding: .utf16LittleEndian))
        #expect(text.hasPrefix("Windows Registry Editor Version 5.00\r\n"))
        #expect(text.contains("\"Path\"=-"))
        #expect(text.contains("\"Count\"=dword:000000ff"))
        #expect(text.components(separatedBy: "[HKEY_CURRENT_USER").count == 2)
    }
}
