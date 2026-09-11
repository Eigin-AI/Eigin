#if DEBUG || EIGIN_DEV
import Foundation

final class FakeFoodLookupService: FoodLookupService, @unchecked Sendable {
    var searchResults: [FoodProduct] = []
    var searchError: (any Error)?
    var productResult: FoodProduct?
    var productError: (any Error)?

    private(set) var searchQueries: [(query: String, limit: Int)] = []
    private(set) var barcodeQueries: [String] = []

    func search(query: String, limit: Int) async -> Result<[FoodProduct], any Error> {
        searchQueries.append((query: query, limit: limit))
        if let error = searchError { return .failure(error) }
        return .success(searchResults)
    }

    func getProduct(barcode: String) async -> Result<FoodProduct, any Error> {
        barcodeQueries.append(barcode)
        if let error = productError { return .failure(error) }
        guard let product = productResult else {
            return .failure(OpenFoodFactsError.decodingFailed)
        }
        return .success(product)
    }
}
#endif
