import Foundation

// MARK: - Protocol

protocol HealthService: Sendable {
    func authorize(canPromptUser: Bool) async -> HealthAuthResult
    func readWeight(for date: Date) async throws -> Double?
    func readDietaryEnergy(for date: Date) async throws -> Double
    func readActiveEnergy(for date: Date) async throws -> Double
    func readBasalEnergy(for date: Date) async throws -> Double
    func readDietarySamples(for date: Date) async throws -> [DietarySample]
    func logDietaryEnergy(
        calories: Double, protein: Double?, fat: Double?,
        carbs: Double?, mealName: String?, date: Date
    ) async throws
}

// MARK: - Value Types

enum HealthAuthResult {
    case authorized
    case denied(String)
}

struct DietarySample {
    let date: Date
    let calories: Double
    let protein: Double?
    let fat: Double?
    let carbs: Double?
    let mealName: String?
}
