import Foundation

/// Spendability of a credit wallet, mirroring the relay's `WalletStatus`.
enum WalletStatus: String, Codable, Sendable {
    /// Credits are spendable.
    case active
    /// Credits were zeroed by a store refund.
    case refunded
    /// Wallet was administratively closed.
    case closed
}

/// Request body for `POST /v1/credits/redeem`.
struct RedeemRequest: Encodable {
    /// Entitlement source discriminator, e.g. `apple_iap`.
    let type: String
    /// Credential from the entitlement source. For `apple_iap` this is a StoreKit 2
    /// `Transaction.jwsRepresentation`.
    let proof: String
}

/// Response from `POST /v1/credits/redeem`.
struct RedeemResponse: Decodable {
    /// Opaque bearer token (`eict_…`) for inference and balance checks.
    let token: String
    /// Whole credits remaining in the wallet.
    let credits: Int
    let status: WalletStatus
}

/// Response from `GET /v1/credits/balance`.
struct BalanceResponse: Decodable {
    let credits: Int
    let status: WalletStatus
}

/// Response from `GET /v1/credits/products`.
struct ProductsListResponse: Decodable {
    let products: [CreditProduct]
}

/// A purchasable credit product as the relay knows it: a store product ID and the credits it
/// grants. Price and display name come from the store, not the relay.
struct CreditProduct: Decodable, Sendable {
    let id: String
    let credits: Int
}

/// Response from `GET /v1/models` (OpenAI-compatible).
struct ModelsListResponse: Decodable {
    let data: [ModelObject]

    struct ModelObject: Decodable {
        let id: String
    }
}

/// Manifest for a mirrored model asset, from `GET /v1/assets/{id}`: the
/// pinned version's file list with checksums and short-lived presigned URLs.
struct AssetManifest: Decodable, Sendable, Equatable {
    let id: String
    let version: String
    let files: [File]

    struct File: Decodable, Sendable, Equatable {
        /// Path relative to the asset version root (mirrors the source tree 1:1).
        let path: String
        let size: Int64
        /// Hex SHA-256 of the file — verify downloads against this.
        let sha256: String
        /// Presigned GET URL, valid for a limited window; refetch the manifest
        /// if it expires.
        let url: String
    }
}

/// Standard error response from relay endpoints.
struct RelayErrorResponse: Decodable {
    let error: Body

    struct Body: Decodable {
        let message: String
        let type: String
    }
}
