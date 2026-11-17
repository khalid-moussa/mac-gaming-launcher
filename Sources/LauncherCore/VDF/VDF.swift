import Foundation

/// A node of Valve's text KeyValues format (`*.vdf`, `appmanifest_*.acf`).
public enum VDFNode: Sendable, Equatable {
    case value(String)
    case object(VDFObject)

    public var string: String? {
        if case .value(let value) = self { return value }
        return nil
    }

    public var object: VDFObject? {
        if case .object(let object) = self { return object }
        return nil
    }

    /// Case-insensitive child lookup (Steam itself treats keys case-insensitively, e.g. `appid` vs `appID`).
    public subscript(key: String) -> VDFNode? { object?[key] }
}

/// An ordered key/value object. Keys are matched case-insensitively; for duplicate keys the last one wins.
public struct VDFObject: Sendable, Equatable {
    public struct Entry: Sendable, Equatable {
        public let key: String
        public let node: VDFNode
    }

    public private(set) var entries: [Entry] = []

    public init(entries: [Entry] = []) { self.entries = entries }

    public subscript(key: String) -> VDFNode? {
        entries.last { $0.key.caseInsensitiveCompare(key) == .orderedSame }?.node
    }

    mutating func append(_ key: String, _ node: VDFNode) {
        entries.append(Entry(key: key, node: node))
    }
}

public enum VDFError: Error, Equatable, Sendable {
    case unexpectedClosingBrace(offset: Int)
    case unexpectedOpeningBrace(offset: Int)
}

/// Parser for Valve's text KeyValues.
///
/// Supports quoted and unquoted tokens, the escapes `\n \t \\ \"`, `//` comments, `#include`/`#base` directives
/// (ignored) and `[$CONDITION]` suffixes (ignored). Truncated input yields whatever was parsed so far instead of failing,
/// because Steam rewrites these files non-atomically.
public enum VDF {
    public static func parse(_ text: String) throws -> VDFObject {
        var tokenizer = Tokenizer(bytes: Array(text.utf8))
        return try parseObject(&tokenizer, isRoot: true)
    }

    /// Parses the raw bytes: Steam writes UTF-8; tokens that aren't valid UTF-8 (very old files) are read as Latin-1.
    public static func parse(contentsOf url: URL) throws -> VDFObject {
        var tokenizer = Tokenizer(bytes: Array(try Data(contentsOf: url)))
        return try parseObject(&tokenizer, isRoot: true)
    }

    static func decodeText<Bytes: Collection<UInt8>>(_ bytes: Bytes) -> String {
        String(validating: bytes, as: UTF8.self) ?? String(String.UnicodeScalarView(bytes.map { Unicode.Scalar($0) }))
    }

    private static func parseObject(_ tokenizer: inout Tokenizer, isRoot: Bool) throws -> VDFObject {
        var object = VDFObject()
        while let token = tokenizer.next() {
            switch token.kind {
            case .close:
                if isRoot { throw VDFError.unexpectedClosingBrace(offset: token.offset) }
                return object
            case .open:
                throw VDFError.unexpectedOpeningBrace(offset: token.offset)
            case .text(let key):
                guard let valueToken = tokenizer.next() else { return object }
                switch valueToken.kind {
                case .open:
                    object.append(key, .object(try parseObject(&tokenizer, isRoot: false)))
                case .text(let value):
                    object.append(key, .value(value))
                case .close:
                    // Key without value directly before `}` — tolerate and close the object.
                    if isRoot { throw VDFError.unexpectedClosingBrace(offset: valueToken.offset) }
                    return object
                }
            }
        }
        return object
    }

    struct Token {
        enum Kind { case open, close, text(String) }
        let kind: Kind
        let offset: Int
    }

    struct Tokenizer {
        let bytes: [UInt8]
        var index = 0

        init(bytes: [UInt8]) {
            self.bytes = bytes
            // Skip UTF-8 BOM.
            if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { index = 3 }
        }

        mutating func next() -> Token? {
            while index < bytes.count {
                let byte = bytes[index]
                switch byte {
                case UInt8(ascii: " "), UInt8(ascii: "\t"), UInt8(ascii: "\n"), UInt8(ascii: "\r"), 0:
                    index += 1
                case UInt8(ascii: "/") where peek(1) == UInt8(ascii: "/"):
                    skipLine()
                case UInt8(ascii: "#"):
                    // #include / #base directives: ignore the whole line.
                    skipLine()
                case UInt8(ascii: "["):
                    // Conditional like [$WIN32]: ignore.
                    while index < bytes.count, bytes[index] != UInt8(ascii: "]"), bytes[index] != UInt8(ascii: "\n") { index += 1 }
                    index += 1
                case UInt8(ascii: "{"):
                    defer { index += 1 }
                    return Token(kind: .open, offset: index)
                case UInt8(ascii: "}"):
                    defer { index += 1 }
                    return Token(kind: .close, offset: index)
                case UInt8(ascii: "\""):
                    return quoted()
                default:
                    return bare()
                }
            }
            return nil
        }

        private func peek(_ distance: Int) -> UInt8? {
            index + distance < bytes.count ? bytes[index + distance] : nil
        }

        private mutating func skipLine() {
            while index < bytes.count, bytes[index] != UInt8(ascii: "\n") { index += 1 }
        }

        /// `nil` for a string cut off by the end of the file: a half-read value is worse than none
        /// (`"StateFlags" "10` instead of `"1026"`), so the truncated pair is dropped.
        private mutating func quoted() -> Token? {
            let start = index
            index += 1 // opening quote
            var buffer: [UInt8] = []
            var terminated = false
            while index < bytes.count {
                let byte = bytes[index]
                if byte == UInt8(ascii: "\"") { index += 1; terminated = true; break }
                if byte == UInt8(ascii: "\\"), let escaped = peek(1) {
                    switch escaped {
                    case UInt8(ascii: "n"): buffer.append(UInt8(ascii: "\n"))
                    case UInt8(ascii: "t"): buffer.append(UInt8(ascii: "\t"))
                    case UInt8(ascii: "\\"): buffer.append(UInt8(ascii: "\\"))
                    case UInt8(ascii: "\""): buffer.append(UInt8(ascii: "\""))
                    default: buffer.append(contentsOf: [byte, escaped])
                    }
                    index += 2
                    continue
                }
                buffer.append(byte)
                index += 1
            }
            guard terminated else { return nil }
            return Token(kind: .text(VDF.decodeText(buffer)), offset: start)
        }

        private mutating func bare() -> Token {
            let start = index
            while index < bytes.count {
                switch bytes[index] {
                case UInt8(ascii: " "), UInt8(ascii: "\t"), UInt8(ascii: "\n"), UInt8(ascii: "\r"),
                     UInt8(ascii: "{"), UInt8(ascii: "}"), UInt8(ascii: "\""), 0:
                    return Token(kind: .text(VDF.decodeText(bytes[start..<index])), offset: start)
                default:
                    index += 1
                }
            }
            return Token(kind: .text(VDF.decodeText(bytes[start..<index])), offset: start)
        }
    }
}
