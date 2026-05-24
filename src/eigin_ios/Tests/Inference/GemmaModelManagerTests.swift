@testable import Eigin
import Foundation
import Testing

/// Verifies the compilation guard logic in ``GemmaModelManager``.
///
/// We test at the class boundary because the core change is a relaxed
/// guard that now lets compilation proceed from *any* state when the
/// model files are present on disk and not already loaded.
@Suite("GemmaModelManager") @MainActor
struct GemmaModelManagerTests {
    // MARK: - Guard: skip when inappropriate

    @Test func compileSkipsWhenAlreadyCompiling() async {
        let manager = GemmaModelManager()
        manager.state = .compiling(fractionCompleted: 0.5)
        await manager.compile()
        #expect(manager.state == .compiling(fractionCompleted: 0.5))
    }

    @Test func compileSkipsWhenModelNotOnDisk() async {
        let manager = GemmaModelManager()
        manager.state = .failed("previous error")
        await manager.compile()
        #expect(manager.state == .failed("previous error"))
    }

    // MARK: - Guard: proceed when model is present and not loaded

    @Test func compileRetriesAfterFailureWhenModelIsPresent() async throws {
        let manager = GemmaModelManager()
        try makeFakeModelDirectory()
        defer { cleanupFakeModelDirectory() }

        manager.state = .failed("out of memory")

        await manager.compile()

        // If compilation was attempted the state will have changed from the
        // original failure (briefly to .compiling, then to a GemmaRuntime load
        // error because the fake directory has no model_config.json).
        #expect(
            manager.state != .failed("out of memory"),
            "Expected compile() to attempt loading, which changes state away from the original failure"
        )
    }

    // MARK: - tryAutoCompile

    @Test func tryAutoCompileSkipsWhenAppIsNotActive() {
        let manager = GemmaModelManager()
        manager.state = .failed("old error")
        manager.tryAutoCompile(isActive: false)
        #expect(manager.state == .failed("old error"))
    }

    @Test func tryAutoCompileSkipsWhenAlreadyCompiling() {
        let manager = GemmaModelManager()
        manager.state = .compiling(fractionCompleted: 0.5)
        manager.tryAutoCompile(isActive: true)
        #expect(manager.state == .compiling(fractionCompleted: 0.5))
    }

    private func makeFakeModelDirectory() throws -> URL {
        let documents = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first!
        let gemmaDir = documents
            .appendingPathComponent("Models")
            .appendingPathComponent("gemma4-e2b")
        let weightPath = gemmaDir
            .appendingPathComponent("chunk1.mlmodelc")
            .appendingPathComponent("weights")
            .appendingPathComponent("weight.bin")
        try? FileManager.default.createDirectory(
            at: weightPath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(
            atPath: weightPath.path,
            contents: Data(),
            attributes: nil
        )
        return weightPath
    }

    private func cleanupFakeModelDirectory() {
        let documents = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first!
        let gemmaDir = documents
            .appendingPathComponent("Models")
            .appendingPathComponent("gemma4-e2b")
        try? FileManager.default.removeItem(at: gemmaDir)
    }
}
