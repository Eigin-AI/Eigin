import Foundation

/// Client for the Open Food Facts Search-a-licious API.
///
/// The legacy `cgi/search.pl` endpoint is deprecated and returns 503 globally.
/// Search-a-licious is the replacement Elasticsearch-backed service.
///
/// All product hits are flat dictionaries in a top-level `hits` array.
/// `brands` is returned as an array; `product_name` is a plain string.
struct OpenFoodFactsClient: FoodLookupService {
    private let urlSession: URLSession
    private let deviceInfo: any DeviceInfoService
    private let languageCode: String

    init(
        urlSession: URLSession = .shared,
        deviceInfo: any DeviceInfoService = DefaultDeviceInfoService(),
        languageCode: String = "en"
    ) {
        self.urlSession = urlSession
        self.deviceInfo = deviceInfo
        self.languageCode = languageCode
    }

    // MARK: - Search

    func search(query: String, limit: Int = 5) async -> Result<[FoodProduct], any Error> {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "search.openfoodfacts.org"
        components.path = "/search"
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "page_size", value: String(limit)),
            URLQueryItem(
                name: "fields",
                value: "code,product_name,brands,nutriments"
            ),
            URLQueryItem(name: "langs", value: languageCode),
        ]

        guard let url = components.url else {
            return .failure(OpenFoodFactsError.decodingFailed)
        }

        var request = URLRequest(url: url, timeoutInterval: 10)
        configureHeaders(for: &request)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            return .failure(error)
        }

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            return .failure(OpenFoodFactsError.badStatus(http.statusCode))
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hits = json["hits"] as? [[String: Any]]
        else {
            return .failure(OpenFoodFactsError.decodingFailed)
        }

        return .success(hits.compactMap(Self.parseProduct))
    }

    // MARK: - Product by Barcode

    func getProduct(barcode: String) async -> Result<FoodProduct, any Error> {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "search.openfoodfacts.org"
        components.path = "/search"
        components.queryItems = [
            URLQueryItem(name: "q", value: "code:\"\(barcode)\""),
            URLQueryItem(name: "page_size", value: "1"),
            URLQueryItem(
                name: "fields",
                value: "code,product_name,brands,nutriments"
            ),
            URLQueryItem(name: "langs", value: languageCode),
        ]

        guard let url = components.url else {
            return .failure(OpenFoodFactsError.decodingFailed)
        }

        var request = URLRequest(url: url, timeoutInterval: 10)
        configureHeaders(for: &request)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            return .failure(error)
        }

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            return .failure(OpenFoodFactsError.badStatus(http.statusCode))
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hits = json["hits"] as? [[String: Any]],
              let first = hits.first,
              let product = Self.parseProduct(first)
        else {
            return .failure(OpenFoodFactsError.decodingFailed)
        }

        return .success(product)
    }

    // MARK: - Headers

    private func configureHeaders(for request: inout URLRequest) {
        let appName = deviceInfo.appName().isEmpty ? "Eigin" : deviceInfo.appName()
        let appVersion = deviceInfo.appVersion().isEmpty ? "1.0" : deviceInfo.appVersion()
        let build = deviceInfo.appBuildVersion().isEmpty ? "0" : deviceInfo.appBuildVersion()
        let system = deviceInfo.systemVersion().isEmpty ? "iOS" : "iOS/\(deviceInfo.systemVersion())"
        let userAgent = "\(appName)/\(appVersion) (+https://eigin.ai) \(system) \(appName)/\(appVersion)+\(build)"

        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("support@eigin.ai", forHTTPHeaderField: "From")
    }

    // MARK: - Parsing

    private static func parseProduct(_ dict: [String: Any]) -> FoodProduct? {
        guard let name = dict["product_name"] as? String, !name.isEmpty else { return nil }

        let barcode = dict["code"] as? String ?? ""
        let brands = dict["brands"] as? [String]
        let nutriments = dict["nutriments"] as? [String: Any]

        // Serving size is not reliably returned; try to read if present
        let servingSize = dict["serving_size"] as? String

        return FoodProduct(
            barcode: barcode,
            name: name,
            brands: brands,
            servingSize: servingSize,
            caloriesPer100g: nutriments?["energy-kcal_100g"] as? Double,
            caloriesPerServing: nutriments?["energy-kcal_serving"] as? Double,
            proteinPer100g: nutriments?["proteins_100g"] as? Double,
            fatPer100g: nutriments?["fat_100g"] as? Double,
            carbsPer100g: nutriments?["carbohydrates_100g"] as? Double
        )
    }
}

// MARK: - Errors

enum OpenFoodFactsError: LocalizedError {
    case badStatus(Int)
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .badStatus(let code): "Open Food Facts returned status \(code)."
        case .decodingFailed: "Failed to decode Open Food Facts response."
        }
    }
}
