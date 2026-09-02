import Foundation

/// Assembles a large file from byte-range parts written at their offsets.
enum AssetFileWriter {
    /// Ensure `url` exists with exactly `size` bytes. On APFS this is a sparse
    /// file, so it costs no disk until ranges land.
    static func preallocate(_ url: URL, size: Int64) throws {
        let fm = FileManager.default
        try fm.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.truncate(atOffset: UInt64(size))
    }

    /// Copy `source` into `destination` starting at `offset`, then delete `source`.
    static func write(contentsOf source: URL, to destination: URL, at offset: Int64) throws {
        let reader = try FileHandle(forReadingFrom: source)
        defer { try? reader.close() }
        let writer = try FileHandle(forWritingTo: destination)
        defer { try? writer.close() }

        try writer.seek(toOffset: UInt64(offset))
        let bufferSize = 1 << 20
        while let chunk = try reader.read(upToCount: bufferSize), !chunk.isEmpty {
            try writer.write(contentsOf: chunk)
        }
        try? FileManager.default.removeItem(at: source)
    }
}
