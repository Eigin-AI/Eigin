import Foundation

/// A credit product the user can buy: the relay's credit grant joined with the store's live display
/// name and price. Produced by merging the relay catalog with StoreKit.
struct PurchasableCredit: Identifiable, Sendable {
    let id: String
    let credits: Int
    let displayName: String
    let displayPrice: String
}

/// Coordinates acquiring credits: purchase via StoreKit, redeem with the relay, and persist the
/// resulting wallet. Spending and selection live in ``CreditWalletManager``.
protocol CreditsService: Sendable {
    /// Purchasable products: relay catalog merged with StoreKit price/name,
    /// filtered to what the store vends.
    func availableProducts() async throws -> [PurchasableCredit]
    /// Purchase the given product, redeem it, store the wallet, and return it.
    func purchaseCredits(productID: String) async throws -> CreditWallet
    /// Redeem every outstanding StoreKit transaction: scan the queue of unfinished transactions
    /// once, then keep redeeming whatever StoreKit delivers, for the process lifetime.
    func startOutstandingRedemption() async
}

struct DefaultCreditsService: CreditsService {
    private let relayClient: any RelayClient
    private let purchaseService: any StoreKitPurchaseService
    private let walletManager: any CreditWalletManager

    /// Guards the launch redemption: one listener for the process lifetime, and no two paths
    /// redeeming the same outstanding proof concurrently (the launch scan and the StoreKit
    /// updates listener can both observe the same unfinished transaction).
    private let redemptionState = RedemptionState()

    init(
        relayClient: any RelayClient,
        purchaseService: any StoreKitPurchaseService,
        walletManager: any CreditWalletManager
    ) {
        self.relayClient = relayClient
        self.purchaseService = purchaseService
        self.walletManager = walletManager
    }

    func availableProducts() async throws -> [PurchasableCredit] {
        let catalog = try await relayClient.products()
        let store = try await purchaseService.availableProducts(ids: catalog.map(\.id))
        let creditsByID = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0.credits) })
        return store.compactMap { product in
            creditsByID[product.id].map { credits in
                PurchasableCredit(
                    id: product.id,
                    credits: credits,
                    displayName: product.displayName,
                    displayPrice: product.displayPrice
                )
            }
        }
        .sorted { $0.credits < $1.credits }
    }

    func purchaseCredits(productID: String) async throws -> CreditWallet {
        let proof = try await purchaseService.purchase(productID: productID)
        return try await redeemAndFinish(proof: proof, productID: productID)
    }

    func startOutstandingRedemption() async {
        // Keep draining StoreKit deliveries for the process lifetime, without holding up the
        // caller — launch code and tests await only the one-shot unfinished scan.
        if redemptionState.startListener() {
            Task { await consumeDeliveredProofs() }
        }
        for proof in await purchaseService.unfinishedProofs() {
            // Per-proof recovery: one failure (e.g. offline) must not block the rest.
            guard redemptionState.claim(proof) else { continue }
            do {
                _ = try await redeemAndFinish(proof: proof)
                redemptionState.release(proof)
            } catch {
                // Releasable again: StoreKit may re-deliver within this session.
                redemptionState.release(proof)
                continue
            }
        }
    }

    /// Redeem, persist the wallet, and only then finish the transaction. On failure the proof is
    /// left unfinished, so StoreKit re-delivers it later. On this path the recovered wallet's
    /// `productID` stays unknown — the relay remains the source of truth for the balance.
    private func redeemAndFinish(
        proof: String,
        productID: String? = nil
    ) async throws -> CreditWallet {
        do {
            let response = try await relayClient.redeem(type: "apple_iap", proof: proof)
            let wallet = CreditWallet(
                token: response.token,
                credits: response.credits,
                status: response.status,
                productID: productID,
                updatedAt: Date()
            )
            walletManager.add(wallet)
            await purchaseService.finish(proof: proof)
            return wallet
        } catch {
            // The transaction stays unfinished: StoreKit re-delivers it later and the next
            // launch sweep re-scans. Safe to retry — redeem is idempotent per transaction.
            AppLogger.warning(
                "Redeem failed for StoreKit transaction; will retry at next launch: \(public: String(describing: error))",
                category: .general
            )
            throw error
        }
    }

    private func consumeDeliveredProofs() async {
        for await proof in purchaseService.deliveredProofs() {
            guard redemptionState.claim(proof) else { continue }
            _ = try? await redeemAndFinish(proof: proof)
            redemptionState.release(proof)
        }
    }
}

/// Concurrency and double-start guard for launch redemption. Shared by every copy of
/// ``DefaultCreditsService`` (it is a struct).
private final class RedemptionState: @unchecked Sendable {
    private let lock = NSLock()
    private var isListening = false
    private var inFlight: Set<String> = []

    /// Returns `true` only for the first caller; later starts must not spawn another
    /// process-lifetime listener.
    func startListener() -> Bool {
        lock.withLock {
            if isListening {
                return false
            }
            isListening = true
            return true
        }
    }

    /// Claims `proof` while it is being redeemed; `false` means something else already is.
    func claim(_ proof: String) -> Bool {
        lock.withLock {
            !inFlight.contains(proof) && inFlight.insert(proof).inserted
        }
    }

    /// Lets the proof be claimed again — for redeliveries after a failed redeem.
    func release(_ proof: String) {
        lock.withLock {
            inFlight.remove(proof)
        }
    }
}
