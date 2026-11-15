import Foundation

public final class PlaytimeTracker: @unchecked Sendable {
    public static let shared = PlaytimeTracker()

    private let fileURL: URL
    private var records: [String: TimeInterval] = [:]
    private var activeSessions: [String: Date] = [:]
    private let lock = NSLock()

    public init() {
        let appSupport = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MacGamingLauncher")
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        self.fileURL = appSupport.appendingPathComponent("playtime.json")
        load()
    }

    public func sessionStarted(appId: String) {
        lock.lock()
        defer { lock.unlock() }
        activeSessions[appId] = Date()
    }

    public func sessionEnded(appId: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let startTime = activeSessions.removeValue(forKey: appId) else { return }
        let duration = Date().timeIntervalSince(startTime)
        let currentTotal = records[appId] ?? 0
        records[appId] = currentTotal + duration
        save()
    }

    /// Flushes all currently active sessions — call before the app terminates.
    public func flushAllActiveSessions() {
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        for (appId, startTime) in activeSessions {
            let duration = now.timeIntervalSince(startTime)
            let currentTotal = records[appId] ?? 0
            records[appId] = currentTotal + duration
        }
        activeSessions.removeAll()
        save()
    }

    public func totalPlaytime(appId: String) -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return records[appId] ?? 0
    }

    public func formattedPlaytime(appId: String) -> String {
        let total = totalPlaytime(appId: appId)
        if total < 60 {
            return "Weniger als 1 Minute"
        }
        let minutes = Int(total / 60)
        let hours = minutes / 60
        let remainingMinutes = minutes % 60

        if hours > 0 {
            return "\(hours) Std. \(remainingMinutes) Min."
        } else {
            return "\(minutes) Min."
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let dict = try? JSONDecoder().decode([String: TimeInterval].self, from: data) else {
            return
        }
        self.records = dict
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: fileURL)
    }
}
