import Foundation

/// Abstracts free-space queries so views and services stay testable.
protocol DiskSpaceService: Sendable {
    /// The available free space on the device’s primary file system, in bytes.
    func availableBytes() -> Int64?
}

/// Production implementation that queries the file system directly.
struct DefaultDiskSpaceService: DiskSpaceService {
    func availableBytes() -> Int64? {
        (try? FileManager.default.attributesOfFileSystem(
            forPath: NSHomeDirectory()
        )[.systemFreeSize]) as? Int64
    }
}
