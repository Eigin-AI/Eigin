import Foundation

/// A redeemed credit wallet held on device. A device may hold several — one per purchase —
/// and spends from whichever still has balance. Persisted in the Keychain via
/// ``CreditWalletStore``; the relay remains the source of truth for the live balance.
struct CreditWallet: Codable, Identifiable, Equatable, Sendable {
    /// Opaque bearer token (`eict_…`) returned by redeem. Stable for a given purchase.
    let token: String
    /// Last known whole-credit balance.
    var credits: Int
    var status: WalletStatus
    /// The IAP product this wallet was redeemed from, when known.
    var productID: String?
    /// When the local snapshot was last updated from the relay.
    var updatedAt: Date

    var id: String {
        token
    }

    /// Whether this wallet can currently be spent against.
    var isSpendable: Bool {
        status == .active && credits > 0
    }
}
