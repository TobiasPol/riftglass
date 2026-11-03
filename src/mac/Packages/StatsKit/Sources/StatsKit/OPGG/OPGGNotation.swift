import Foundation

/// A value of OP.GG's compact MCP output format.
public indirect enum NotationValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case list([NotationValue])
    case object(type: String, fields: [String: NotationValue])

    public subscript(key: String) -> NotationValue? {
        if case let .object(_, fields) = self {
            return fields[key]
        }
        return nil
    }

    public var double: Double? {
        if case let .number(value) = self {
            return value
        }
        return nil
    }

    public var int: Int? {
        double.map { Int($0) }
    }

    public var string: String? {
        if case let .string(value) = self {
            return value
        }
        return nil
    }

    public var list: [NotationValue] {
        if case let .list(values) = self {
            return values
        }
        return []
    }

    public var ints: [Int] {
        list.compactMap(\.int)
    }
}

public enum NotationError: Error, Equatable {
    case unexpectedEnd
    case unexpectedCharacter(Character, offset: Int)
    case unknownClass(String)
    case fieldCountMismatch(String, expected: Int, got: Int)
}

/// Parser for the format returned by OP.GG's MCP tools (verified in docs/SPIKE.md):
///
///     class Runes: id,primary_page_id
///
///     Result(Runes(8112,8100),[1,2],"text",null)
///
/// Class declarations give the field names; constructor calls list the values positionally.
public enum OPGGNotation {
    public static func parse(_ text: String) throws -> NotationValue {
        var schema: [String: [String]] = [:]
        var body: [Substring] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("class "), let colon = line.firstIndex(of: ":") {
                let name = line[line.index(line.startIndex, offsetBy: 6) ..< colon]
                    .trimmingCharacters(in: .whitespaces)
                schema[name] = line[line.index(after: colon)...].split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
            } else {
                body.append(line)
            }
        }
        var parser = NotationParser(text: body.joined(separator: "\n"), schema: schema)
        let value = try parser.parseValue()
        try parser.expectEnd()
        return value
    }
}

private struct NotationParser {
    private let chars: [Character]
    private let schema: [String: [String]]
    private var index = 0

    init(text: String, schema: [String: [String]]) {
        chars = Array(text)
        self.schema = schema
    }

    mutating func expectEnd() throws {
        skipWhitespace()
        if index < chars.count {
            throw NotationError.unexpectedCharacter(chars[index], offset: index)
        }
    }

    mutating func parseValue() throws -> NotationValue {
        skipWhitespace()
        guard index < chars.count else { throw NotationError.unexpectedEnd }
        let char = chars[index]
        if char == "\"" {
            return try .string(parseString())
        }
        if char == "[" {
            return try .list(parseSequence(open: "[", close: "]"))
        }
        if char == "-" || char.isNumber {
            return try parseNumber()
        }
        if char.isLetter || char == "_" {
            return try parseIdentifierValue()
        }
        throw NotationError.unexpectedCharacter(char, offset: index)
    }

    private mutating func parseIdentifierValue() throws -> NotationValue {
        let name = readIdentifier()
        switch name {
        case "null", "None": return .null
        case "true", "True": return .bool(true)
        case "false", "False": return .bool(false)
        default: break
        }
        guard let fieldNames = schema[name] else { throw NotationError.unknownClass(name) }
        let values = try parseSequence(open: "(", close: ")")
        guard values.count == fieldNames.count else {
            throw NotationError.fieldCountMismatch(name, expected: fieldNames.count, got: values.count)
        }
        return .object(type: name, fields: Dictionary(uniqueKeysWithValues: zip(fieldNames, values)))
    }

    private mutating func parseSequence(open: Character, close: Character) throws -> [NotationValue] {
        try expect(open)
        var values: [NotationValue] = []
        skipWhitespace()
        if peek() == close {
            index += 1
            return values
        }
        while true {
            try values.append(parseValue())
            skipWhitespace()
            guard let next = peek() else { throw NotationError.unexpectedEnd }
            index += 1
            if next == close {
                return values
            }
            guard next == "," else { throw NotationError.unexpectedCharacter(next, offset: index - 1) }
        }
    }

    private mutating func parseString() throws -> String {
        try expect("\"")
        var result = ""
        while let char = peek() {
            index += 1
            switch char {
            case "\"": return result
            case "\\": try result.append(parseEscape())
            default: result.append(char)
            }
        }
        throw NotationError.unexpectedEnd
    }

    private mutating func parseEscape() throws -> Character {
        guard let char = peek() else { throw NotationError.unexpectedEnd }
        index += 1
        switch char {
        case "n": return "\n"
        case "t": return "\t"
        case "u":
            guard index + 4 <= chars.count,
                  let code = UInt32(String(chars[index ..< index + 4]), radix: 16),
                  let scalar = Unicode.Scalar(code)
            else { throw NotationError.unexpectedCharacter(char, offset: index) }
            index += 4
            return Character(scalar)
        default: return char
        }
    }

    private mutating func parseNumber() throws -> NotationValue {
        let start = index
        while let char = peek(), char.isNumber || "-+.eE".contains(char) {
            index += 1
        }
        guard let value = Double(String(chars[start ..< index])) else {
            throw NotationError.unexpectedCharacter(chars[start], offset: start)
        }
        return .number(value)
    }

    private mutating func readIdentifier() -> String {
        let start = index
        while let char = peek(), char.isLetter || char.isNumber || char == "_" {
            index += 1
        }
        return String(chars[start ..< index])
    }

    private mutating func expect(_ char: Character) throws {
        skipWhitespace()
        guard let next = peek() else { throw NotationError.unexpectedEnd }
        guard next == char else { throw NotationError.unexpectedCharacter(next, offset: index) }
        index += 1
    }

    private func peek() -> Character? {
        index < chars.count ? chars[index] : nil
    }

    private mutating func skipWhitespace() {
        while let char = peek(), char.isWhitespace {
            index += 1
        }
    }
}
