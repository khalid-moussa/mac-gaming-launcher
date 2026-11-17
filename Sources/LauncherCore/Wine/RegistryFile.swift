import Foundation

/// Builds a `.reg` file for `wine reg import`.
///
/// Wine only imports UTF-16LE files with a byte-order mark; without it the import silently does nothing.
/// (`regedit /S` is avoided: it can show a dialog and never exit.)
public struct RegistryFile: Sendable, Equatable {
    public enum Value: Sendable, Equatable {
        case string(String)
        case dword(UInt32)
        /// Removes the value (`"name"=-`).
        case delete
    }

    public private(set) var sections: [(key: String, values: [(name: String, value: Value)])] = []

    public init() {}

    public static func == (lhs: RegistryFile, rhs: RegistryFile) -> Bool { lhs.text == rhs.text }

    public var isEmpty: Bool { sections.allSatisfy { $0.values.isEmpty } }

    public mutating func set(_ key: String, _ name: String, _ value: Value) {
        if let index = sections.firstIndex(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame }) {
            if let valueIndex = sections[index].values.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                sections[index].values[valueIndex].value = value
            } else {
                sections[index].values.append((name, value))
            }
        } else {
            sections.append((key, [(name, value)]))
        }
    }

    public var text: String {
        var lines = ["Windows Registry Editor Version 5.00", ""]
        for section in sections where !section.values.isEmpty {
            lines.append("[\(section.key)]")
            for (name, value) in section.values {
                let quotedName = "\"\(Self.escape(name))\""
                switch value {
                case .string(let string): lines.append("\(quotedName)=\"\(Self.escape(string))\"")
                case .dword(let number): lines.append("\(quotedName)=dword:\(String(format: "%08x", number))")
                case .delete: lines.append("\(quotedName)=-")
                }
            }
            lines.append("")
        }
        return lines.joined(separator: "\r\n")
    }

    /// UTF-16LE with BOM.
    public var data: Data {
        var data = Data([0xFF, 0xFE])
        data.append(text.data(using: .utf16LittleEndian)!)
        return data
    }

    static func escape(_ string: String) -> String {
        string.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
