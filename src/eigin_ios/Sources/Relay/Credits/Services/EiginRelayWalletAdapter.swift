import EiginSDK

/// Supplies local wallet credentials while the SDK owns inference failover.
final class EiginRelayWalletAdapter: EiginSDK.Experimental.Inference.EiginRelayWalletSource {
    let manager: any CreditWalletManager

    init(manager: any CreditWalletManager) {
        self.manager = manager
    }

    func nextToken(excluded: [String]) throws -> String? {
        manager.wallets().first { $0.isSpendable && !excluded.contains($0.token) }?.token
    }

    func markExhausted(token: String) throws {
        manager.markExhausted(token: token)
    }
}
