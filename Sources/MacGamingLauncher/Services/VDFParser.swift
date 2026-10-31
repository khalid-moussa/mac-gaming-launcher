import Foundation

/// A parser for Valve's KeyValues (VDF) format used by Steam for `libraryfolders.vdf` and `appmanifest_*.acf`.
public enum VDFValue {
    case string(String)
    case dictionary([String: VDFValue])

    public var stringValue: String? {
        if case .string(let str) = self { return str }
        return nil
    }

    public var dictionaryValue: [String: VDFValue]? {
        if case .dictionary(let dict) = self { return dict }
        return nil
    }

    public subscript(key: String) -> VDFValue? {
        guard case .dictionary(let dict) = self else { return nil }
        return dict[key]
    }
}

public final class VDFParser {

    public static func parse(string: String) throws -> [String: VDFValue] {
        var tokens = tokenize(string)
        var result: [String: VDFValue] = [:]

        while !tokens.isEmpty {
            guard let key = tokens.first?.content else { break }
            tokens.removeFirst()

            guard !tokens.isEmpty else { break }

            let next = tokens.first!
            if next.type == .openBrace {
                tokens.removeFirst()
                let subDict = try parseDictionary(tokens: &tokens)
                result[key] = .dictionary(subDict)
            } else if next.type == .string {
                tokens.removeFirst()
                result[key] = .string(next.content)
            }
        }

        return result
    }

    private static func parseDictionary(tokens: inout [Token]) throws -> [String: VDFValue] {
        var dict: [String: VDFValue] = [:]

        while !tokens.isEmpty {
            let token = tokens.removeFirst()
            if token.type == .closeBrace {
                return dict
            }

            guard token.type == .string else {
                continue
            }

            guard !tokens.isEmpty else { break }
            let next = tokens.first!

            if next.type == .openBrace {
                tokens.removeFirst()
                let subDict = try parseDictionary(tokens: &tokens)
                dict[token.content] = .dictionary(subDict)
            } else if next.type == .string {
                tokens.removeFirst()
                dict[token.content] = .string(next.content)
            }
        }

        return dict
    }

    private enum TokenType {
        case string
        case openBrace
        case closeBrace
    }

    private struct Token {
        let type: TokenType
        let content: String
    }

    private static func tokenize(_ input: String) -> [Token] {
        var tokens: [Token] = []
        var iterator = input.makeIterator()
        var currentChar = iterator.next()

        while let char = currentChar {
            // Skip whitespace
            if char.isWhitespace {
                currentChar = iterator.next()
                continue
            }

            // Comments (// or #)
            if char == "/" {
                let next = iterator.next()
                if next == "/" {
                    // Skip to newline
                    while let c = iterator.next(), c != "\n" && c != "\r" {}
                    currentChar = iterator.next()
                    continue
                } else {
                    currentChar = next
                    continue
                }
            }

            if char == "{" {
                tokens.append(Token(type: .openBrace, content: "{"))
                currentChar = iterator.next()
                continue
            }

            if char == "}" {
                tokens.append(Token(type: .closeBrace, content: "}"))
                currentChar = iterator.next()
                continue
            }

            // Quoted string
            if char == "\"" {
                var stringVal = ""
                var escaped = false
                while let c = iterator.next() {
                    if escaped {
                        stringVal.append(c)
                        escaped = false
                    } else if c == "\\" {
                        escaped = true
                    } else if c == "\"" {
                        break
                    } else {
                        stringVal.append(c)
                    }
                }
                tokens.append(Token(type: .string, content: stringVal))
                currentChar = iterator.next()
                continue
            }

            // Bare string (unquoted token)
            var bare = String(char)
            while let c = iterator.next() {
                if c.isWhitespace || c == "{" || c == "}" || c == "\"" {
                    currentChar = c
                    break
                }
                bare.append(c)
            }
            tokens.append(Token(type: .string, content: bare))
        }

        return tokens
    }
}
