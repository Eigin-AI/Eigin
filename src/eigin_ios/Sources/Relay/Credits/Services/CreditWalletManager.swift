import Foundation

/// Manages the device's credit wallets: which one to spend, recording exhaustion,
/// eviction of dead wallets, and refreshing balances from the relay.
///
/// Balance handling is lazy: the redeem response seeds the balance, `markExhausted` corrects it
/// on a 402, and `refreshBalances` reconciles on demand.
protocol CreditWalletManager: Sendable {
    /// All wallets currently held on device.
    func wallets() -> [CreditWallet]
    /// Add or update a wallet (dedupe by token).
    func add(_ wallet: CreditWallet)
    /// The first wallet with spendable balance, if any.
    func spendableWallet() -> CreditWallet?
    /// Drop refunded, closed, and zero-balance wallets.
    func evictEmpty()
    /// Reconcile every wallet's balance against the relay, dropping unknown tokens.
    func refreshBalances() async
    /// Records a rejected wallet and evicts it from the spendable collection.
    func markExhausted(token: String)
}

/// Default `CreditWalletManager` backed by a `CreditWalletStore` and the relay.
struct DefaultCreditWalletManager: CreditWalletManager {
    private let relayClient: any RelayClient
    private let store: CreditWalletStore

    init(relayClient: any RelayClient, keychain: any KeychainService) {
        self.relayClient = relayClient
        store = CreditWalletStore(keychain: keychain)
    }

    func wallets() -> [CreditWallet] {
        store.all()
    }

    func add(_ wallet: CreditWallet) {
        store.upsert(wallet)
    }

    func spendableWallet() -> CreditWallet? {
        store.all().first { $0.isSpendable }
    }

    func evictEmpty() {
        store.replaceAll(store.all().filter(\.isSpendable))
    }

    func refreshBalances() async {
        var updated: [CreditWallet] = []
        for var wallet in store.all() {
            do {
                let balance = try await relayClient.balance(token: wallet.token)
                wallet.credits = balance.credits
                wallet.status = balance.status
                wallet.updatedAt = Date()
                updated.append(wallet)
            } catch let error as RelayClientError {
                // An unknown/expired token is dropped; transient failures keep the snapshot.
                if case .authentication = error { continue }
                updated.append(wallet)
            } catch {
                updated.append(wallet)
            }
        }
        store.replaceAll(updated)
        evictEmpty()
    }

    func markExhausted(token: String) {
        guard var wallet = store.all().first(where: { $0.token == token }) else { return }
        wallet.credits = 0
        wallet.updatedAt = Date()
        store.upsert(wallet)
        evictEmpty()
    }
}
