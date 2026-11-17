import Foundation
import os

/// Structured logging. View in Console.app with subsystem `com.khalid.MacGamingLauncher`.
public enum Log {
    public static let subsystem = "com.khalid.MacGamingLauncher"
    public static let runtime = Logger(subsystem: subsystem, category: "runtime")
    public static let bottles = Logger(subsystem: subsystem, category: "bottles")
    public static let wine = Logger(subsystem: subsystem, category: "wine")
    public static let steam = Logger(subsystem: subsystem, category: "steam")
    public static let session = Logger(subsystem: subsystem, category: "session")
    public static let storage = Logger(subsystem: subsystem, category: "storage")
}

/// An error with a user-facing German message.
public struct LauncherError: LocalizedError, Sendable, Equatable {
    public let message: String
    public let detail: String?

    public init(_ message: String, detail: String? = nil) {
        self.message = message
        self.detail = detail
    }

    public var errorDescription: String? {
        if let detail, !detail.isEmpty { return "\(message)\n\(detail)" }
        return message
    }
}
