import Foundation

/// Lightweight client for the Eigin Relay web search endpoint.
/// Performs a background HTTP request — no WKWebView needed.
enum RelaySearchClient {
    // MARK: - Configuration

    private static let baseURL: URL? = (Bundle.main.infoDictionary?["EiginRelayURL"] as? String)
        .flatMap(URL.init(string:))
    private static let apiKey: String? = Bundle.main.infoDictionary?["EiginRelayKey"] as? String

    // MARK: - API

    struct SearchResult {
        let json: String
    }

    enum SearchError: Error {
        case badStatus(Int)
        case network(Error)
    }

    /// Calls the relay's `/search` endpoint and returns the raw Mojeek JSON.
    static func search(query: String) async -> Result<SearchResult, SearchError> {
        guard let baseURL, let apiKey, !apiKey.isEmpty else {
            return .failure(.badStatus(0))
        }

        guard var components = URLComponents(
            url: baseURL.appendingPathComponent("search"),
            resolvingAgainstBaseURL: false
        ) else {
            return .failure(.badStatus(0))
        }
        components.queryItems = [URLQueryItem(name: "q", value: query)]

        guard let url = components.url else {
            return .failure(.badStatus(0))
        }

        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue(apiKey, forHTTPHeaderField: "X-Eigin-Key")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0

            guard (200 ..< 300).contains(status) else {
                return .failure(.badStatus(status))
            }

            let body = String(data: data, encoding: .utf8) ?? ""
            return .success(SearchResult(json: body))

        } catch {
            return .failure(.network(error))
        }
    }
}
