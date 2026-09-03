@testable import Eigin
import Foundation
import Testing

@Suite("CreditsService")
struct CreditsServiceTests {
    /// Build the service plus the wallet manager underneath it, so tests can inspect persisted
    /// wallets through the Keychain-backed store via ``DefaultCreditWalletManager.wallets()``.
    private func makeService(
        relay: FakeRelayClient,
        store: FakeStoreKitPurchaseService
    ) -> (service: DefaultCreditsService, walletManager: DefaultCreditWalletManager) {
        let manager = DefaultCreditWalletManager(
            relayClient: relay,
            keychain: FakeKeychainService()
        )
        let service = DefaultCreditsService(
            relayClient: relay,
            purchaseService: store,
            walletManager: manager
        )
        return (service, manager)
    }

    /// Sendable proof log the redeem handler appends to.
    private final class ProofLog: @unchecked Sendable {
        private let lock = NSLock()
        private var proofs: [String] = []

        func append(_ proof: String) {
            lock.lock()
            proofs.append(proof)
            lock.unlock()
        }

        var all: [String] {
            lock.lock()
            defer { lock.unlock() }
            return proofs
        }
    }

    /// Redeem handler minting a distinct token per proof and recording the proof order it was
    /// called with. Proofs in `failed` throw instead.
    private func mintingRedeemer(
        relay: FakeRelayClient,
        redeemed: ProofLog,
        failed: Set<String> = []
    ) {
        relay.redeemHandler = { _, proof in
            guard !failed.contains(proof) else {
                throw RelayClientError.network("")
            }
            redeemed.append(proof)
            return RedeemResponse(token: "eict_\(proof)", credits: 500, status: .active)
        }
    }

    /// Wait until `condition` holds or the deadline passes. The delivered-proof stream is
    /// asynchronous, so results need a bounded wait rather than an immediate assert.
    private func waitUntil(
        _ condition: @autoclosure () async throws -> Bool,
        timeout: TimeInterval = 5
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if try await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(try await condition())
    }

    // MARK: - Catalog (existing behavior)

    @Test func availableProductsMergesRelayCreditsWithStorePrice() async throws {
        let relay = FakeRelayClient()
        relay.productsHandler = {
            [CreditProduct(id: "eigin.credits.v1.apple.500", credits: 500)]
        }
        let store = FakeStoreKitPurchaseService()
        store.vended = [
            "eigin.credits.v1.apple.500": StoreProduct(
                id: "eigin.credits.v1.apple.500",
                displayName: "500 Credits",
                displayPrice: "$4.99"
            ),
        ]

        let (service, _) = makeService(relay: relay, store: store)
        let products = try await service.availableProducts()

        #expect(products.count == 1)
        let product = try #require(products.first)
        #expect(product.id == "eigin.credits.v1.apple.500")
        #expect(product.credits == 500) // from the relay
        #expect(product.displayName == "500 Credits") // from the store
        #expect(product.displayPrice == "$4.99") // from the store
    }

    @Test func availableProductsDropsCatalogIDsTheStoreDoesNotVend() async throws {
        let relay = FakeRelayClient()
        relay.productsHandler = {
            [
                CreditProduct(id: "eigin.credits.v1.apple.500", credits: 500),
                CreditProduct(id: "eigin.credits.v1.apple.dev.500", credits: 500),
            ]
        }
        // The store only vends the dev product (mirrors the dev app's App Store Connect listing).
        let store = FakeStoreKitPurchaseService()
        store.vended = [
            "eigin.credits.v1.apple.dev.500": StoreProduct(
                id: "eigin.credits.v1.apple.dev.500",
                displayName: "500 Credits (Dev)",
                displayPrice: "$4.99"
            ),
        ]

        let (service, _) = makeService(relay: relay, store: store)
        let products = try await service.availableProducts()

        #expect(products.map(\.id) == ["eigin.credits.v1.apple.dev.500"])
    }

    @Test func availableProductsSortsByCreditsAscending() async throws {
        let relay = FakeRelayClient()
        relay.productsHandler = {
            [
                CreditProduct(id: "big", credits: 500),
                CreditProduct(id: "small", credits: 100),
            ]
        }
        let store = FakeStoreKitPurchaseService()
        store.vended = [
            "big": StoreProduct(id: "big", displayName: "Big", displayPrice: "$4.99"),
            "small": StoreProduct(id: "small", displayName: "Small", displayPrice: "$0.99"),
        ]

        let (service, _) = makeService(relay: relay, store: store)
        let products = try await service.availableProducts()

        #expect(products.map(\.credits) == [100, 500])
    }

    // MARK: - Outstanding redemption (#215)

    @Test func purchaseCreditsRedeemsBeforeFinishing() async throws {
        let relay = FakeRelayClient()
        let store = FakeStoreKitPurchaseService()
        store.purchaseProofs = ["proof-1"]
        let (service, manager) = makeService(relay: relay, store: store)

        // The transaction may only be finished once the redeem has succeeded — the redeem and
        // the finish both append to the same log, so their relative order is observable.
        let events = ProofLog()
        relay.redeemHandler = { _, proof in
            events.append("redeem:\(proof)")
            return RedeemResponse(token: "eict_\(proof)", credits: 500, status: .active)
        }
        store.onFinished = { events.append("finish:\($0)") }

        let wallet = try await service.purchaseCredits(productID: "eigin.credits.v1.apple.500")

        #expect(events.all == ["redeem:proof-1", "finish:proof-1"])
        // ...and the wallet is persisted with the redeem response.
        #expect(wallet.token == "eict_proof-1")
        #expect(manager.wallets() == [wallet])
    }

    @Test func purchaseCreditsWithFailedRedeemLeavesTransactionUnfinished() async throws {
        let relay = FakeRelayClient()
        let store = FakeStoreKitPurchaseService()
        store.purchaseProofs = ["proof-1"]
        relay.redeemHandler = { _, _ in throw RelayClientError.network("") }
        let (service, manager) = makeService(relay: relay, store: store)

        do {
            _ = try await service.purchaseCredits(productID: "any")
            Issue.record("redeem should have failed")
        } catch {}

        // Unfinished on purpose: StoreKit re-delivers this transaction and the next launch
        // sweep recovers the purchase.
        #expect(store.finished.isEmpty)
        #expect(manager.wallets().isEmpty)
    }

    @Test func launchSweepRedeemsAllUnfinishedAndFinishes() async {
        let relay = FakeRelayClient()
        let redeemed = ProofLog()
        mintingRedeemer(relay: relay, redeemed: redeemed)
        let store = FakeStoreKitPurchaseService()
        store.unfinished = ["proof-a", "proof-b"]
        let (service, manager) = makeService(relay: relay, store: store)

        await service.startOutstandingRedemption()

        #expect(redeemed.all == ["proof-a", "proof-b"])
        #expect(store.finished == ["proof-a", "proof-b"])
        #expect(
            manager.wallets().map(\.token) == ["eict_proof-a", "eict_proof-b"],
            "one wallet persisted per redeemed transaction"
        )
    }

    @Test func launchSweepContinuesPastRedeemFailure() async {
        let relay = FakeRelayClient()
        let redeemed = ProofLog()
        mintingRedeemer(relay: relay, redeemed: redeemed, failed: ["proof-a"])
        let store = FakeStoreKitPurchaseService()
        store.unfinished = ["proof-a", "proof-b"]
        let (service, manager) = makeService(relay: relay, store: store)

        await service.startOutstandingRedemption()

        // The failed proof stays unfinished (no finish, no wallet); the sweep still
        // redeems and finishes everything after it.
        #expect(!redeemed.all.contains("proof-a"))
        #expect(redeemed.all == ["proof-b"])
        #expect(store.finished == ["proof-b"])
        #expect(manager.wallets().map(\.token) == ["eict_proof-b"])
    }

    @Test func launchSweepKeepsRedeemingStoreKitDeliveredTransactions() async throws {
        let relay = FakeRelayClient()
        let redeemed = ProofLog()
        mintingRedeemer(relay: relay, redeemed: redeemed)
        let store = FakeStoreKitPurchaseService()
        let (service, manager) = makeService(relay: relay, store: store)

        // Simulates an Ask-to-Buy approval or interrupted purchase arriving once the
        // launch sweep is already listening.
        await service.startOutstandingRedemption()
        store.deliver("delivered-proof")

        try await waitUntil(
            manager.wallets().map(\.token) == ["eict_delivered-proof"]
        )
        try await waitUntil(
            store.finished == ["delivered-proof"]
        )
    }

    @Test func reDeliveredProofRestoresSameWalletWithoutDuplicates() async {
        let relay = FakeRelayClient()
        let redeemed = ProofLog()
        mintingRedeemer(relay: relay, redeemed: redeemed)
        let store = FakeStoreKitPurchaseService()
        store.unfinished = ["proof-a", "proof-a"]
        let (service, manager) = makeService(relay: relay, store: store)

        await service.startOutstandingRedemption()

        // Mirrors relay idempotency: the same proof redeems to the same token both times and
        // the store keeps a single wallet for it.
        let wallets = manager.wallets()
        #expect(wallets.count == 1)
        #expect(wallets.first?.token == "eict_proof-a")
    }
}
