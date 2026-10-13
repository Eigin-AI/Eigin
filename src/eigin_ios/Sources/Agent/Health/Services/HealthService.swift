import Foundation

// MARK: - Protocol

protocol HealthService: Sendable {
    func authorize(canPromptUser: Bool) async -> HealthAuthResult
    /// Whether this device has Apple Health at all.
    func isAvailable() -> Bool
    /// Whether Apple Health has already asked about everything Eigin uses.
    func hasAsked() async -> Bool
    /// What Apple Health won't let Eigin save. It never says what Eigin may read.
    func notAllowedSaves() -> Set<HealthSave>

    // Nutrition & energy
    func readDietaryEnergy(for date: Date) async throws -> Double
    func readActiveEnergy(for date: Date) async throws -> Double
    func readBasalEnergy(for date: Date) async throws -> Double
    func readDietarySamples(for date: Date) async throws -> [DietarySample]

    /// Body
    func readWeight(for date: Date) async throws -> Double?

    // Activity
    func readSteps(for date: Date) async throws -> Double
    func readExerciseMinutes(for date: Date) async throws -> Double
    func readWorkouts(for date: Date) async throws -> [WorkoutSample]

    // Vitals
    func readRestingHeartRate(for date: Date) async throws -> Double?
    func readHeartRateVariability(for date: Date) async throws -> Double?

    /// Reads the sleep that belongs to `date`: the night ending the morning of
    /// that day. The query window runs from 18:00 the previous evening to 18:00
    /// on `date`, so an early-morning wake-up is attributed to the day it ends.
    func readSleep(for date: Date) async throws -> SleepSummary?

    /// Writes
    func logDietaryEnergy(
        calories: Double, protein: Double?, fat: Double?,
        carbs: Double?, mealName: String?, date: Date
    ) async throws
    func logWeight(_ kilograms: Double, date: Date) async throws
    /// Writes a single asleep interval. Stage detail is left to wearables.
    func logSleep(start: Date, end: Date) async throws
}

// MARK: - Value Types

enum HealthAuthResult {
    case authorized
    case denied(String)
}

/// A kind of data Eigin saves to Apple Health, as a person names it.
enum HealthSave: String, CaseIterable, Sendable {
    case meals
    case sleep
    case bodyMeasurements
}

struct DietarySample {
    let date: Date
    let calories: Double
    let protein: Double?
    let fat: Double?
    let carbs: Double?
    let mealName: String?
}

/// A night's sleep, broken down by stage. All values are in hours.
struct SleepSummary {
    /// Total time asleep (deep + core + rem).
    let asleep: Double
    let deep: Double
    let core: Double
    let rem: Double
    /// Time awake during the sleep window.
    let awake: Double
    /// Time in bed (where reported by the source).
    let inBed: Double
}

struct WorkoutSample {
    let type: String
    let start: Date
    /// Duration in seconds.
    let duration: TimeInterval
    /// Active energy burned in kilocalories, where available.
    let activeEnergy: Double?
    /// Distance in meters, where available.
    let distance: Double?
}
