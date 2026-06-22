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
        let lower = body.lowercased()
        let hints = [
            "model_not_found",
            "model not found",
            "no such model",
            "unknown model",
            "invalid model",
            "unsupported model",
        ]
        if hints.contains(where: { lower.contains($0) }) { return true }
        // Phrasings like "The model `x` does not exist" or "model 'x' is not available".
        return lower.contains("model")
            && (lower.contains("does not exist")
                || lower.contains("is not available")
                || lower.contains("not a valid model"))
    }
}
