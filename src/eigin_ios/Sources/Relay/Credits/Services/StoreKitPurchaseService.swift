import StoreKit

/// A store product resolved from StoreKit: the live display fields for a product ID. Sendable so it
/// can cross the StoreKit boundary into the credits domain without leaking `Product`.
struct StoreProduct: Sendable {
    let id: String
    let displayName: String
    let displayPrice: String
}

/// Drives a StoreKit 2 consumable purchase and returns the verified transaction's JWS, which the
/// relay verifies on redeem. A thin boundary over StoreKit — not unit-tested.
///
/// Transactions are deliberately left unfinished: ``finish(proof:)`` is called only after the
/// redeem has succeeded, so an interrupted purchase is re-delivered by StoreKit and recovered at
/// launch (unfinished-transaction scan and the ``deliveredProofs()`` stream).
protocol StoreKitPurchaseService: Sendable {
    /// Resolve product IDs against StoreKit for live display name and price. IDs the store does not
    /// vend are silently dropped.
    func availableProducts(ids: [String]) async throws -> [StoreProduct]
    /// Purchase the given product and return its `Transaction.jwsRepresentation`. The transaction
    /// stays unfinished until ``finish(proof:)`` succeeds for the returned proof.
    func purchase(productID: String) async throws -> String
    /// Verified proofs for everything currently unfinished in the StoreKit queue, in
    /// `Transaction.unfinished` order. Unverified transactions are finished immediately so they
    /// don't block the queue.
    func unfinishedProofs() async -> [String]
    /// Verified proofs StoreKit delivers for as long as the stream is alive (Ask-to-Buy approvals,
    /// transactions set up before an earlier redemption completed). Unverified transactions are
    /// finished immediately.
    func deliveredProofs() -> AsyncStream<String>
    /// Verified proofs for every consumable, non-revoked transaction in the App Store account's
    /// history for this app — including already finished ones. Used to re-redeem past purchases
    /// after a reinstall. These transactions are already finished; there is nothing to finish
    /// afterwards.
    func historicalProofs() async -> [String]
    /// Finish the transaction backing this proof. No-op for an unknown proof.
    func finish(proof: String) async
}

struct DefaultStoreKitPurchaseService: StoreKitPurchaseService {
    /// Finishes the transaction behind an unverified result. The payload is still a `Transaction`,
    /// and leaving it unfinished would make StoreKit re-deliver it forever.
    private static func discardUnverified(
        _ payload: Transaction,
        error: VerificationResult<Transaction>.VerificationError
    ) async {
        await payload.finish()
        AppLogger.warning(
            "Finished unverified StoreKit transaction \(public: payload.id): \(public: String(describing: error))",
            category: .general
        )
    }

    /// Keeps unfinished transactions alive per proof until they are finished.
    private final class ProofTransactions: @unchecked Sendable {
        private let lock = NSLock()
        private var transactions: [String: Transaction] = [:]

        func remember(_ transaction: Transaction, proof: String) {
            lock.lock()
            transactions[proof] = transaction
            lock.unlock()
        }

        func take(proof: String) -> Transaction? {
            lock.lock()
            defer { lock.unlock() }
            return transactions.removeValue(forKey: proof)
        }
    }

    private let proofTransactions = ProofTransactions()

    func availableProducts(ids: [String]) async throws -> [StoreProduct] {
        try await Product.products(for: ids).map {
            StoreProduct(id: $0.id, displayName: $0.displayName, displayPrice: $0.displayPrice)
        }
    }

    func purchase(productID: String) async throws -> String {
        let products = try await Product.products(for: [productID])
        guard let product = products.first else {
            throw CreditsError.productNotFound
        }

        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            guard case .verified(let transaction) = verification else {
                throw CreditsError.purchaseVerificationFailed
            }
            // Left unfinished on purpose: finish only after the redeem succeeds, so an
            // interrupted purchase is re-delivered by StoreKit and redeemed at launch.
            proofTransactions.remember(transaction, proof: verification.jwsRepresentation)
            return verification.jwsRepresentation
        case .userCancelled:
            throw CreditsError.purchaseCancelled
        case .pending:
            throw CreditsError.purchasePending
        @unknown default:
            throw CreditsError.purchaseVerificationFailed
        }
    }

    func unfinishedProofs() async -> [String] {
        var proofs: [String] = []
        for await result in Transaction.unfinished {
            if case .unverified(let transaction, let error) = result {
                await Self.discardUnverified(transaction, error: error)
                continue
            }
            guard case .verified(let transaction) = result else { continue }
            proofTransactions.remember(transaction, proof: result.jwsRepresentation)
            proofs.append(result.jwsRepresentation)
        }
        return proofs
    }

    func deliveredProofs() -> AsyncStream<String> {
        AsyncStream { continuation in
            let task = Task {
                for await result in Transaction.updates {
                    if case .unverified(let transaction, let error) = result {
                        await Self.discardUnverified(transaction, error: error)
                        continue
                    }
                    guard case .verified(let transaction) = result else { continue }
                    proofTransactions.remember(transaction, proof: result.jwsRepresentation)
                    continuation.yield(result.jwsRepresentation)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func historicalProofs() async -> [String] {
        var proofs: [String] = []
        for await result in Transaction.all {
            guard case .verified(let transaction) = result else { continue }
            // Only consumable credit packs; skips anything revoked (e.g. refunded).
            guard transaction.productType == .consumable, transaction.revocationDate == nil else {
                continue
            }
            proofs.append(result.jwsRepresentation)
        }
        return proofs
    }

    func finish(proof: String) async {
        guard let transaction = proofTransactions.take(proof: proof) else { return }
        await transaction.finish()
    }
}
