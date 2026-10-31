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
        let retina = true

        if let confContent = try? String(contentsOf: confURL, encoding: .utf8) {
            for line in confContent.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.contains("WINEMSYNC") {
                    msync = trimmed.contains("\"1\"")
                } else if trimmed.contains("D3DM_ENABLE_METALFX") {
                    metalFx = trimmed.contains("\"1\"")
                } else if trimmed.contains("MTL_HUD_ENABLED") {
                    metalHud = trimmed.contains("\"1\"")
                } else if trimmed.contains("CX_GRAPHICS_BACKEND") {
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

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.starts(with: "\"WINEMSYNC\"") {
                lines[index] = "\"WINEMSYNC\" = \"\(bottle.msyncEnabled ? "1" : "0")\""
                updated = true
            } else if trimmed.starts(with: "\"D3DM_ENABLE_METALFX\"") {
                lines[index] = "\"D3DM_ENABLE_METALFX\" = \"\(bottle.metalFxEnabled ? "1" : "0")\""
                updated = true
            }
        }

        if updated {
            let newContent = lines.joined(separator: "\n")
            try? newContent.write(to: confURL, atomically: true, encoding: .utf8)
        }
    }
}
