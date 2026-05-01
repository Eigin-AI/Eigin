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
}
