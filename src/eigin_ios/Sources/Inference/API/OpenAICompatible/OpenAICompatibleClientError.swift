import EiginSDK
import Foundation

/// Errors thrown by ``OpenAICompatibleClient`` during URL construction, response validation, or
/// HTTP failures.
enum OpenAICompatibleClientError: LocalizedError {
    case invalidURL(String)
    case invalidResponse
    case httpError(Int, body: String? = nil)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url): "Invalid URL: \(url)"
        case .invalidResponse: "Invalid response from server"
        case .httpError(let code, _): "HTTP error \(code)"
        }
    }

    /// Whether the error indicates the requested model is unknown to the provider (retired,
    /// renamed, or never existed). Providers signal this as a 404 or 400 with a model-specific
    /// message, so we require both a matching status and a model hint in the body to avoid
    /// treating generic 404/400 failures as recoverable.
    var isModelNotFound: Bool {
        guard case .httpError(let code, let body) = self, code == 404 || code == 400 else {
            return false
        }
        guard let body else { return false }
        return EiginSDK.Experimental.Inference.isModelNotFound(status: UInt16(code), body: body)
    }
}
