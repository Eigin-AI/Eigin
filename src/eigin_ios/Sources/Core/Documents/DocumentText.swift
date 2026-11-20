import CoreFoundation
import Foundation

/// Validates document text and decodes declared text encodings and Unicode BOMs.
enum DocumentText {
    /// Checks for visible text without altering meaningful Unicode shaping or continuation offsets.
    static func hasReadableContent(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            guard !scalar.properties.isWhitespace,
                  !scalar.properties.isDefaultIgnorableCodePoint else { return false }
            switch scalar.properties.generalCategory {
            case .control, .format, .nonspacingMark, .spacingMark, .enclosingMark:
                return false
            default:
                return scalar
                    .value != 0x2800 // Braille blank has symbol category but no visible marks.
            }
        }
    }

    static func decode(_ data: Data, mimeType: String) throws -> String {
        let charset = mimeType.components(separatedBy: ";").dropFirst()
            .compactMap { parameter -> String? in
                let pair = parameter.split(separator: "=", maxSplits: 1)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                guard pair.count == 2, pair[0].lowercased() == "charset" else { return nil }
                return pair[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            }.first
        let encoding: String.Encoding
        // UTF-32 must precede UTF-16 because their little-endian BOMs share a prefix.
        if data.starts(with: [0xFF, 0xFE, 0, 0]) || data.starts(with: [0, 0, 0xFE, 0xFF]) {
            encoding = .utf32
        } else if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            encoding = .utf16
        } else if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            encoding = .utf8
        } else if let charset {
            let cfEncoding = CFStringConvertIANACharSetNameToEncoding(charset as CFString)
            guard cfEncoding != kCFStringEncodingInvalidId else {
                throw DocumentReadError.unreadable("Unsupported text encoding: \(charset).")
            }
            encoding = String
                .Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
        } else {
            encoding = .utf8
        }
        guard var text = String(data: data, encoding: encoding),
              !text.unicodeScalars
              .contains(where: { $0.value < 32 && ![9, 10, 13].contains($0.value) })
        else {
            throw DocumentReadError
                .unreadable(
                    "Attachment could not be decoded as plain text; it may be binary or use an unsupported encoding."
                )
        }
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        return text
    }
}
