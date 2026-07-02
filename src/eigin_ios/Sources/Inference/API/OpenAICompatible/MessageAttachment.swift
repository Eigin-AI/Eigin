import Foundation

/// A lightweight reference to a locally-stored chat attachment (e.g. an image).
struct MessageAttachment: Codable, Sendable, Identifiable, Equatable {
    /// Stable unique identifier; used to derive the on-disk filename.
    let id: UUID

    /// Type of attachment content.
    var kind: AttachmentKind

    /// IANA media type (e.g. `"image/jpeg"`, `"image/png"`).
    var mimeType: String

    /// Pixel width of the image, if known.
    var width: Int?

    /// Pixel height of the image, if known.
    var height: Int?

    /// Byte size of the stored (normalized) data.
    var byteCount: Int

    init(
        id: UUID = UUID(),
        kind: AttachmentKind,
        mimeType: String,
        width: Int? = nil,
        height: Int? = nil,
        byteCount: Int
    ) {
        self.id = id
        self.kind = kind
        self.mimeType = mimeType
        self.width = width
        self.height = height
        self.byteCount = byteCount
    }
}

/// The category of attachment content.
enum AttachmentKind: String, Codable, Sendable {
    case image
}
