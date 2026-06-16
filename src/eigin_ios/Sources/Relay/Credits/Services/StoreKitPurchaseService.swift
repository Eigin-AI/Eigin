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
protocol StoreKitPurchaseService: Sendable {
    /// Resolve product IDs against StoreKit for live display name and price. IDs the store does not
    /// vend are silently dropped.
    func availableProducts(ids: [String]) async throws -> [StoreProduct]
    /// Purchase the given product and return its `Transaction.jwsRepresentation`.
    func purchase(productID: String) async throws -> String
}

struct DefaultStoreKitPurchaseService: StoreKitPurchaseService {
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
            // Consumable: finish immediately so StoreKit doesn't redeliver it.
            await transaction.finish()
            return verification.jwsRepresentation
        case .userCancelled:
            throw CreditsError.purchaseCancelled
        case .pending:
            throw CreditsError.purchasePending
        @unknown default:
            throw CreditsError.purchaseVerificationFailed
        }
    }
}
