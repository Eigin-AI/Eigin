import Foundation

/// Metadata for an attachment scoped to its connected account and message.
struct EmailAttachment: Sendable, Equatable {
    let id: String
    let filename: String
    let mimeType: String
    var sizeBytes: Int?
    var unsupportedReason: String?

    var readable: Bool {
        unsupportedReason == nil && documentMimeType != nil
    }

    /// Chooses a reader; the reader must still validate the actual bytes.
    var documentMimeType: String? {
        let type = mimeType.components(separatedBy: ";")[0].trimmingCharacters(in: .whitespaces)
            .lowercased()
        if ["application/pdf", "text/plain"].contains(type) { return mimeType }
        guard type == "application/octet-stream" else { return nil }
        switch (filename as NSString).pathExtension.lowercased() {
        case "pdf": return "application/pdf"
        case "txt": return "text/plain"
        default: return nil
        }
    }

    var jsonObject: [String: Any] {
        var result: [String: Any] = [
            "id": id, "filename": filename, "mime_type": mimeType, "readable": readable,
        ]
        if let sizeBytes { result["size_bytes"] = sizeBytes }
        if !readable {
            result["unsupported_reason"] = unsupportedReason ?? "Only PDF and plain-text attachments are supported."
        }
        return result
    }
}

/// Selected attachment bytes, bounded before document parsing.
struct EmailAttachmentContent: Sendable {
    let metadata: EmailAttachment
    let data: Data
}

/// Limits shared by provider downloads and document reading.
enum EmailAttachmentLimits {
    static let decodedBytes = 10 * 1024 * 1024
    static let transportBytes = 16 * 1024 * 1024
    static let downloadSeconds: TimeInterval = 10

    static func validate(_ data: Data) throws {
        guard data.count <= decodedBytes else {
            throw EmailProviderError.requestFailed("Attachment exceeds the 10 MiB reading limit.")
        }
    }
}
