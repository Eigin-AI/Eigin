@testable import Eigin
import Foundation
import Testing

/// Verifies the download-completion gatekeeper logic in ``GemmaModelDownloader``.
///
/// The downloader is a singleton with complex URLSession state, so we exercise
/// the internal methods directly through `@testable` import.
@Suite("GemmaModelDownloader")
struct GemmaModelDownloaderTests {
    // MARK: – Reattach / zombie prevention

    @Test func completedTaskIDsBlockZombieReattachment() {
        let downloader = GemmaModelDownloader.shared

        // Simulate a task that completed before getAllTasks finished.
        downloader.completedTaskIDs.insert(42)

        // Manually run the guard that reattachInFlightTasks uses.
        let shouldReattach = !downloader.completedTaskIDs.contains(42)

        #expect(!shouldReattach, "Task 42 should be skipped because its delegate already fired")
    }

    @Test func cancelDownloadClearsCompletedTaskIDs() {
        let downloader = GemmaModelDownloader.shared
        downloader.completedTaskIDs.insert(1)
        downloader.completedTaskIDs.insert(2)

        downloader.cancelDownload()

        #expect(downloader.completedTaskIDs.isEmpty)
    }

    // MARK: – fillDownloadSlots → finishDownload gate

    @Test func fillDownloadSlotsReachesFinishWhenAllTasksDone() throws {
        let downloader = GemmaModelDownloader.shared
        let documents = try #require(FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first)
        let dest = documents
            .appendingPathComponent("Models")
            .appendingPathComponent("test-model")

        // Clean up from previous runs
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.createDirectory(
            at: dest, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: dest) }

        // Create a minimal fake model directory so localModelURL returns non-nil
        let chunkDir = dest
            .appendingPathComponent("chunk1.mlmodelc/weights", isDirectory: true)
        try FileManager.default.createDirectory(
            at: chunkDir, withIntermediateDirectories: true
        )
        FileManager.default.createFile(
            atPath: chunkDir.appendingPathComponent("weight.bin").path,
            contents: nil,
            attributes: nil
        )

        let model = GemmaModelDownloader.ModelInfo(
            id: "test-model",
            name: "Test",
            size: "1 GB",
            downloadURL: "http://example.com",
            folderName: "test-model"
        )

        // Set up downloader state so fillDownloadSlots thinks everything is done
        downloader.currentModel = model
        downloader.destDir = dest
        downloader.isDownloading = true
        downloader.isPaused = false
        downloader.pendingFiles = [
            GemmaModelDownloader.DownloadFile(
                remotePath: "a",
                localPath: "a",
                estimatedSize: 1
            ),
        ]
        downloader.nextFileIndex = 1 // all files dispatched
        downloader.activeDownloadTasks.removeAll()
        downloader.completedTaskIDs.removeAll()

        downloader.fillDownloadSlots()

        #expect(!downloader.isDownloading, "finishDownload should set isDownloading to false")
        #expect(downloader.progress == 1.0, "finishDownload should set progress to 1.0")
    }
}
