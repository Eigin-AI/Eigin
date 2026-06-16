import Foundation

/// Keychain-backed persistence for the credit-wallet collection.
///
/// The whole collection is stored as a single JSON blob under
/// `KeychainService.creditWalletsKey` (the keychain holds only strings). This is an internal
/// helper of ``DefaultCreditWalletManager``, not a DI-registered service — it is constructed
/// from the injected `KeychainService` and unit-tested directly with a fake keychain.
struct CreditWalletStore: Sendable {
    private let keychain: any KeychainService

    init(keychain: any KeychainService) {
        self.keychain = keychain
    }

    /// All stored wallets, in insertion order. Empty if none or if the blob is unreadable.
    func all() -> [CreditWallet] {
        guard let json = keychain.read(key: keychain.creditWalletsKey),
              let data = json.data(using: .utf8),
              let wallets = try? JSONDecoder().decode([CreditWallet].self, from: data)
        else {
            return []
        }
        return wallets
    }

    /// Overwrite the entire collection.
    func replaceAll(_ wallets: [CreditWallet]) {
        guard let data = try? JSONEncoder().encode(wallets),
              let json = String(data: data, encoding: .utf8)
        else {
            return
        }
        keychain.save(key: keychain.creditWalletsKey, value: json)
    }

    /// Insert a wallet, or update the existing one with the same token (dedupe by token).
    func upsert(_ wallet: CreditWallet) {
        var wallets = all()
        if let index = wallets.firstIndex(where: { $0.token == wallet.token }) {
            wallets[index] = wallet
        } else {
            wallets.append(wallet)
        }
        replaceAll(wallets)
    }

    /// Remove the wallet with the given token, if present.
    func remove(token: String) {
        replaceAll(all().filter { $0.token != token })
    }
}
