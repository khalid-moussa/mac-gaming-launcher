import Foundation
import Synchronization

/// Locally tracked play time per game (keyed by `SteamGame.id`). Thread-safe; writes atomically.
public final class PlaytimeStore: Sendable {
    public struct Record: Codable, Sendable, Equatable {
        public var total: TimeInterval = 0
        public var lastPlayed: Date?
    }

    private let file: URL
    private let state: Mutex<[String: Record]>

    public init(file: URL) {
        self.file = file
        self.state = Mutex(Self.load(from: file))
    }

    public func record(for gameID: String) -> Record {
        state.withLock { $0[gameID] ?? Record() }
    }

    /// Adds a finished session. Sessions shorter than 5 seconds are ignored (failed launches).
    public func addSession(gameID: String, start: Date, end: Date = .now) {
        let duration = end.timeIntervalSince(start)
        guard duration >= 5 else { return }
        let snapshot = state.withLock { records -> [String: Record] in
            var record = records[gameID] ?? Record()
            record.total += duration
            record.lastPlayed = end
            records[gameID] = record
            return records
        }
        persist(snapshot)
    }

    private func persist(_ records: [String: Record]) {
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(records).write(to: file, options: .atomic)
        } catch {
            Log.storage.error("Spielzeit konnte nicht gespeichert werden: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func load(from file: URL) -> [String: Record] {
        guard let data = try? Data(contentsOf: file) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let records = try? decoder.decode([String: Record].self, from: data) { return records }
        // Never silently overwrite unreadable data: keep a backup.
        let backup = file.deletingPathExtension().appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970)).json")
        try? FileManager.default.copyItem(at: file, to: backup)
        Log.storage.error("playtime.json beschädigt – Sicherung unter \(backup.path, privacy: .public)")
        return [:]
    }

    public static func format(_ seconds: TimeInterval) -> String {
        guard seconds >= 60 else { return seconds > 0 ? "< 1 Min." : "—" }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute]
        formatter.unitsStyle = .abbreviated
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "de_DE")
        formatter.calendar = calendar
        return formatter.string(from: seconds) ?? "—"
    }
}
