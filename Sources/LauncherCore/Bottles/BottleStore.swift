import Foundation

/// Discovers bottles and persists launcher-owned bottle settings.
public struct BottleStore: Sendable {
    public let paths: LauncherPaths

    public init(paths: LauncherPaths) { self.paths = paths }

    /// Launcher bottles first, then CrossOver bottles.
    public func discover(fileManager: FileManager = .default) -> [Bottle] {
        let launcher = subfolders(of: paths.bottlesFolder, fileManager: fileManager).map { url in
            Bottle(name: url.lastPathComponent, url: url, owner: .launcher, settings: loadSettings(at: url))
        }
        let crossOver = subfolders(of: paths.crossOverBottlesFolder, fileManager: fileManager)
            .filter { fileManager.fileExists(atPath: $0.appending(path: "cxbottle.conf").path) }
            .map { Bottle(name: $0.lastPathComponent, url: $0, owner: .crossOver, settings: crossOverSettings(at: $0)) }
        return launcher + crossOver
    }

    /// Folder for a new launcher bottle. Names are sanitized; `Steam`, `Steam 2`, … on collision.
    public func newBottleURL(named name: String, fileManager: FileManager = .default) -> URL {
        let cleaned = name.components(separatedBy: CharacterSet(charactersIn: "/:\\")).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let base = cleaned.isEmpty ? "Steam" : cleaned
        var candidate = paths.bottlesFolder.appending(path: base, directoryHint: .isDirectory)
        var counter = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = paths.bottlesFolder.appending(path: "\(base) \(counter)", directoryHint: .isDirectory)
            counter += 1
        }
        return candidate
    }

    public func loadSettings(at bottleURL: URL) -> BottleSettings {
        let file = bottleURL.appending(path: "bottle.json")
        guard let data = try? Data(contentsOf: file) else { return BottleSettings() }
        do {
            return try JSONDecoder().decode(BottleSettings.self, from: data)
        } catch {
            Log.bottles.error("bottle.json unlesbar (\(file.path, privacy: .public)): \(error.localizedDescription, privacy: .public)")
            return BottleSettings()
        }
    }

    public func save(_ bottle: Bottle) throws {
        switch bottle.owner {
        case .launcher:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(bottle.settings).write(to: bottle.settingsFile, options: .atomic)
        case .crossOver:
            try CrossOverConfig.write(bottle.settings, to: bottle.url.appending(path: "cxbottle.conf"))
        }
    }

    public func delete(_ bottle: Bottle) throws {
        guard bottle.owner == .launcher else {
            throw LauncherError("CrossOver-Bottles bitte in CrossOver löschen.")
        }
        try FileManager.default.trashItem(at: bottle.url, resultingItemURL: nil)
    }

    func crossOverSettings(at url: URL) -> BottleSettings {
        guard let text = try? String(contentsOf: url.appending(path: "cxbottle.conf"), encoding: .utf8) else { return BottleSettings() }
        return CrossOverConfig.settings(from: text)
    }

    private func subfolders(of folder: URL, fileManager: FileManager) -> [URL] {
        let contents = (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        return contents
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
}

/// Minimal, section-aware editor for CrossOver's `cxbottle.conf` (INI style, `"KEY" = "value"` lines).
public enum CrossOverConfig {
    static let section = "[EnvironmentVariables]"

    static func settings(from text: String) -> BottleSettings {
        let values = environmentValues(in: text)
        var settings = BottleSettings()
        switch values["CX_GRAPHICS_BACKEND"]?.lowercased() {
        case "d3dmetal": settings.graphics = .d3dMetal
        case "dxmt": settings.graphics = .dxmt
        case "dxvk": settings.graphics = .dxvk
        case "wined3d": settings.graphics = .wined3d
        default: settings.graphics = .automatic
        }
        settings.msync = values["WINEMSYNC"].map { $0 != "0" } ?? true
        settings.metalFX = values["D3DM_ENABLE_METALFX"] == "1"
        settings.metalHUD = values["MTL_HUD_ENABLED"] == "1"
        settings.advertiseAVX = values["ROSETTA_ADVERTISE_AVX"].map { $0 != "0" } ?? true
        return settings
    }

    static func environmentValues(in text: String) -> [String: String] {
        var result: [String: String] = [:]
        var inSection = false
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") { inSection = trimmed.caseInsensitiveCompare(section) == .orderedSame; continue }
            guard inSection, let (key, value) = parseLine(trimmed) else { continue }
            result[key] = value
        }
        return result
    }

    static func parseLine(_ line: String) -> (String, String)? {
        let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2 else { return nil }
        let unquote = { (s: String) in s.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
        return (unquote(parts[0]), unquote(parts[1]))
    }

    /// Writes our settings into `[EnvironmentVariables]`, keeping every other line untouched.
    static func write(_ settings: BottleSettings, to file: URL) throws {
        let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        try updated(text, with: settings).write(to: file, atomically: true, encoding: .utf8)
    }

    static func updated(_ text: String, with settings: BottleSettings) -> String {
        var desired: [String: String?] = [
            "WINEMSYNC": settings.msync ? "1" : "0",
            "D3DM_ENABLE_METALFX": settings.metalFX ? "1" : "0",
            "MTL_HUD_ENABLED": settings.metalHUD ? "1" : nil,
            "ROSETTA_ADVERTISE_AVX": settings.advertiseAVX ? "1" : "0",
        ]
        switch settings.graphics {
        case .automatic: desired["CX_GRAPHICS_BACKEND"] = .some(nil)
        case .d3dMetal: desired["CX_GRAPHICS_BACKEND"] = "d3dmetal"
        case .dxmt: desired["CX_GRAPHICS_BACKEND"] = "dxmt"
        case .dxvk: desired["CX_GRAPHICS_BACKEND"] = "dxvk"
        case .wined3d: desired["CX_GRAPHICS_BACKEND"] = "wined3d"
        }

        var lines = text.isEmpty ? [] : text.components(separatedBy: "\n")
        var sectionStart: Int?
        var sectionEnd = lines.count
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("[") else { continue }
            if sectionStart != nil { sectionEnd = index; break }
            if trimmed.caseInsensitiveCompare(section) == .orderedSame { sectionStart = index }
        }
        if sectionStart == nil {
            if let last = lines.last, !last.isEmpty { lines.append("") }
            lines.append(section)
            sectionStart = lines.count - 1
            sectionEnd = lines.count
        }

        var handled = Set<String>()
        var index = sectionStart! + 1
        while index < sectionEnd {
            if let (key, _) = parseLine(lines[index].trimmingCharacters(in: .whitespaces)), let value = desired[key] {
                handled.insert(key)
                if let value {
                    lines[index] = "\"\(key)\" = \"\(value)\""
                    index += 1
                } else {
                    lines.remove(at: index)
                    sectionEnd -= 1
                }
                continue
            }
            index += 1
        }
        // Insert missing keys at the end of the section (before trailing blank lines).
        var insertAt = sectionEnd
        while insertAt > sectionStart! + 1, lines[insertAt - 1].trimmingCharacters(in: .whitespaces).isEmpty { insertAt -= 1 }
        for key in desired.keys.sorted() where !handled.contains(key) {
            if let value = desired[key] ?? nil {
                lines.insert("\"\(key)\" = \"\(value)\"", at: insertAt)
                insertAt += 1
            }
        }
        return lines.joined(separator: "\n")
    }
}
