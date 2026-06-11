import Foundation

// MARK: - Protocol

protocol FoodLookupService: Sendable {
    func search(query: String, limit: Int) async -> Result<[FoodProduct], any Error>
    func getProduct(barcode: String) async -> Result<FoodProduct, any Error>
}

// MARK: - Value Types

struct FoodProduct {
    let barcode: String
    let name: String
    let brands: [String]?
    let servingSize: String?
    let caloriesPer100g: Double?
    let caloriesPerServing: Double?
    let proteinPer100g: Double?
    let fatPer100g: Double?
    let carbsPer100g: Double?
}
