import Foundation

/// Client-side credit conditions, distinct from `RelayClientError` (which models HTTP failures).
enum CreditsError: LocalizedError, Equatable {
    /// No wallet on device has spendable balance.
    case noCreditsRemaining
    /// The user dismissed the purchase sheet.
    case purchaseCancelled
    /// The purchase is awaiting approval (e.g. Ask to Buy).
    case purchasePending
    /// StoreKit returned a transaction that failed verification.
    case purchaseVerificationFailed
    /// No StoreKit product matched the configured product ID.
    case productNotFound

    var errorDescription: String? {
        switch self {
        case .noCreditsRemaining: "No credits remaining"
        case .purchaseCancelled: "Purchase cancelled"
        case .purchasePending: "Purchase is pending approval"
        case .purchaseVerificationFailed: "Purchase could not be verified"
        case .productNotFound: "Credit product not found"
        }
    }
}
