import CoreML
import Foundation

enum SpeculativeError: Error {
    case predictionFailed
    case assetMissing(String)
    case verifyFailed(String)
}

public protocol SpeculativeTarget {
    func lastHiddenMulti(at layerIndices: [Int]) throws -> [MLMultiArray]
    func verifyCandidates(_ candidates: [Int32], K: Int) throws -> [Int32]
    func commitAccepted(_ tokens: [Int32]) throws
}

enum SpecProfile {
    static func time<T>(_ block: () throws -> T) rethrows -> (T, Double) {
        let start = CFAbsoluteTimeGetCurrent()
        let result = try block()
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        return (result, elapsed * 1000)
    }

    static func logBurst(
        engine: String, cycle: Int,
        draftMs: Double, verifyMs: Double, commitMs: Double,
        accepted: Int, compareLen: Int,
        emitted: Int, rolling: Double
    ) {}
    static func logBootstrap(
        engine: String, replayCount: Int,
        replayMs: Double, targetStepMs: Double
    ) {}
}
