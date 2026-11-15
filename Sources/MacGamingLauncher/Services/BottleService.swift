import Foundation

public final class BottleService: @unchecked Sendable {
    public static let shared = BottleService()

    private let fileManager = FileManager.default

    public init() {}

    /// Discovers all bottles across known locations
    public func discoverBottles() -> [Bottle] {
        var bottles: [Bottle] = []
        let searchDirectories = [
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/CrossOver/Bottles"),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/MacGamingLauncher/Bottles"),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Whisky/Bottles")
        ]

        for baseDir in searchDirectories {
            guard fileManager.fileExists(atPath: baseDir.path) else { continue }
            guard let contents = try? fileManager.contentsOfDirectory(at: baseDir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
                continue
            }

            for bottleURL in contents {
                var isDirectory: ObjCBool = false
                if fileManager.fileExists(atPath: bottleURL.path, isDirectory: &isDirectory), isDirectory.boolValue {
                    let bottle = parseBottle(at: bottleURL)
                    bottles.append(bottle)
                }
            }
        }

        return bottles
    }

    /// Parses configuration from cxbottle.conf or bottle.json
    public func parseBottle(at url: URL) -> Bottle {
        let name = url.lastPathComponent
        let confURL = url.appendingPathComponent("cxbottle.conf")

        var msync = true
        var d3dmetal = true
        var metalFx = false
        var metalHud = false
        var retina = true

        if let confContent = try? String(contentsOf: confURL, encoding: .utf8) {
            for line in confContent.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.starts(with: "\"WINEMSYNC\"") {
                    msync = trimmed.contains("\"1\"")
                } else if trimmed.starts(with: "\"D3DM_ENABLE_METALFX\"") {
                    metalFx = trimmed.contains("\"1\"")
                } else if trimmed.starts(with: "\"MTL_HUD_ENABLED\"") {
                    metalHud = trimmed.contains("\"1\"")
                } else if trimmed.starts(with: "\"RetinaMode\"") || trimmed.starts(with: "\"AllowRetina\"") {
                    retina = trimmed.contains("\"1\"")
                } else if trimmed.starts(with: "\"CX_GRAPHICS_BACKEND\"") {
                    if trimmed.contains("\"dxvk\"") {
                        d3dmetal = false
                    }
                }
            }
        }

        return Bottle(
            name: name,
            path: url,
            msyncEnabled: msync,
            d3dMetalEnabled: d3dmetal,
            metalFxEnabled: metalFx,
            metalHudEnabled: metalHud,
            retinaEnabled: retina
        )
    }

    /// Updates toggles in cxbottle.conf if present
    public func updateBottleConfiguration(bottle: Bottle) {
        let confURL = bottle.path.appendingPathComponent("cxbottle.conf")
        guard let original = try? String(contentsOf: confURL, encoding: .utf8) else { return }

        var lines = original.components(separatedBy: .newlines)
        var updated = false

        var foundMsync = false
        var foundMetalFx = false
        var foundMetalHud = false
        var foundWineD3dMetal = false
        var foundRetina = false

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.starts(with: "\"WINEMSYNC\"") {
                lines[index] = "\"WINEMSYNC\" = \"\(bottle.msyncEnabled ? "1" : "0")\""
                updated = true
                foundMsync = true
            } else if trimmed.starts(with: "\"D3DM_ENABLE_METALFX\"") {
                lines[index] = "\"D3DM_ENABLE_METALFX\" = \"\(bottle.metalFxEnabled ? "1" : "0")\""
                updated = true
                foundMetalFx = true
            } else if trimmed.starts(with: "\"MTL_HUD_ENABLED\"") {
                lines[index] = "\"MTL_HUD_ENABLED\" = \"\(bottle.metalHudEnabled ? "1" : "0")\""
                updated = true
                foundMetalHud = true
            } else if trimmed.starts(with: "\"WINED3DMETAL\"") {
                lines[index] = "\"WINED3DMETAL\" = \"\(bottle.d3dMetalEnabled ? "1" : "0")\""
                updated = true
                foundWineD3dMetal = true
            } else if trimmed.starts(with: "\"RetinaMode\"") {
                lines[index] = "\"RetinaMode\" = \"\(bottle.retinaEnabled ? "1" : "0")\""
                updated = true
                foundRetina = true
            }
        }

        // Insert missing keys before the last closing brace
        var newKeys: [String] = []
        if !foundMsync { newKeys.append("\"WINEMSYNC\" = \"\(bottle.msyncEnabled ? "1" : "0")\"") }
        if !foundMetalFx { newKeys.append("\"D3DM_ENABLE_METALFX\" = \"\(bottle.metalFxEnabled ? "1" : "0")\"") }
        if !foundMetalHud { newKeys.append("\"MTL_HUD_ENABLED\" = \"\(bottle.metalHudEnabled ? "1" : "0")\"") }
        if !foundWineD3dMetal { newKeys.append("\"WINED3DMETAL\" = \"\(bottle.d3dMetalEnabled ? "1" : "0")\"") }
        if !foundRetina { newKeys.append("\"RetinaMode\" = \"\(bottle.retinaEnabled ? "1" : "0")\"") }

        if !newKeys.isEmpty {
            // Find the last line that is a closing brace
            if let lastBraceIndex = lines.indices.reversed().first(where: { lines[$0].trimmingCharacters(in: .whitespaces) == "}" }) {
                lines.insert(contentsOf: newKeys, at: lastBraceIndex)
            } else {
                lines.append(contentsOf: newKeys)
            }
            updated = true
        }

        if updated {
            let newContent = lines.joined(separator: "\n")
            do {
                try newContent.write(to: confURL, atomically: true, encoding: .utf8)
            } catch {
                print("[BottleService] Fehler beim Schreiben der Konfiguration: \(error.localizedDescription)")
            }
        }
    }
}
