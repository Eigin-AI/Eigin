import Foundation

/// A profile reference embedded in a message or post response (sender/author).
struct AulaProfileFragment: Decodable {
    let fullName: String?
}

/// An HTML-bodied text field, as several Aula response shapes embed it.
struct AulaRichTextFragment: Decodable {
    let html: String?

    /// Aula message/post bodies come as HTML; strip tags for a plain-text preview.
    var plainText: String? {
        guard let html else { return nil }
        return html.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
