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
            self.error = error.localizedDescription
        }
    }

    /// Buy a product and refresh the balance. Returns `true` on success so the caller can dismiss.
    /// Guarded so only one purchase runs at a time.
    func purchase(_ productID: String) async -> Bool {
        guard purchasingID == nil else { return false }
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
            self.error = error.localizedDescription
            return false
        }
    }
}
