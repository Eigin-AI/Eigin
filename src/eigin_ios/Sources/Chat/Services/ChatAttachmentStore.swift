import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Protocol

/// Persists chat-attachment binary data on disk and normalises images before saving.
///
/// Bytes never enter SwiftData rows or the in-memory message window. ``ChatMessage``
/// carries only a lightweight ``MessageAttachment`` reference; callers load data
/// on demand (for request payloads) or render thumbnails (for the chat feed).
protocol ChatAttachmentStoring: Sendable {
    /// Normalises `imageData` (downscale, re-encode to JPEG) and saves it under `id`.
    /// Returns the resulting ``MessageAttachment`` populated with final dimensions
    /// and byte count.
    func save(imageData: Data, id: UUID) throws -> MessageAttachment

    /// Loads the raw bytes for the attachment with the given `id`.
    /// Returns `nil` when the file does not exist.
    func load(id: UUID) -> Data?

    /// Loads a small thumbnail-sized rendering of the attachment with the given
    /// `id`, for use in the chat feed and composer. Falls back to the full
    /// normalised image when no thumbnail file is present (e.g. attachments
    /// saved before thumbnails were introduced). Returns `nil` when neither
    /// file exists.
    func loadThumbnail(id: UUID) -> Data?

    /// Returns the on-disk file URL for the attachment with the given `id`,
    /// or `nil` when the file does not exist. Useful for handing the file to
    /// system viewers (e.g. QuickLook) that need a URL rather than raw bytes.
    func fileURL(for id: UUID) -> URL?

    /// Deletes the file for the given attachment `id`, if it exists.
    func delete(id: UUID)

    /// Deletes all attachments whose IDs are listed in `attachments`.
    /// Convenience for cleaning up a message's attachments.
    func deleteAll(_ attachments: [MessageAttachment])
}

// MARK: - Image normalisation constants

/// Normalisation limits shared across all in-scope providers.
///
/// Anthropic and OpenAI both impose ~5 MB per image and resize beyond ~2000 px
/// internally; Gemini's vision documentation uses similar figures. We apply a
/// conservative common maximum so a single normalised file is valid everywhere.
enum AttachmentNormalization {
    /// Maximum dimension (width or height) of a normalised image, in pixels.
    /// Anthropic recommends ≤1568 px; OpenAI auto-downscales above ~2048 px.
    /// 1024 px keeps chat images well within model detail needs while keeping
    /// per-image and total request payloads small when several are attached.
    static let maxDimension: CGFloat = 1024

    /// Maximum dimension of the separate thumbnail rendering saved alongside
    /// the normalised image. Sized to cover the largest thumbnail shown in the
    /// UI (88pt) at @3x, with headroom to spare.
    static let thumbnailMaxDimension: CGFloat = 264

    /// JPEG compression quality (0–1) applied when re-encoding.
    static let jpegQuality: CGFloat = 0.85

    /// Output MIME type after normalisation.
    static let outputMimeType = "image/jpeg"

    /// File extension for normalised images.
    static let outputExtension = "jpg"
}

// MARK: - Default implementation

/// Stores normalised images under `Application Support/ChatAttachments/<id>.jpg`.
struct DefaultChatAttachmentStore: ChatAttachmentStoring {
    private let root: URL

    init(root: URL) {
        self.root = root
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    // MARK: ChatAttachmentStoring

    func save(imageData: Data, id: UUID) throws -> MessageAttachment {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil) else {
            throw AttachmentStoreError.invalidImageData
        }

        // kCGImageSourceCreateThumbnailWithTransform bakes the EXIF orientation
        // tag into the pixel data, so photos taken in any orientation (not just
        // landscape) come out rotated correctly. This also performs the
        // downscale to maxDimension in the same pass.
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: AttachmentNormalization.maxDimension,
        ]
        guard let normalised = CGImageSourceCreateThumbnailAtIndex(
            source, 0, thumbnailOptions as CFDictionary
        ) else {
            throw AttachmentStoreError.invalidImageData
        }

        guard let jpegData = encode(normalised) else {
            throw AttachmentStoreError.encodingFailed
        }

        let url = deterministicFileURL(for: id)
        try jpegData.write(to: url, options: .atomic)

        // Best-effort: a missing thumbnail just falls back to the full image.
        if let thumbnail = CGImageSourceCreateThumbnailAtIndex(
            source, 0,
            [
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: AttachmentNormalization.thumbnailMaxDimension,
            ] as CFDictionary
        ), let thumbnailData = encode(thumbnail) {
            try? thumbnailData.write(to: deterministicThumbnailFileURL(for: id), options: .atomic)
        }

        return MessageAttachment(
            id: id,
            kind: .image,
            mimeType: AttachmentNormalization.outputMimeType,
            width: normalised.width,
            height: normalised.height,
            byteCount: jpegData.count
        )
    }

    func load(id: UUID) -> Data? {
        try? Data(contentsOf: deterministicFileURL(for: id))
    }

    func loadThumbnail(id: UUID) -> Data? {
        (try? Data(contentsOf: deterministicThumbnailFileURL(for: id))) ?? load(id: id)
    }

    func fileURL(for id: UUID) -> URL? {
        let url = deterministicFileURL(for: id)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func delete(id: UUID) {
        try? FileManager.default.removeItem(at: deterministicFileURL(for: id))
        try? FileManager.default.removeItem(at: deterministicThumbnailFileURL(for: id))
    }

    func deleteAll(_ attachments: [MessageAttachment]) {
        for attachment in attachments {
            delete(id: attachment.id)
        }
    }

    // MARK: Helpers

    private func deterministicFileURL(for id: UUID) -> URL {
        root.appendingPathComponent("\(id.uuidString).\(AttachmentNormalization.outputExtension)")
    }

    private func deterministicThumbnailFileURL(for id: UUID) -> URL {
        root.appendingPathComponent(
            "\(id.uuidString)_thumb.\(AttachmentNormalization.outputExtension)"
        )
    }

    /// Encodes `image` as JPEG using ``AttachmentNormalization/jpegQuality``.
    private func encode(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data as CFMutableData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { return nil }

        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: AttachmentNormalization.jpegQuality,
        ]
        CGImageDestinationAddImage(dest, image, options as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }
}

// MARK: - Errors

enum AttachmentStoreError: Error {
    case invalidImageData
    case encodingFailed
}
