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
    ]

    private static let writeTypes: Set<HKSampleType> = [
        HKQuantityType(.dietaryEnergyConsumed),
        HKQuantityType(.dietaryProtein),
        HKQuantityType(.dietaryFatTotal),
        HKQuantityType(.dietaryCarbohydrates),
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

    func readWeight() async throws -> Double? {
        let type = HKQuantityType(.bodyMass)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let samples = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<
            [HKQuantitySample],
            Error
        >) in
            let query = HKSampleQuery(
                sampleType: type, predicate: nil,
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

    // MARK: - Helpers

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
