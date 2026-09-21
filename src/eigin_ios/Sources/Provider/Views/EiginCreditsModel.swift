import Factory
import SwiftUI

/// Drives the Eigin credits screen: the summed balance and the purchasable catalog.
///
/// The relay client, ``CreditsService``, and ``CreditWalletManager`` do no caching or request
/// deduplication, so this model owns it. The catalog loads once per screen lifetime and the balance
/// refreshes only on entry, on deliberate pull-to-refresh, and once after a purchase.
@Observable @MainActor
final class EiginCreditsModel {
    private var creditsService: any CreditsService {
        Container.shared.creditsService()
    }

    private var walletManager: any CreditWalletManager {
        Container.shared.creditWalletManager()
    }

    /// Summed balance across wallets. Local-first: seeded immediately from the locally persisted
    /// wallets on init, then reconciled against the relay on refresh.
    private(set) var totalCredits = 0
    private(set) var products: [PurchasableCredit] = []
    private(set) var hasLoadedProducts = false
    private(set) var isRefreshing = false
    private(set) var purchasingID: String?
    private(set) var isRestoring = false
    var error: String?

    var isPurchasing: Bool {
        purchasingID != nil
    }

    init() {
        // Show the last-known balance instantly; the network refresh on entry corrects it.
        totalCredits = cachedBalance()
    }

    /// Called once when the screen appears: refresh the balance and load the catalog.
    func onAppear() async {
        await refresh()
        await loadProductsIfNeeded()
    }

    /// Reconcile every wallet against the relay and sum the result. Guarded so rapid re-entry or a
    /// pull-to-refresh mid-flight can't stack requests.
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await walletManager.refreshBalances()
        totalCredits = cachedBalance()
    }

    /// Sum of the locally persisted wallet balances — the last value reconciled from the relay.
    private func cachedBalance() -> Int {
        walletManager.wallets().reduce(0) { $0 + $1.credits }
    }

    /// Load the purchasable catalog the first time only — it changes rarely.
    func loadProductsIfNeeded() async {
        guard !hasLoadedProducts else { return }
        await loadProducts()
    }

    private func loadProducts() async {
        error = nil
        do {
            products = try await creditsService.availableProducts()
            hasLoadedProducts = true
        } catch {
            self.error = Self.userMessage(
                for: error,
                fallback: Localized.Provider.Eigin.purchaseRetry
            )
        }
    }

    /// Restore past purchases and refresh the balance. Returns `true` when at least one wallet came
    /// back, so the caller can dismiss — mirrors `purchase(_:)`. An empty result (no purchases in
    /// the account's history) is surfaced as an error-style note, not a silent no-op.
    func restorePurchases() async -> Bool {
        guard !isRestoring, !isPurchasing else { return false }
        isRestoring = true
        error = nil
        defer { isRestoring = false }
        do {
            let wallets = try await creditsService.restorePurchases()
            await refresh()
            guard !wallets.isEmpty else {
                error = Localized.Provider.Eigin.nothingToRestore
                return false
            }
            return true
        } catch {
            // No purchase is in flight on this path, so the pending-recovery copy would
            // claim something untrue; a neutral retry line is the honest fallback.
            self.error = Self.userMessage(
                for: error,
                fallback: Localized.Provider.Eigin.purchaseRetry
            )
            return false
        }
    }

    /// Buy a product and refresh the balance. Returns `true` on success so the caller can dismiss.
    /// Guarded so only one operation runs at a time — a purchase and a restore must not interleave.
    func purchase(_ productID: String) async -> Bool {
        guard purchasingID == nil, !isRestoring else { return false }
        purchasingID = productID
        error = nil
        defer { purchasingID = nil }
        do {
            _ = try await creditsService.purchaseCredits(productID: productID)
            await refresh()
            return true
        } catch CreditsError.purchaseCancelled, CreditsError.purchasePending {
            // Expected user outcomes, not failures worth surfacing.
            return false
        } catch {
            self.error = Self.userMessage(for: error)
            return false
        }
    }

    /// Plain, calm copy per failure class. A config problem must not read like the user's
    /// connection failure, and an interrupted purchase must not read as lost money:
    /// unfinished transactions are redeemed automatically at the next launch. Call sites
    /// without a purchase in flight pick their own neutral fallback.
    private static func userMessage(
        for error: Error,
        fallback: String = Localized.Provider.Eigin.purchasePendingRecovery
    ) -> String {
        switch error {
        case CreditsError.productNotFound:
            Localized.Provider.Eigin.purchaseUnavailable
        case CreditsError.purchaseVerificationFailed, RelayClientError.proofVerificationFailed:
            Localized.Provider.Eigin.purchaseVerification
        case RelayClientError.serviceUnavailable:
            Localized.Provider.Eigin.purchaseOutage
        case RelayClientError.network:
            Localized.Provider.Eigin.purchaseNetwork
        default:
            fallback
        }
    }
}
