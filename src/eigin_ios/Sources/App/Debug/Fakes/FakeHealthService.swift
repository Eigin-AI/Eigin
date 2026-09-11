#if DEBUG || EIGIN_DEV
import Foundation

final class FakeHealthService: HealthService, @unchecked Sendable {
    var authResult: HealthAuthResult = .authorized
    var weight: Double?
    var dietaryEnergy: Double = 0
    var activeEnergy: Double = 0
    var basalEnergy: Double = 0
    var dietarySamples: [DietarySample] = []
    var steps: Double = 0
    var exerciseMinutes: Double = 0
    var workouts: [WorkoutSample] = []
    var restingHeartRate: Double?
    var heartRateVariability: Double?
    var sleep: SleepSummary?
    var loggedEntries: [(
        calories: Double,
        protein: Double?,
        fat: Double?,
        carbs: Double?,
        mealName: String?,
        date: Date
    )] = []
    var loggedWeights: [(kilograms: Double, date: Date)] = []
    var loggedSleep: [(start: Date, end: Date)] = []

    func authorize(canPromptUser: Bool) async -> HealthAuthResult {
        authResult
    }

    func readWeight(for date: Date) async throws -> Double? {
        weight
    }

    func readSteps(for date: Date) async throws -> Double {
        steps
    }

    func readExerciseMinutes(for date: Date) async throws -> Double {
        exerciseMinutes
    }

    func readWorkouts(for date: Date) async throws -> [WorkoutSample] {
        workouts
    }

    func readRestingHeartRate(for date: Date) async throws -> Double? {
        restingHeartRate
    }

    func readHeartRateVariability(for date: Date) async throws -> Double? {
        heartRateVariability
    }

    func readSleep(for date: Date) async throws -> SleepSummary? {
        sleep
    }

    func logWeight(_ kilograms: Double, date: Date) async throws {
        loggedWeights.append((kilograms: kilograms, date: date))
    }

    func logSleep(start: Date, end: Date) async throws {
        loggedSleep.append((start: start, end: end))
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
#endif
