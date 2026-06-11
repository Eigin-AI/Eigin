@testable import Eigin
import Foundation

final class FakeHealthService: HealthService, @unchecked Sendable {
    var authResult: HealthAuthResult = .authorized
    var weight: Double?
    var dietaryEnergy: Double = 0
    var activeEnergy: Double = 0
    var basalEnergy: Double = 0
    var dietarySamples: [DietarySample] = []
    var loggedEntries: [(
        calories: Double,
        protein: Double?,
        fat: Double?,
        carbs: Double?,
        mealName: String?,
        date: Date
    )] = []

    func authorize(canPromptUser: Bool) async -> HealthAuthResult {
        authResult
    }

    func readWeight(for date: Date) async throws -> Double? {
        weight
    }

    func readDietaryEnergy(for date: Date) async throws -> Double {
        dietaryEnergy
    }

    func readActiveEnergy(for date: Date) async throws -> Double {
        activeEnergy
    }

    func readBasalEnergy(for date: Date) async throws -> Double {
        basalEnergy
    }

    func readDietarySamples(for date: Date) async throws -> [DietarySample] {
        dietarySamples
    }

    func logDietaryEnergy(
        calories: Double, protein: Double?, fat: Double?,
        carbs: Double?, mealName: String?, date: Date
    ) async throws {
        loggedEntries.append((
            calories: calories,
            protein: protein,
            fat: fat,
            carbs: carbs,
            mealName: mealName,
            date: date
        ))
    }
}
