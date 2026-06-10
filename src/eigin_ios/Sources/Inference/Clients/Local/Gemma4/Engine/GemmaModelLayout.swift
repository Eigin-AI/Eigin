@preconcurrency import CoreML
import Foundation

/// Enumerates every `.mlmodelc` / `.mlpackage` bundle that CoreML must
/// specialise for a Gemma 4 E2B model directory.
///
/// Having this in one place means `ChunkedEngine.load` and
/// `GemmaRuntime.prewarm` never disagree about which files need warming.
///
/// Each element is a `(url: URL, configuration: MLModelConfiguration)`
/// pair ready to pass directly to `MLModel(contentsOf:configuration:)`.
enum GemmaModelLayout {
    struct Entry {
        let name: String
        let url: URL
        let configuration: MLModelConfiguration
    }

    /// Returns all model entries that need ANE specialisation in `directory`.
    ///
    /// Order matches `ChunkedEngine.load`: decode chunks first, then prefill
    /// chunks (if present), then verify functions (if present), then the MTP
    /// drafter (if present).
    ///
    /// - Parameters:
    ///   - directory: The root model directory (contains `chunk1.mlmodelc` etc.)
    ///   - computeUnits: Applied to all entries (default `.cpuAndNeuralEngine`).
    static func entries(
        in directory: URL,
        computeUnits: MLComputeUnits = .cpuAndNeuralEngine
    ) -> [Entry] {
        let fm = FileManager.default

        func find(_ name: String) -> URL? {
            let compiled = directory.appendingPathComponent("\(name).mlmodelc")
            if fm.fileExists(atPath: compiled.path) { return compiled }
            let pkg = directory.appendingPathComponent("\(name).mlpackage")
            if fm.fileExists(atPath: pkg.path) { return pkg }
            return nil
        }

        var result: [Entry] = []

        // Decode chunks — always required.
        let decodeConfig = MLModelConfiguration()
        decodeConfig.computeUnits = computeUnits

        for name in ["chunk1", "chunk2", "chunk3", "chunk4"] {
            if let url = find(name) {
                result.append(Entry(name: name, url: url, configuration: decodeConfig))
            }
        }

        // Prefill chunks — optional.
        for name in ["prefill_chunk1", "prefill_chunk2", "prefill_chunk3", "prefill_chunk4"] {
            if let url = find(name) {
                result.append(Entry(name: name, url: url, configuration: decodeConfig))
            }
        }

        // Verify functions — only supported by multi-function ML programs
        // (.mlpackage). Compiled .mlmodelc bundles reject a non-nil
        // functionName with a runtime error, so only add these entries when
        // the file on disk is actually a .mlpackage.
        let verifyConfig = MLModelConfiguration()
        verifyConfig.computeUnits = computeUnits
        verifyConfig.functionName = "verify_qK"

        for name in ["chunk1", "chunk2", "chunk3", "chunk4"] {
            let pkg = directory.appendingPathComponent("\(name).mlpackage")
            if fm.fileExists(atPath: pkg.path) {
                result.append(
                    Entry(name: "\(name) [verify]", url: pkg, configuration: verifyConfig)
                )
            }
        }

        // MTP drafter — optional.
        if let url = find("mtp_drafter") {
            result.append(Entry(name: "mtp_drafter", url: url, configuration: decodeConfig))
        }

        return result
    }
}
