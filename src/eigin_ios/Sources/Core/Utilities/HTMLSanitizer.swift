import Foundation

/// Errors specific to web tools (fetch / search).
enum WebToolError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case blocked
    case rateLimited
    case httpError(Int)
    case decodingFailed
    case emptyContent
    case unsupportedContentType(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: "The URL is invalid."
        case .invalidResponse: "Received an invalid response."
        case .blocked: "Access was blocked by the server (403 Forbidden)."
        case .rateLimited: "Rate-limited by the server (429 Too Many Requests)."
        case .httpError(let code): "HTTP error \(code)."
        case .decodingFailed: "Failed to decode the response body."
        case .emptyContent: "The page returned no usable text content."
        case .unsupportedContentType(let mimeType):
            "The URL points to binary content (\(mimeType)) that cannot be fetched as text."
        }
    }
}

/// Shared HTML-to-plain-text utility used by ``WebSearchTool`` and ``WebFetchTool``.
enum HTMLSanitizer {
    static let maxOutputLength = 20000
    static let requestTimeout: TimeInterval = 15
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

    // MARK: - Fetch + Sanitize

    /// Fetch a URL and return sanitised plain text.
    /// - Parameter session: Injectable for tests; defaults to the shared session.
    static func fetchAndSanitize(
        url: URL,
        session: URLSession = .shared
    ) async throws -> (text: String, warnings: [String]) {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = requestTimeout

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw WebToolError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200 ..< 300: break
        case 403: throw WebToolError.blocked
        case 429: throw WebToolError.rateLimited
        default: throw WebToolError.httpError(httpResponse.statusCode)
        }

        // Reject binary content — decoding it as text yields garbage.
        if let mimeType = httpResponse.mimeType, !Self.isTextual(mimeType) {
            throw WebToolError.unsupportedContentType(mimeType)
        }

        // Attempt UTF-8, fall back to ISO Latin-1
        let html: String
        if let utf8 = String(data: data, encoding: .utf8) {
            html = utf8
        } else if let latin1 = String(data: data, encoding: .isoLatin1) {
            html = latin1
        } else {
            throw WebToolError.decodingFailed
        }

        let result = sanitize(html)
        if result.text.isEmpty {
            throw WebToolError.emptyContent
        }
        return result
    }

    // MARK: - Sanitize

    /// Whether a MIME type identifies textual content this sanitizer can process.
    private static func isTextual(_ mimeType: String) -> Bool {
        mimeType.hasPrefix("text/")
            || mimeType.contains("html")
            || mimeType.contains("xml")
            || mimeType.contains("json")
            || mimeType.contains("javascript")
    }

    /// Convert raw HTML to plain text.
    static func sanitize(_ html: String) -> (text: String, warnings: [String]) {
        var text = html
        var warnings: [String] = []

        // 1. Remove script, style, noscript, head blocks (content + tags)
        let blockTags = ["script", "style", "noscript", "head"]
        for tag in blockTags {
            text = text.replacingOccurrences(
                of: "<\(tag)[^>]*>[\\s\\S]*?</\(tag)>",
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }

        // 2. Replace block-closing tags with newlines
        let newlineTags = ["<br[^>]*>", "</p>", "</div>", "</li>", "</tr>"]
        for pattern in newlineTags {
            text = text.replacingOccurrences(
                of: pattern,
                with: "\n",
                options: [.regularExpression, .caseInsensitive]
            )
        }

        // 3. Strip all remaining HTML tags
        text = text.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )

        // 4. Decode HTML entities
        text = decodeHTMLEntities(text)

        // 5. Collapse whitespace:
        //    - Any whitespace run containing a newline → single newline
        //    - Remaining horizontal whitespace runs → single space
        text = text.replacingOccurrences(
            of: "[ \\t]*\\n[ \\t\\n]*",
            with: "\n",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: "[ \\t]{2,}",
            with: " ",
            options: .regularExpression
        )

        // 6. Trim
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // 7. Truncate
        if text.count > maxOutputLength {
            text = String(text.prefix(maxOutputLength))
            warnings.append("Content truncated to \(maxOutputLength) characters.")
        }

        return (text, warnings)
    }

    // MARK: - Entity Decoding

    private static func decodeHTMLEntities(_ string: String) -> String {
        var result = string

        // Named entities
        let namedEntities: [(String, String)] = [
            ("&amp;", "&"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&quot;", "\""),
            ("&#39;", "'"),
            ("&apos;", "'"),
            ("&nbsp;", " "),
        ]
        for (entity, char) in namedEntities {
            result = result.replacingOccurrences(of: entity, with: char)
        }

        // Numeric decimal entities: &#NNN;
        if let regex = try? NSRegularExpression(pattern: "&#(\\d+);") {
            let nsRange = NSRange(result.startIndex..., in: result)
            let matches = regex.matches(in: result, range: nsRange).reversed()
            for match in matches {
                guard let codeRange = Range(match.range(at: 1), in: result),
                      let code = UInt32(result[codeRange]),
                      let scalar = Unicode.Scalar(code)
                else { continue }
                let charRange = Range(match.range, in: result)!
                result.replaceSubrange(charRange, with: String(scalar))
            }
        }

        // Numeric hex entities: &#xHHH;
        if let regex = try? NSRegularExpression(pattern: "&#x([0-9a-fA-F]+);") {
            let nsRange = NSRange(result.startIndex..., in: result)
            let matches = regex.matches(in: result, range: nsRange).reversed()
            for match in matches {
                guard let codeRange = Range(match.range(at: 1), in: result),
                      let code = UInt32(result[codeRange], radix: 16),
                      let scalar = Unicode.Scalar(code)
                else { continue }
                let charRange = Range(match.range, in: result)!
                result.replaceSubrange(charRange, with: String(scalar))
            }
        }

        return result
    }
}
