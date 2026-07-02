@testable import Eigin
import Foundation
import ImageIO
import Testing
import UIKit
import UniformTypeIdentifiers

@Suite("ChatAttachmentStore")
struct ChatAttachmentStoreTests {
    // MARK: - Helpers

    private func makeStore() -> DefaultChatAttachmentStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChatAttachmentStoreTests-\(UUID().uuidString)")
        return DefaultChatAttachmentStore(root: dir)
    }

    /// Creates a small 10×10 white JPEG image as raw Data.
    private func smallImageData() -> Data {
        let size = CGSize(width: 10, height: 10)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        return image.jpegData(compressionQuality: 0.9)!
    }

    // MARK: - Round-trip

    @Test func writeReadRoundTrip() throws {
        let store = makeStore()
        let id = UUID()
        let data = smallImageData()

        let attachment = try store.save(imageData: data, id: id)

        #expect(attachment.id == id)
        #expect(attachment.kind == .image)
        #expect(attachment.mimeType == AttachmentNormalization.outputMimeType)
        #expect(attachment.byteCount > 0)

        let loaded = store.load(id: id)
        #expect(loaded != nil)
        #expect(loaded?.count == attachment.byteCount)
    }

    @Test func loadReturnsNilForMissingID() {
        let store = makeStore()
        let result = store.load(id: UUID())
        #expect(result == nil)
    }

    // MARK: - Thumbnails

    @Test func saveProducesLoadableThumbnail() throws {
        let store = makeStore()
        let id = UUID()
        _ = try store.save(imageData: smallImageData(), id: id)

        let thumbnail = store.loadThumbnail(id: id)
        #expect(thumbnail != nil)
    }

    @Test func loadThumbnailFallsBackToFullImageWhenThumbnailMissing() throws {
        // Simulates an attachment saved before thumbnails were introduced:
        // only the full-size file exists on disk.
        let store = makeStore()
        let id = UUID()
        let attachment = try store.save(imageData: smallImageData(), id: id)

        let thumbURL = try #require(store.fileURL(for: id)?
            .deletingLastPathComponent()
            .appendingPathComponent("\(id.uuidString)_thumb.jpg"))
        try? FileManager.default.removeItem(at: thumbURL)

        let thumbnail = store.loadThumbnail(id: id)
        #expect(thumbnail != nil)
        #expect(thumbnail?.count == attachment.byteCount)
    }

    @Test func loadThumbnailReturnsNilForMissingID() {
        let store = makeStore()
        let result = store.loadThumbnail(id: UUID())
        #expect(result == nil)
    }

    @Test func thumbnailDimensionsWithinLimit() throws {
        let store = makeStore()
        let size = CGSize(width: 2000, height: 2000)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            UIColor.blue.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        let data = try #require(image.jpegData(compressionQuality: 1.0))
        let id = UUID()
        _ = try store.save(imageData: data, id: id)

        let thumbnailData = try #require(store.loadThumbnail(id: id))
        let thumbnailImage = try #require(UIImage(data: thumbnailData))
        let maxDim = AttachmentNormalization.thumbnailMaxDimension
        #expect(thumbnailImage.size.width * thumbnailImage.scale <= maxDim)
        #expect(thumbnailImage.size.height * thumbnailImage.scale <= maxDim)
    }

    // MARK: - Delete

    @Test func deleteRemovesFile() throws {
        let store = makeStore()
        let id = UUID()
        _ = try store.save(imageData: smallImageData(), id: id)

        // File exists
        #expect(store.load(id: id) != nil)

        store.delete(id: id)

        // File gone
        #expect(store.load(id: id) == nil)
    }

    @Test func deleteRemovesThumbnailFile() throws {
        let store = makeStore()
        let id = UUID()
        _ = try store.save(imageData: smallImageData(), id: id)

        #expect(store.loadThumbnail(id: id) != nil)

        store.delete(id: id)

        #expect(store.loadThumbnail(id: id) == nil)
    }

    @Test func deleteNonExistentIsNoOp() {
        let store = makeStore()
        // Should not throw or crash
        store.delete(id: UUID())
    }

    @Test func deleteAllRemovesAllFiles() throws {
        let store = makeStore()
        let id1 = UUID()
        let id2 = UUID()
        let a1 = try store.save(imageData: smallImageData(), id: id1)
        let a2 = try store.save(imageData: smallImageData(), id: id2)

        store.deleteAll([a1, a2])

        #expect(store.load(id: id1) == nil)
        #expect(store.load(id: id2) == nil)
    }

    // MARK: - Normalisation

    @Test func normalisedImageDimensionsWithinLimit() throws {
        // Create an oversized image (2000×2000) and verify it is downscaled.
        let store = makeStore()
        let size = CGSize(width: 2000, height: 2000)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            UIColor.blue.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        let data = try #require(image.jpegData(compressionQuality: 1.0))

        let attachment = try store.save(imageData: data, id: UUID())

        let maxDim = Int(AttachmentNormalization.maxDimension)
        let w = attachment.width ?? 0
        let h = attachment.height ?? 0
        #expect(w <= maxDim)
        #expect(h <= maxDim)
        #expect(w > 0 && h > 0)
    }

    @Test func smallImageNotUpscaled() throws {
        let store = makeStore()
        let data = smallImageData() // 10×10

        let attachment = try store.save(imageData: data, id: UUID())

        // Should not be upscaled
        #expect((attachment.width ?? 0) <= 10)
        #expect((attachment.height ?? 0) <= 10)
    }

    /// Simulates a portrait photo: pixels are stored landscape (20×10) with an
    /// EXIF orientation tag of 6 (rotate 90° CW to display correctly). Only
    /// applying the transform yields the correct portrait dimensions (10×20).
    @Test func exifOrientationIsApplied() throws {
        let store = makeStore()
        let data = try #require(orientedImageData(
            pixelWidth: 20,
            pixelHeight: 10,
            exifOrientation: 6
        ))

        let attachment = try store.save(imageData: data, id: UUID())

        #expect(attachment.width == 10)
        #expect(attachment.height == 20)
    }

    /// Builds a JPEG whose raw pixel buffer is `pixelWidth`×`pixelHeight` but
    /// carries an EXIF orientation tag, mirroring how cameras store portrait
    /// photos as rotated landscape pixel data.
    private func orientedImageData(
        pixelWidth: Int,
        pixelHeight: Int,
        exifOrientation: UInt32
    ) -> Data? {
        let size = CGSize(width: pixelWidth, height: pixelHeight)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { ctx in
            UIColor.blue.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        guard let cgImage = image.cgImage else { return nil }

        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data as CFMutableData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { return nil }

        let options: [CFString: Any] = [
            kCGImagePropertyOrientation: exifOrientation,
        ]
        CGImageDestinationAddImage(dest, cgImage, options as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    // MARK: - Error handling

    @Test func invalidDataThrows() {
        let store = makeStore()
        let badData = Data("not an image".utf8)
        #expect(throws: AttachmentStoreError.self) {
            try store.save(imageData: badData, id: UUID())
        }
    }

    // MARK: - Attachment persistence round-trip

    @Test func attachmentCodecRoundTrip() throws {
        let original = MessageAttachment(
            id: UUID(),
            kind: .image,
            mimeType: "image/jpeg",
            width: 800,
            height: 600,
            byteCount: 50000
        )
        let encoded = try JSONEncoder().encode([original])
        let decoded = try JSONDecoder().decode([MessageAttachment].self, from: encoded)

        #expect(decoded.count == 1)
        let result = decoded[0]
        #expect(result.id == original.id)
        #expect(result.kind == original.kind)
        #expect(result.mimeType == original.mimeType)
        #expect(result.width == original.width)
        #expect(result.height == original.height)
        #expect(result.byteCount == original.byteCount)
    }
}
