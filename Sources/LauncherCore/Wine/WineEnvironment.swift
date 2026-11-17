import Foundation

/// Builds the process environment for Wine invocations.
///
/// Deliberately does NOT set `WINEDLLOVERRIDES`: it would be inherited by every child process (Steam → games) and
/// outrank the per-executable registry overrides that keep Steam on DXVK while games use D3DMetal/DXMT.
public enum WineEnvironment {
    public static func make(
        engine: Engine,
        bottle: Bottle,
        host: [String: String] = ProcessInfo.processInfo.environment,
        timeZone: TimeZone = .current
    ) -> [String: String] {
        let settings = bottle.settings
        var env: [String: String] = [:]

        // Minimal host passthrough — no inherited DYLD_*/WINE* surprises from the launching shell.
        for key in ["HOME", "USER", "LOGNAME", "TMPDIR", "LANG", "LC_ALL", "SHELL"] {
            if let value = host[key] { env[key] = value }
        }
        env["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
        env["TZ"] = host["TZ"] ?? timeZone.identifier

        if engine.kind == .crossOver {
            // CrossOver's wrapper manages the prefix and reads cxbottle.conf; only pass HUD toggles.
            if settings.metalHUD { env["MTL_HUD_ENABLED"] = "1" }
            return env
        }

        env["WINEPREFIX"] = bottle.url.path
        env["WINEDEBUG"] = "fixme-all"
        env["GST_DEBUG"] = "1"
        env["MTL_DEBUG_LAYER"] = "0"
        env["WINEFSYNC"] = "0"
        // D3DMetal expects ESYNC to be set; MSYNC on top when the build supports it.
        env["WINEESYNC"] = "1"
        if settings.msync && engine.supportsMSync { env["WINEMSYNC"] = "1" }

        // Steam (Chromium) under Wine.
        env["STEAM_RUNTIME"] = "0"
        env["STEAM_DISABLE_CEF_SANDBOX"] = "1"
        env["CEF_DISABLE_SANDBOX"] = "1"

        if settings.advertiseAVX { env["ROSETTA_ADVERTISE_AVX"] = "1" }
        if settings.metalHUD { env["MTL_HUD_ENABLED"] = "1" }

        // Games inherit Steam's environment, so backend variables are set for the whole bottle.
        env["DXVK_ASYNC"] = "1"
        env["MVK_CONFIG_SHOULD_MAXIMIZE_CONCURRENT_COMPILATION"] = "1"
        let dxvkConfig = bottle.url.appending(path: "dxvk.conf")
        if FileManager.default.fileExists(atPath: dxvkConfig.path) {
            env["DXVK_CONFIG_FILE"] = "Z:" + dxvkConfig.path.replacingOccurrences(of: "/", with: "\\")
        }
        if let d3dMetal = engine.d3dMetal {
            if d3dMetal.isMetal4 { env["D3DM_MTL4"] = "1" }
            if settings.metalFX { env["D3DM_ENABLE_METALFX"] = "1" }
        }
        if GraphicsPlan.gameBackend(for: settings.graphics, engine: engine) == .wined3d {
            env["WINED3DMETAL"] = "0"
        }
        return env
    }
}
