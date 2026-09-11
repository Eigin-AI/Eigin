#if DEBUG || EIGIN_DEV
import Foundation

/// Programmable `StoreKitPurchaseService` for tests. `availableProducts` returns whatever the store
/// is configured to vend; `purchase` returns canned proofs.
final class FakeStoreKitPurchaseService: StoreKitPurchaseService, @unchecked Sendable {
    /// Products the fake store vends, keyed by ID. `availableProducts(ids:)` returns the subset of
    /// requested IDs present here, mirroring StoreKit dropping unknown IDs.
    var vended: [String: StoreProduct] = [:]

    /// Proofs `purchase` returns, recycled in order (empty → "fake-jws").
    var purchaseProofs: [String] = []
    /// Errors thrown by `purchase`, keyed by product ID (or "*" for any).
    var purchaseErrors: [String: Error] = [:]
    /// Proofs handed out by the unfinished-transaction scan.
    var unfinished: [String] = []
    /// Proofs handed out by the historical (reinstall recovery) scan.
    var historical: [String] = []
    /// Proofs `finish(proof:)` was called with, in order.
    private(set) var finished: [String] = []

    /// Continuation backing `deliveredProofs`, plus proofs delivered before any consumer started
    /// (buffered and replayed when the stream is first pulled).
    private final class DeliveredPipe: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: AsyncStream<String>.Continuation?
        private var buffered: [String] = []

        func attach(_ continuation: AsyncStream<String>.Continuation) -> [String] {
            lock.lock()
            defer { lock.unlock() }
            self.continuation = continuation
            let replay = buffered
            buffered = []
            return replay
        }

        func send(_ proof: String) {
            let active = lock.withLock { () -> AsyncStream<String>.Continuation? in
                if let queued = self.continuation {
                    return queued
                }
                buffered.append(proof)
                return nil
            }
            active?.yield(proof)
        }
    }

    private let deliveredPipe = DeliveredPipe()

    /// Stream of proofs delivered via ``deliver(_:)``, mirroring StoreKit's
    /// `Transaction.updates`.
    var delivered: AsyncStream<String> {
        AsyncStream { continuation in
            let replay = self.deliveredPipe.attach(continuation)
            replay.forEach { continuation.yield($0) }
        }
    }

    /// Push a proof through the delivered-transactions stream.
    func deliver(_ proof: String) {
        deliveredPipe.send(proof)
    }

    /// Called when `finish(proof:)` runs, so tests can observe the finish itself.
    var onFinished: (@Sendable (String) -> Void)?

    private let lock = NSLock()
    private var purchaseCursor = 0

    func availableProducts(ids: [String]) async throws -> [StoreProduct] {
        ids.compactMap { vended[$0] }
    }

    func purchase(productID: String) async throws -> String {
        if let error = purchaseErrors[productID] ?? purchaseErrors["*"] {
            throw error
        }
        return try lock.withLock {
            guard !purchaseProofs.isEmpty else { return "fake-jws" }
            let proof = purchaseProofs[purchaseCursor % purchaseProofs.count]
            purchaseCursor += 1
            return proof
        }
    }

    func unfinishedProofs() async -> [String] {
        unfinished
    }

    func deliveredProofs() -> AsyncStream<String> {
        delivered
    }

    func historicalProofs() async -> [String] {
        historical
    }

    func finish(proof: String) async {
        lock.withLock {
            finished.append(proof)
        }
        onFinished?(proof)
    }
}
#endif
