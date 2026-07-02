import Foundation

/// Client for the Eigin Relay HTTP API,
protocol RelayClient: Sendable {
    /// Proxied web search.
    /// - Parameters:
    ///   - region: ISO 3166-1 alpha-2 region code used to boost regionally relevant results.
    ///   - focus: A named site focus (e.g. "recipes"), mapped server-side to a curated domain list.
    func search(query: String, region: String?, focus: String?) async throws -> String
    /// Available credit products and the credits each grants. Fetched before any wallet exists.
    func products() async throws -> [CreditProduct]
    /// Redeem an entitlement proof, minting or restoring a credit token.
    func redeem(type: String, proof: String) async throws -> RedeemResponse
    /// Current balance for a credit token.
    func balance(token: String) async throws -> BalanceResponse
    /// Available model IDs. The catalog is public, gated only by the relay key.
    func models() async throws -> [String]
}

/// Relay configuration read from the bundle's Info.plist (populated per build target).
enum RelayConfiguration {
    static var baseURL: URL? {
        (Bundle.main.infoDictionary?["EiginRelayURL"] as? String).flatMap(URL.init(string:))
    }

    static var apiKey: String? {
        Bundle.main.infoDictionary?["EiginRelayKey"] as? String
    }
}

/// Default `RelayClient` backed by `URLSession`.
struct DefaultRelayClient: RelayClient {
    private let baseURL: URL?
    private let apiKey: String?
    private let session: URLSession

    init(
        baseURL: URL? = RelayConfiguration.baseURL,
        apiKey: String? = RelayConfiguration.apiKey,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.session = session
    }

    func search(query: String, region: String? = nil, focus: String? = nil) async throws -> String {
        var queryItems = [URLQueryItem(name: "q", value: query)]
        if let region { queryItems.append(URLQueryItem(name: "region", value: region)) }
        if let focus { queryItems.append(URLQueryItem(name: "focus", value: focus)) }

        var request = try makeRequest(path: "/v1/search", queryItems: queryItems)
        request.httpMethod = "GET"
        let data = try await perform(request)
        return String(data: data, encoding: .utf8) ?? ""
    }

    func products() async throws -> [CreditProduct] {
        var request = try makeRequest(path: "/v1/credits/products")
        request.httpMethod = "GET"
        let response: ProductsListResponse = try await decode(request)
        return response.products
    }

    func redeem(type: String, proof: String) async throws -> RedeemResponse {
        var request = try makeRequest(path: "/v1/credits/redeem")
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(RedeemRequest(type: type, proof: proof))
        return try await decode(request)
    }

    func balance(token: String) async throws -> BalanceResponse {
        var request = try makeRequest(path: "/v1/credits/balance", token: token)
        request.httpMethod = "GET"
        return try await decode(request)
    }

    func models() async throws -> [String] {
        var request = try makeRequest(path: "/v1/models")
        request.httpMethod = "GET"
        let response: ModelsListResponse = try await decode(request)
        return response.data.map(\.id).sorted()
    }

    // MARK: - Request plumbing

    private func makeRequest(
        path: String,
        queryItems: [URLQueryItem] = [],
        token: String? = nil
    ) throws -> URLRequest {
        guard let baseURL, let apiKey, !apiKey.isEmpty else {
            throw RelayClientError.notConfigured
        }

        var components = URLComponents(
            url: baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )
        if !queryItems.isEmpty {
            components?.queryItems = queryItems
        }
        guard let url = components?.url else {
            throw RelayClientError.notConfigured
        }

        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue(apiKey, forHTTPHeaderField: "X-Eigin-Key")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    /// Send a request, validating the status and mapping error bodies to `RelayClientError`.
    private func perform(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw RelayClientError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw RelayClientError.network("Non-HTTP response")
        }
        guard (200 ... 299).contains(http.statusCode) else {
            throw RelayClientError.from(status: http.statusCode, body: data)
        }
        return data
    }

    private func decode<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data = try await perform(request)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw RelayClientError.decoding
        }
    }
}
