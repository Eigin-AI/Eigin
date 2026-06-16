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
}

struct DefaultCreditsService: CreditsService {
    private let relayClient: any RelayClient
    private let purchaseService: any StoreKitPurchaseService
    private let walletManager: any CreditWalletManager

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
        let response = try await relayClient.redeem(type: "apple_iap", proof: proof)
        let wallet = CreditWallet(
            token: response.token,
            credits: response.credits,
            status: response.status,
            productID: productID,
            updatedAt: Date()
        )
        walletManager.add(wallet)
        return wallet
    }
}
