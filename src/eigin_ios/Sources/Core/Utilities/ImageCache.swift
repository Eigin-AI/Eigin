import CryptoKit
import Foundation
import UIKit

/// Caches chat images so a picture the user has consented to load stays
/// loaded — across scrolls, and across restarts on disk.
///
/// Disk files live under `Caches/ImageCache/`, keyed by a SHA-256 of the
/// source: purgeable by the OS, excluded from backups, and bounded by a soft
/// byte budget that evicts the oldest first. Re-withholding after a purge is
/// by design.
actor ImageCache {
    private static let byteBudget = 50 * 1024 * 1024

    private let directory: URL

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 45
        return URLSession(configuration: configuration)
    }()

    /// The one in-flight network fetch per source, so a fast scroll doesn't
    /// start duplicate requests.
    private var inflight: [String: Task<Data?, Never>] = [:]

    /// Decoded images for the current session. A card that comes back on screen
    /// after a list recycle reads this synchronously in its `init`, so a picture
    /// you already consented to never flashes back to withheld.
    private let remembered = ImageMemoryCache()

    // MARK: - Session memory (synchronous, any thread)

    nonisolated func cachedImage(_ src: String) -> UIImage? {
        remembered.image(for: src)
    }

    nonisolated func remember(_ image: UIImage, for src: String) {
        remembered.store(image, for: src)
    }

    /// Remembers a failed load, so a recycled view shows failed rather than
    /// re-withholding.
    nonisolated func rememberFailure(_ src: String) {
        remembered.markFailed(src)
    }

    nonisolated func isKnownFailed(_ src: String) -> Bool {
        remembered.isFailed(src)
    }

    init(directory: URL? = nil) {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        self.directory = directory ?? caches.appending(path: "ImageCache")
        try? FileManager.default.createDirectory(
            at: self.directory,
            withIntermediateDirectories: true
        )
    }

    // MARK: - API

    /// Cached bytes if present, else nil. No network. Used on appear so a
    /// remote image you've already consented to load shows loaded directly.
    func data(for src: String) async -> Data? {
        if let local = Self.localData(src) {
            return local
        }
        guard Self.isRemote(src) else { return nil }
        do {
            return try Data(contentsOf: fileURL(src))
        } catch {
            return nil
        }
    }

    /// True while a download for `src` is running. A recycled view uses this to
    /// ride along on the consented fetch it can no longer observe, instead of
    /// flipping back to withheld mid-download.
    func isFetching(_ src: String) async -> Bool {
        inflight[src] != nil
    }

    /// Bytes for `src`, fetching from the network when remote and uncached,
    /// with a write-through to disk. Nil on transport or decode failure.
    /// Data and file sources resolve directly and are never cached.
    func fetch(_ src: String) async -> Data? {
        if let local = Self.localData(src) {
            return local
        }
        guard Self.isRemote(src) else { return nil }

        if let running = inflight[src] {
            return await running.value
        }
        let task = Task<Data?, Never> {
            await self.download(src)
        }
        inflight[src] = task
        let data = await task.value
        inflight[src] = nil
        return data
    }

    /// A temp file URL holding the cached bytes, for handing to QuickLook. The
    /// extension is guessed from the source URL or the byte signature, since
    /// QuickLook picks its previewer by file type.
    func previewFile(for src: String) async -> URL? {
        guard let data = await data(for: src) else { return nil }
        let name = Self.digest(src)
        let file = FileManager.default.temporaryDirectory
            .appending(path: "image-preview-\(name).\(Self.fileExtension(of: data, or: src))")
        do {
            try data.write(to: file, options: .atomic)
            return file
        } catch {
            return nil
        }
    }

    // MARK: - Internals

    private func download(_ src: String) async -> Data? {
        guard let url = URL.fromMixedEncodingString(src) else { return nil }
        do {
            let (data, response) = try await Self.session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            guard UIImage(data: data) != nil else { return nil }
            try? data.write(to: fileURL(src), options: .atomic)
            await evictIfNeeded()
            return data
        } catch {
            return nil
        }
    }

    /// Deletes the oldest files by modification time until the store is back
    /// under the byte budget. Runs on the actor, so it never races a fetch.
    private func evictIfNeeded() async {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
        )) ?? []
        guard !files.isEmpty else { return }

        let entries = files.compactMap { url -> (url: URL, date: Date, size: Int)? in
            let values = try? url.resourceValues(forKeys: [
                .contentModificationDateKey,
                .fileSizeKey,
            ])
            guard let size = values?.fileSize else { return nil }
            return (url, values?.contentModificationDate ?? .distantPast, size)
        }
        var total = entries.reduce(0) { $0 + $1.size }
        guard total > Self.byteBudget else { return }

        for entry in entries.sorted(by: { $0.date < $1.date }) {
            guard total > Self.byteBudget else { return }
            try? FileManager.default.removeItem(at: entry.url)
            total -= entry.size
        }
    }

    private func fileURL(_ src: String) -> URL {
        directory.appending(path: Self.digest(src))
    }

    // MARK: - Source helpers

    /// Bytes already on the device: decoded data URIs and file URLs. Data URIs
    /// carry no host, so they skip the withheld state and load directly.
    private static func localData(_ src: String) -> Data? {
        if src.lowercased().hasPrefix("data:") {
            return dataURIDecoded(src)
        }
        guard let url = URL.fromMixedEncodingString(src), url.isFileURL else { return nil }
        return try? Data(contentsOf: url)
    }

    private static func dataURIDecoded(_ src: String) -> Data? {
        guard let comma = src.firstIndex(of: ","), comma != src.endIndex else { return nil }
        let payload = String(src[src.index(after: comma)...])
        if src.range(of: ";base64,", options: .caseInsensitive) != nil {
            return Data(base64Encoded: payload)
        }
        return payload.removingPercentEncoding?.data(using: .utf8)
    }

    private static func isRemote(_ src: String) -> Bool {
        // One source of truth, shared with the card: a URL is remote when its
        // scheme is http(s).
        URL.fromMixedEncodingString(src)?.isRemoteHTTP ?? false
    }

    private static func digest(_ src: String) -> String {
        SHA256.hash(data: Data(src.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// QuickLook keys its previewer off the file extension: `png`, `jpg`, `gif`,
    /// `webp`, falling back to the source's own extension, then a bare `img`.
    private static func fileExtension(of data: Data, or src: String) -> String {
        func starts(with bytes: [UInt8]) -> Bool {
            data.starts(with: bytes)
        }
        if starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if starts(with: [0xFF, 0xD8, 0xFF]) { return "jpg" }
        if starts(with: Array("GIF8".utf8)) { return "gif" }
        if data.count > 12, Array(data[8 ... 11]) == Array("WEBP".utf8) { return "webp" }
        if data.starts(with: [0x49, 0x49, 0x2A]) || data.starts(with: [0x4D, 0x4D, 0x00]) {
            return "tif"
        }
        if let fromSource = URL.fromMixedEncodingString(src)?.pathExtension, !fromSource.isEmpty {
            return fromSource
        }
        return "img"
    }
}

/// Session pool of decoded images: `NSCache` for the pictures (already
/// synchronised; entries vanish under memory pressure, which just falls back
/// to disk) and a locked set for failure marks.
private final class ImageMemoryCache: @unchecked Sendable {
    private let cache = NSCache<NSString, UIImage>()
    private let lock = NSLock()
    private var failures = Set<NSString>()

    init() {
        cache.countLimit = 64
        cache.totalCostLimit = 64 * 1024 * 1024
    }

    func image(for src: String) -> UIImage? {
        cache.object(forKey: src as NSString)
    }

    func store(_ image: UIImage, for src: String) {
        cache.setObject(image, forKey: src as NSString, cost: Self.cost(of: image))
        lock.withLock { failures.remove(src as NSString) }
    }

    func markFailed(_ src: String) {
        lock.withLock { failures.insert(src as NSString) }
    }

    func isFailed(_ src: String) -> Bool {
        lock.withLock { failures.contains(src as NSString) }
    }

    /// A rough decoded-size estimate, so the pool's budget weighs pictures by
    /// what they cost to keep: bytes, not links.
    private static func cost(of image: UIImage) -> Int {
        let size = image.size
        return Int(size.width * size.height * image.scale * image.scale * 4)
    }
}
