import Foundation

/// Errors thrown by ``RelayClient``. Cases mirror the relay's documented error `type`s and
/// HTTP statuses (see `api.yaml`), plus client-side transport failures.
enum RelayClientError: LocalizedError, Equatable {
    /// Invalid `x-eigin-key` or unknown/expired credit token (401).
    case authentication(String?)
    /// Malformed request, missing field, or unknown product/model (400).
    case invalidRequest(String?)
    /// Balance below the admit floor or wallet not active (402).
    case insufficientCredits(String?)
    /// Per-token or per-IP rate limit, or quota exhausted (429).
    case rateLimit(String?)
    /// Inference not configured upstream (503).
    case serviceUnavailable(String?)
    /// Upstream provider error (502).
    case upstream(String?)
    /// Entitlement proof failed verification on redeem (422).
    case proofVerificationFailed(String?)
    /// Any other non-success status.
    case server(Int, String?)
    /// Response body could not be decoded.
    case decoding
    /// The relay URL or key is not configured in the bundle.
    case notConfigured
    /// Transport-level failure.
    case network(String)

    /// Map an HTTP status and optional error body to a `RelayClientError`.
    /// Prefers the body's `type` discriminator, falling back to the status code.
    static func from(status: Int, body: Data) -> RelayClientError {
        let envelope = try? JSONDecoder().decode(RelayErrorResponse.self, from: body)
        let message = envelope?.error.message

        switch envelope?.error.type {
        case "authentication_error": return .authentication(message)
        case "invalid_request_error": return .invalidRequest(message)
        case "insufficient_credits": return .insufficientCredits(message)
        case "rate_limit_error": return .rateLimit(message)
        case "service_unavailable": return .serviceUnavailable(message)
        case "upstream_error": return .upstream(message)
        default: break
        }

        switch status {
        case 401: return .authentication(message)
        case 400: return .invalidRequest(message)
        case 402: return .insufficientCredits(message)
        case 422: return .proofVerificationFailed(message)
        case 429: return .rateLimit(message)
        case 502: return .upstream(message)
        case 503: return .serviceUnavailable(message)
        default: return .server(status, message)
        }
    }

    var errorDescription: String? {
        switch self {
        case .authentication(let m): m ?? "Authentication failed"
        case .invalidRequest(let m): m ?? "Invalid request"
        case .insufficientCredits(let m): m ?? "Insufficient credits"
        case .rateLimit(let m): m ?? "Rate limited"
        case .serviceUnavailable(let m): m ?? "Service unavailable"
        case .upstream(let m): m ?? "Upstream error"
        case .proofVerificationFailed(let m): m ?? "Purchase verification failed"
        case .server(let code, let m): m ?? "Server error (\(code))"
        case .decoding: "Could not decode the response"
        case .notConfigured: "Relay is not configured"
        case .network(let m): m
        }
    }
}
