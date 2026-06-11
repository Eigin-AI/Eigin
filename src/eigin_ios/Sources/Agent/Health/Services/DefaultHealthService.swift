import Foundation
import HealthKit

final class DefaultHealthService: HealthService, @unchecked Sendable {
    private let store = HKHealthStore()

    // MARK: - Types

    private static let readTypes: Set<HKObjectType> = [
        HKQuantityType(.dietaryEnergyConsumed),
        HKQuantityType(.bodyMass),
        HKQuantityType(.activeEnergyBurned),
        HKQuantityType(.basalEnergyBurned),
        HKQuantityType(.dietaryProtein),
        HKQuantityType(.dietaryFatTotal),
        HKQuantityType(.dietaryCarbohydrates),
        HKQuantityType(.stepCount),
        HKQuantityType(.appleExerciseTime),
        HKQuantityType(.restingHeartRate),
        HKQuantityType(.heartRateVariabilitySDNN),
        HKCategoryType(.sleepAnalysis),
        HKWorkoutType.workoutType(),
    ]

    private static let writeTypes: Set<HKSampleType> = [
        HKQuantityType(.dietaryEnergyConsumed),
        HKQuantityType(.dietaryProtein),
        HKQuantityType(.dietaryFatTotal),
        HKQuantityType(.dietaryCarbohydrates),
        HKQuantityType(.bodyMass),
        HKCategoryType(.sleepAnalysis),
    ]

    // MARK: - Authorization

    func authorize(canPromptUser: Bool) async -> HealthAuthResult {
        guard HKHealthStore.isHealthDataAvailable() else {
            return .denied("Health data is not available on this device.")
        }

        if canPromptUser {
            do {
                try await store.requestAuthorization(
                    toShare: Self.writeTypes,
                    read: Self.readTypes
                )
                return .authorized
            } catch {
                return .denied("Health access request failed: \(error.localizedDescription)")
            }
        }

        // In background, check if we can write (HealthKit only reveals write auth status)
        let energyType = HKQuantityType(.dietaryEnergyConsumed)
        let status = store.authorizationStatus(for: energyType)
        switch status {
        case .sharingAuthorized:
            return .authorized
        case .sharingDenied:
            return .denied("Health access was denied. Enable it in Settings.")
        case .notDetermined:
            return .denied("Health access cannot be requested while in the background.")
        @unknown default:
            return .denied("Health access is unavailable.")
        }
    }

    // MARK: - Read

    func readWeight(for date: Date) async throws -> Double? {
        let type = HKQuantityType(.bodyMass)
        let predicate = dayPredicate(for: date)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let samples = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<
            [HKQuantitySample],
            Error
        >) in
            let query = HKSampleQuery(
                sampleType: type, predicate: predicate,
                limit: 1, sortDescriptors: [sort]
            ) { _, results, error in
                if let error { cont.resume(throwing: error) }
                else { cont.resume(returning: (results as? [HKQuantitySample]) ?? []) }
            }
            store.execute(query)
        }
        guard let sample = samples.first else { return nil }
        return sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
    }

    func readDietaryEnergy(for date: Date) async throws -> Double {
        try await cumulativeSum(for: .dietaryEnergyConsumed, unit: .kilocalorie(), date: date)
    }

    func readActiveEnergy(for date: Date) async throws -> Double {
        try await cumulativeSum(for: .activeEnergyBurned, unit: .kilocalorie(), date: date)
    }

    func readBasalEnergy(for date: Date) async throws -> Double {
        try await cumulativeSum(for: .basalEnergyBurned, unit: .kilocalorie(), date: date)
    }

    func readDietarySamples(for date: Date) async throws -> [DietarySample] {
        let type = HKQuantityType(.dietaryEnergyConsumed)
        let predicate = dayPredicate(for: date)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        let samples = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<
            [HKQuantitySample],
            Error
        >) in
            let query = HKSampleQuery(
                sampleType: type, predicate: predicate,
                limit: HKObjectQueryNoLimit, sortDescriptors: [sort]
            ) { _, results, error in
                if let error { cont.resume(throwing: error) }
                else { cont.resume(returning: (results as? [HKQuantitySample]) ?? []) }
            }
            store.execute(query)
        }

        return samples.map { sample in
            let kcal = sample.quantity.doubleValue(for: .kilocalorie())
            let mealName = sample.metadata?[HKMetadataKeyFoodType] as? String
            return DietarySample(
                date: sample.startDate,
                calories: kcal,
                protein: nil,
                fat: nil,
                carbs: nil,
                mealName: mealName
            )
        }
    }

    func readSteps(for date: Date) async throws -> Double {
        try await cumulativeSum(for: .stepCount, unit: .count(), date: date)
    }

    func readExerciseMinutes(for date: Date) async throws -> Double {
        try await cumulativeSum(for: .appleExerciseTime, unit: .minute(), date: date)
    }

    func readRestingHeartRate(for date: Date) async throws -> Double? {
        try await discreteAverage(
            for: .restingHeartRate,
            unit: HKUnit.count().unitDivided(by: .minute()),
            date: date
        )
    }

    func readHeartRateVariability(for date: Date) async throws -> Double? {
        try await discreteAverage(
            for: .heartRateVariabilitySDNN,
            unit: .secondUnit(with: .milli),
            date: date
        )
    }

    func readWorkouts(for date: Date) async throws -> [WorkoutSample] {
        let predicate = dayPredicate(for: date)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        let workouts = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<
            [HKWorkout],
            Error
        >) in
            let query = HKSampleQuery(
                sampleType: .workoutType(), predicate: predicate,
                limit: HKObjectQueryNoLimit, sortDescriptors: [sort]
            ) { _, results, error in
                if let error { cont.resume(throwing: error) }
                else { cont.resume(returning: (results as? [HKWorkout]) ?? []) }
            }
            store.execute(query)
        }

        return workouts.map { workout in
            let energy = workout.statistics(for: HKQuantityType(.activeEnergyBurned))?
                .sumQuantity()?.doubleValue(for: .kilocalorie())
            let distance = workout.statistics(for: HKQuantityType(.distanceWalkingRunning))?
                .sumQuantity()?.doubleValue(for: .meter())
            return WorkoutSample(
                type: workout.workoutActivityType.displayName,
                start: workout.startDate,
                duration: workout.duration,
                activeEnergy: energy,
                distance: distance
            )
        }
    }

    func readSleep(for date: Date) async throws -> SleepSummary? {
        let predicate = sleepNightPredicate(for: date)

        let samples = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<
            [HKCategorySample],
            Error
        >) in
            let query = HKSampleQuery(
                sampleType: HKCategoryType(.sleepAnalysis), predicate: predicate,
                limit: HKObjectQueryNoLimit, sortDescriptors: nil
            ) { _, results, error in
                if let error { cont.resume(throwing: error) }
                else { cont.resume(returning: (results as? [HKCategorySample]) ?? []) }
            }
            store.execute(query)
        }

        guard !samples.isEmpty else { return nil }

        var deep = 0.0, core = 0.0, rem = 0.0, awake = 0.0, inBed = 0.0
        for sample in samples {
            let hours = sample.endDate.timeIntervalSince(sample.startDate) / 3600
            switch HKCategoryValueSleepAnalysis(rawValue: sample.value) {
            case .asleepDeep: deep += hours
            case .asleepCore: core += hours
            case .asleepREM: rem += hours
            case .asleepUnspecified: core += hours
            case .awake: awake += hours
            case .inBed: inBed += hours
            default: break
            }
        }

        return SleepSummary(
            asleep: deep + core + rem,
            deep: deep, core: core, rem: rem,
            awake: awake, inBed: inBed
        )
    }

    // MARK: - Write

    func logDietaryEnergy(
        calories: Double, protein: Double?, fat: Double?,
        carbs: Double?, mealName: String?, date: Date
    ) async throws {
        var metadata: [String: Any] = [:]
        if let mealName { metadata[HKMetadataKeyFoodType] = mealName }

        var samples: [HKQuantitySample] = []

        samples.append(HKQuantitySample(
            type: HKQuantityType(.dietaryEnergyConsumed),
            quantity: HKQuantity(unit: .kilocalorie(), doubleValue: calories),
            start: date, end: date, metadata: metadata
        ))

        if let protein {
            samples.append(HKQuantitySample(
                type: HKQuantityType(.dietaryProtein),
                quantity: HKQuantity(unit: .gram(), doubleValue: protein),
                start: date, end: date, metadata: metadata
            ))
        }

        if let fat {
            samples.append(HKQuantitySample(
                type: HKQuantityType(.dietaryFatTotal),
                quantity: HKQuantity(unit: .gram(), doubleValue: fat),
                start: date, end: date, metadata: metadata
            ))
        }

        if let carbs {
            samples.append(HKQuantitySample(
                type: HKQuantityType(.dietaryCarbohydrates),
                quantity: HKQuantity(unit: .gram(), doubleValue: carbs),
                start: date, end: date, metadata: metadata
            ))
        }

        let correlation = HKCorrelation(
            type: HKCorrelationType(.food),
            start: date, end: date,
            objects: Set(samples),
            metadata: metadata
        )

        try await store.save(correlation)
    }

    func logWeight(_ kilograms: Double, date: Date) async throws {
        let sample = HKQuantitySample(
            type: HKQuantityType(.bodyMass),
            quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: kilograms),
            start: date, end: date
        )
        try await store.save(sample)
    }

    func logSleep(start: Date, end: Date) async throws {
        let sample = HKCategorySample(
            type: HKCategoryType(.sleepAnalysis),
            value: HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            start: start, end: end
        )
        try await store.save(sample)
    }

    // MARK: - Helpers

    /// Average of discrete samples (e.g. heart rate) over the day, or nil when
    /// no samples exist.
    private func discreteAverage(
        for identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        date: Date
    ) async throws -> Double? {
        let type = HKQuantityType(identifier)
        let predicate = dayPredicate(for: date)

        return try await withCheckedThrowingContinuation { cont in
            let query = HKStatisticsQuery(
                quantityType: type, quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, statistics, error in
                if let error { cont.resume(throwing: error); return }
                cont.resume(returning: statistics?.averageQuantity()?.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    /// Window for the night ending on the morning of `date`: 18:00 the previous
    /// evening through 18:00 on `date`.
    private func sleepNightPredicate(for date: Date) -> NSPredicate {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .hour, value: 18, to: startOfDay)!
        let start = calendar.date(byAdding: .hour, value: -6, to: startOfDay)!
        return HKQuery.predicateForSamples(withStart: start, end: end, options: [])
    }

    private func cumulativeSum(
        for identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        date: Date
    ) async throws -> Double {
        let type = HKQuantityType(identifier)
        let predicate = dayPredicate(for: date)

        return try await withCheckedThrowingContinuation { cont in
            let query = HKStatisticsQuery(
                quantityType: type, quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, error in
                if let error { cont.resume(throwing: error); return }
                let value = statistics?.sumQuantity()?.doubleValue(for: unit) ?? 0
                cont.resume(returning: value)
            }
            store.execute(query)
        }
    }

    private func dayPredicate(for date: Date) -> NSPredicate {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        return HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
    }
}

// MARK: - Workout naming

private extension HKWorkoutActivityType {
    /// A human-readable name for the common activity types. Falls back to a
    /// generic label for the long tail HealthKit defines.
    var displayName: String {
        switch self {
        case .walking: "Walking"
        case .running: "Running"
        case .cycling: "Cycling"
        case .swimming: "Swimming"
        case .hiking: "Hiking"
        case .yoga: "Yoga"
        case .functionalStrengthTraining, .traditionalStrengthTraining: "Strength training"
        case .highIntensityIntervalTraining: "HIIT"
        case .elliptical: "Elliptical"
        case .rowing: "Rowing"
        case .coreTraining: "Core training"
        case .pilates: "Pilates"
        case .dance, .cardioDance, .socialDance: "Dance"
        case .stairClimbing, .stairs: "Stair climbing"
        case .mixedCardio: "Cardio"
        default: "Workout"
        }
    }
}
