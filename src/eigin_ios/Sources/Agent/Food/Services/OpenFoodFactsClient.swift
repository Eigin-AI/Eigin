import Foundation

/// Client for the Open Food Facts public API.
///
/// Requires a descriptive `User-Agent` header on every request per OFF policy.
/// Search endpoint is rate-limited to 10 req/min; product lookups to 100 req/min.
struct OpenFoodFactsClient: FoodLookupService {
    private let userAgent = "Eigin/1.0 (https://eigin.app)"

    // MARK: - Search

    func search(query: String, limit: Int = 5) async -> Result<[FoodProduct], any Error> {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url =
              URL(
                  string: "https://world.openfoodfacts.org/cgi/search.pl?search_terms=\(encoded)&json=1&page_size=\(limit)&fields=code,product_name,brands,serving_size,nutriments"
              )
        else {
            return .success([])
        }

        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            return .failure(error)
        }

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            return .failure(OpenFoodFactsError.badStatus(http.statusCode))
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let products = json["products"] as? [[String: Any]]
        else {
            return .failure(OpenFoodFactsError.decodingFailed)
        }

        return .success(products.compactMap(Self.parseProduct))
    }

    // MARK: - Product by Barcode

    func getProduct(barcode: String) async -> Result<FoodProduct, any Error> {
        guard let url =
            URL(
                string: "https://world.openfoodfacts.org/api/v2/product/\(barcode)?fields=code,product_name,brands,serving_size,nutriments"
            )
        else {
            return .failure(OpenFoodFactsError.decodingFailed)
        }

        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            return .failure(error)
        }

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            return .failure(OpenFoodFactsError.badStatus(http.statusCode))
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let productDict = json["product"] as? [String: Any],
              let product = Self.parseProduct(productDict)
        else {
            return .failure(OpenFoodFactsError.decodingFailed)
        }

        return .success(product)
    }

    // MARK: - Parsing

    private static func parseProduct(_ dict: [String: Any]) -> FoodProduct? {
        let name = dict["product_name"] as? String ?? ""
        guard !name.isEmpty else { return nil }

        let barcode = dict["code"] as? String ?? ""
        let brand = dict["brands"] as? String
        let servingSize = dict["serving_size"] as? String
        let nutriments = dict["nutriments"] as? [String: Any]

        return FoodProduct(
            barcode: barcode,
            name: name,
            brand: brand,
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
