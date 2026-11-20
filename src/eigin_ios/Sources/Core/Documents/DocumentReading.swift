import Foundation

/// Resource limits shared by document readers and tool callers.
enum DocumentLimits {
    static let maximumInputBytes = 10 * 1024 * 1024
    static let maximumPages = 5
    static let minimumOutputCharacters = 100
    static let outputCharacters = 20000
    static let smallContextOutputCharacters = 2000
    static let operationSeconds: TimeInterval = 25
    static let pdfProcessingSeconds: TimeInterval = 10
    static let minimumRemainingSeconds: TimeInterval = 1
    static let readerPollInterval: Duration = .milliseconds(100)
}

/// Whether the requested document content could be extracted.
enum DocumentReadStatus: String, Sendable {
    case complete, partial, unsupported, unreadable
}

/// How a document or page was converted to text.
enum DocumentExtractionMethod: String, Sendable {
    case text
    case embeddedText = "embedded_text"
    case structuredOCR = "structured_ocr"
    case basicOCR = "basic_ocr"
}

/// Extracted page text with its method and optional layout warning.
struct DocumentPageContent: Sendable {
    let text: String
    let method: DocumentExtractionMethod
    var warning: String?
}

/// A bounded selection of document content. Page numbers are one-based; offsets count characters.
struct DocumentSelection: Sendable {
    var startPage = 1
    var pageCount = DocumentLimits.maximumPages
    var contentOffset = 0
    var ocr = false
    var outputLimit = DocumentLimits.outputCharacters
    var deadline = Date().addingTimeInterval(DocumentLimits.operationSeconds)
}

/// Extracted Markdown and explicit information about incomplete or uncertain content.
struct DocumentReadResult: Sendable {
    var status: DocumentReadStatus = .complete
    var content = ""
    var warnings: [String] = []
    var pageCount: Int?
    var methods: [String: DocumentExtractionMethod] = [:]
    var nextPage: Int?
    var nextContentOffset: Int?

    var jsonObject: [String: Any] {
        var result: [String: Any] = [
            "status": status.rawValue,
            "content": content,
            "extraction_methods": methods.mapValues(\.rawValue),
        ]
        if let pageCount { result["total_pages"] = pageCount }
        if let nextPage { result["next_page"] = nextPage }
        if let nextContentOffset { result["next_content_offset"] = nextContentOffset }
        return result
    }
}

/// Converts document bytes to text without sending the source document to a model.
protocol DocumentReading: Sendable {
    func read(data: Data, mimeType: String, selection: DocumentSelection) async throws
        -> DocumentReadResult
}

/// Invalid selection or document data that cannot safely be interpreted.
enum DocumentReadError: Error, LocalizedError {
    case invalidSelection
    case unreadable(String)

    var errorDescription: String? {
        switch self {
        case .invalidSelection: "Invalid document selection. Pages start at 1, page_count is 1–5, and content_offset must refer to a character in the selected content."
        case .unreadable(let reason): reason
        }
    }
}
