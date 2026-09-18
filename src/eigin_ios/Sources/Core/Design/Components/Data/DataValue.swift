import Foundation

/// The document a data card reads out: any JSON shape.
///
/// Objects keep their source key order and booleans stay distinct from
/// numbers — the two things `JSONSerialization`'s dictionaries cannot promise.
indirect enum DataValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([DataValue])
    case object([Entry])

    struct Entry: Equatable {
        let key: String
        let value: DataValue
    }

    /// Parses a JSON string into a document. `nil` when the text does not read
    /// as JSON.
    static func parse(_ raw: String) -> DataValue? {
        var reader = JSONReader(text: raw)
        guard let value = reader.value() else { return nil }
        reader.skipWhitespace()
        // Whole-text values only: a fragment would render as partial truth.
        return reader.isAtEnd ? value : nil
    }
}

/// A minimal JSON reader — just enough to hand ``DataValue`` objects in
/// document order, which `JSONSerialization`'s dictionaries cannot.
private struct JSONReader {
    private let text: Substring
    private var index: Substring.Index

    init(text: String) {
        self.text = Substring(text)
        index = self.text.startIndex
    }

    var isAtEnd: Bool {
        index >= text.endIndex
    }

    mutating func skipWhitespace() {
        while !isAtEnd, text[index].isWhitespace {
            index = text.index(after: index)
        }
    }

    private mutating func advance() {
        index = text.index(after: index)
    }

    private func peek() -> Character? {
        isAtEnd ? nil : text[index]
    }

    private mutating func read(expected: Character) -> Bool {
        if peek() == expected {
            advance()
            return true
        }
        return false
    }

    /// Reads a value at the cursor, if one is there.
    mutating func value() -> DataValue? {
        skipWhitespace()
        switch peek() {
        case "{": return object()
        case "[": return array()
        case "\"": return string().map { DataValue.string($0) }
        case "t": return literal("true").map { _ in DataValue.bool(true) }
        case "f": return literal("false").map { _ in DataValue.bool(false) }
        case "n": return literal("null").map { _ in DataValue.null }
        case _ where peek()?.isNumber == true || peek() == "-": return number()
        default: return nil
        }
    }

    private mutating func object() -> DataValue? {
        advance() // {
        var entries: [DataValue.Entry] = []
        skipWhitespace()
        if read(expected: "}") { return .object(entries) }
        while true {
            skipWhitespace()
            guard let key = string() else { return nil }
            skipWhitespace()
            guard read(expected: ":"), let value = value() else { return nil }
            entries.append(DataValue.Entry(key: key, value: value))
            skipWhitespace()
            if read(expected: ",") { continue }
            if read(expected: "}") { return .object(entries) }
            return nil
        }
    }

    private mutating func array() -> DataValue? {
        advance() // [
        var items: [DataValue] = []
        skipWhitespace()
        if read(expected: "]") { return .array(items) }
        while true {
            guard let value = value() else { return nil }
            items.append(value)
            skipWhitespace()
            if read(expected: ",") { continue }
            if read(expected: "]") { return .array(items) }
            return nil
        }
    }

    private mutating func string() -> String? {
        guard read(expected: "\"") else { return nil }
        var result = ""
        while let character = peek() {
            advance()
            if character == "\"" { return result }
            if character != "\\" {
                result.append(character)
                continue
            }
            guard let escaped = peek() else { return nil }
            advance()
            switch escaped {
            case "\"": result.append("\"")
            case "\\": result.append("\\")
            case "/": result.append("/")
            case "b": result.append("\u{8}")
            case "f": result.append("\u{C}")
            case "n": result.append("\n")
            case "r": result.append("\r")
            case "t": result.append("\t")
            case "u": guard let scalar = unicodeEscape() else { return nil }
                result.append(scalar)
            default: return nil
            }
        }
        return nil
    }

    /// One `\uXXXX` escape, joining a surrogate pair into a single scalar.
    /// `nil` when the hex digits are not hex: a mangled escape is malformed
    /// JSON, not a blank.
    private mutating func unicodeEscape() -> Character? {
        guard let high = hex4() else { return nil }
        guard !(0xD800 ... 0xDBFF).contains(high) else {
            guard read(expected: "\\"), read(expected: "u"), let low = hex4() else { return nil }
            guard (0xDC00 ... 0xDFFF).contains(low) else { return nil }
            let scalar = 0x10000 + ((high - 0xD800) << 10) + (low - 0xDC00)
            return Character(Unicode.Scalar(scalar) ?? "�")
        }
        guard let scalar = Unicode.Scalar(high) else { return nil }
        return Character(scalar)
    }

    private mutating func hex4() -> Int? {
        var value = 0
        for _ in 0 ..< 4 {
            guard let digit = peek()?.hexDigitValue else { return nil }
            advance()
            value = value * 16 + digit
        }
        return value
    }

    private mutating func literal(_ expected: String) -> Bool? {
        for character in expected {
            guard read(expected: character) else { return nil }
        }
        return true
    }

    private mutating func number() -> DataValue? {
        let start = index
        while let character = peek(), character.isNumber || "-+.eE".contains(character) {
            advance()
        }
        guard index > start, let value = Double(text[start ..< index]) else { return nil }
        return .number(value)
    }
}
