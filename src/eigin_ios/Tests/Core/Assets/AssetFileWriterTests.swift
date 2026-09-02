@testable import Eigin
import Foundation
import Testing

/// Out-of-order range writes reassemble the original bytes.
struct AssetFileWriterTests {
    @Test func partsWrittenAtOffsetsReproduceTheFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let original = Data((0 ..< 3_000_000).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        let destination = dir.appendingPathComponent("out.bin")
        try AssetFileWriter.preallocate(destination, size: Int64(original.count))
        #expect(try FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int64
            == Int64(original.count))

        let chunk = 1_000_000
        for offset in [2_000_000, 0, 1_000_000] {
            let part = dir.appendingPathComponent("part-\(offset)")
            try original.subdata(in: offset ..< offset + chunk).write(to: part)
            try AssetFileWriter.write(contentsOf: part, to: destination, at: Int64(offset))
            #expect(!FileManager.default.fileExists(atPath: part.path))
        }

        #expect(try Data(contentsOf: destination) == original)
    }

    @Test func preallocateIsIdempotent() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("a.bin")
        try AssetFileWriter.preallocate(file, size: 64)
        try AssetFileWriter.preallocate(file, size: 64)
        #expect(try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int64 == 64)
    }
}
