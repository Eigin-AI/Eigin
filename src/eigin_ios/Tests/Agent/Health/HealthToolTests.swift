@testable import Eigin
import Foundation
import SwiftData
import Testing

@Suite("Health Tools", .serialized)
struct HealthToolTests {
    // MARK: - Helpers

    @MainActor
    private func makeAgent() throws -> (Agent, ModelContainer) {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Schema(SchemaV1.models, version: SchemaV1.versionIdentifier),
            configurations: config
        )
        let agent = Agent(name: "TestAgent", providerID: UUID(), model: "test-model")
        container.mainContext.insert(agent)
        return (agent, container)
    }

    private func makeCall(name: String, arguments: String) -> ToolCall {
        ToolCall(
            id: "call_\(name)",
            type: "function",
            function: .init(name: name, arguments: arguments)
        )
    }

    private func sampleDietarySamples() -> [DietarySample] {
        [
            DietarySample(
                date: Date(), calories: 450, protein: 25,
                fat: 15, carbs: 50, mealName: "Oatmeal with berries"
            ),
            DietarySample(
                date: Date(), calories: 650, protein: 35,
                fat: 20, carbs: 60, mealName: "Chicken salad"
            ),
        ]
    }

    // MARK: - LogFoodTool

    @Test @MainActor func logFoodSuccess() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container
        let service = FakeHealthService()

        let tool = LogFoodTool(healthService: service, canPromptUser: true)
        let call = makeCall(name: "log_food", arguments: """
        {"calories":450,"protein_g":25,"fat_g":15,"carbs_g":50,"meal_name":"Oatmeal with berries"}
        """)
        let result = await tool.execute(call, agent: agent)

        #expect(!result.isError)
        #expect(result.content.contains("450"))
        #expect(result.content.contains("Oatmeal with berries"))
        #expect(service.loggedEntries.count == 1)
        #expect(service.loggedEntries.first?.calories == 450)
        #expect(service.loggedEntries.first?.protein == 25)
        #expect(service.loggedEntries.first?.mealName == "Oatmeal with berries")
    }

    @Test @MainActor func logFoodCaloriesOnly() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container
        let service = FakeHealthService()

        let tool = LogFoodTool(healthService: service, canPromptUser: true)
        let call = makeCall(name: "log_food", arguments: """
        {"calories":200,"meal_name":"Snack"}
        """)
        let result = await tool.execute(call, agent: agent)

        #expect(!result.isError)
        #expect(service.loggedEntries.count == 1)
        #expect(service.loggedEntries.first?.protein == nil)
        #expect(service.loggedEntries.first?.fat == nil)
    }

    @Test @MainActor func logFoodMissingCalories() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container
        let service = FakeHealthService()

        let tool = LogFoodTool(healthService: service, canPromptUser: true)
        let call = makeCall(name: "log_food", arguments: """
        {"meal_name":"Mystery food"}
        """)
        let result = await tool.execute(call, agent: agent)

        #expect(result.isError)
        #expect(result.content.contains("calories"))
        #expect(service.loggedEntries.isEmpty)
    }

    @Test @MainActor func logFoodAuthDenied() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container
        let service = FakeHealthService()
        service.authResult = .denied("Health access denied.")

        let tool = LogFoodTool(healthService: service, canPromptUser: true)
        let call = makeCall(name: "log_food", arguments: """
        {"calories":300,"meal_name":"Toast"}
        """)
        let result = await tool.execute(call, agent: agent)

        #expect(result.isError)
        #expect(result.content.contains("denied"))
        #expect(service.loggedEntries.isEmpty)
    }

    @Test @MainActor func logFoodNilServiceReturnsError() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container

        let tool = LogFoodTool(healthService: nil, canPromptUser: true)
        let call = makeCall(name: "log_food", arguments: """
        {"calories":300,"meal_name":"Toast"}
        """)
        let result = await tool.execute(call, agent: agent)

        #expect(result.isError)
        #expect(result.content.contains("unavailable"))
    }

    // MARK: - GetHealthLogTool

    @Test @MainActor func getFoodLogDietaryEntries() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container
        let service = FakeHealthService()
        service.dietarySamples = sampleDietarySamples()

        let tool = GetHealthLogTool(healthService: service, canPromptUser: true)
        let call = makeCall(name: "get_health_log", arguments: """
        {"include":["dietary_entries"]}
        """)
        let result = await tool.execute(call, agent: agent)

        #expect(!result.isError)
        #expect(result.content.contains("Oatmeal with berries"))
        #expect(result.content.contains("Chicken salad"))
        #expect(result.content.contains("450"))
        #expect(result.content.contains("650"))
    }

    @Test @MainActor func getFoodLogCaloriesAndActivity() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container
        let service = FakeHealthService()
        service.dietaryEnergy = 1200
        service.activeEnergy = 350
        service.basalEnergy = 1500

        let tool = GetHealthLogTool(healthService: service, canPromptUser: true)
        let call = makeCall(name: "get_health_log", arguments: """
        {"include":["calories_consumed","active_calories","resting_calories"]}
        """)
        let result = await tool.execute(call, agent: agent)

        #expect(!result.isError)
        #expect(result.content.contains("1200"))
        #expect(result.content.contains("350"))
        #expect(result.content.contains("1500"))
    }

    @Test @MainActor func getFoodLogWeight() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container
        let service = FakeHealthService()
        service.weight = 78.5

        let tool = GetHealthLogTool(healthService: service, canPromptUser: true)
        let call = makeCall(name: "get_health_log", arguments: """
        {"include":["weight"]}
        """)
        let result = await tool.execute(call, agent: agent)

        #expect(!result.isError)
        #expect(result.content.contains("78.5"))
    }

    @Test @MainActor func getFoodLogWeightUnavailable() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container
        let service = FakeHealthService()
        service.weight = nil

        let tool = GetHealthLogTool(healthService: service, canPromptUser: true)
        let call = makeCall(name: "get_health_log", arguments: """
        {"include":["weight"]}
        """)
        let result = await tool.execute(call, agent: agent)

        #expect(!result.isError)
        #expect(result.content.contains("No weight data"))
    }

    @Test @MainActor func getFoodLogWeightForSpecificDate() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container
        let service = FakeHealthService()
        service.weight = 87.93

        let tool = GetHealthLogTool(healthService: service, canPromptUser: true)
        let call = makeCall(name: "get_health_log", arguments: """
        {"include":["weight"],"date":"2026-04-12"}
        """)
        let result = await tool.execute(call, agent: agent)

        #expect(!result.isError)
        #expect(result.content.contains("87.93"))
    }

    @Test @MainActor func getFoodLogScopedReturnOmitsUnrequested() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container
        let service = FakeHealthService()
        service.weight = 80.0
        service.dietaryEnergy = 1500
        service.activeEnergy = 400

        let tool = GetHealthLogTool(healthService: service, canPromptUser: true)
        let call = makeCall(name: "get_health_log", arguments: """
        {"include":["calories_consumed"]}
        """)
        let result = await tool.execute(call, agent: agent)

        #expect(!result.isError)
        #expect(result.content.contains("1500"))
        #expect(!result.content.contains("weight_kg"))
        #expect(!result.content.contains("active_calories"))
    }

    @Test @MainActor func getFoodLogEmptyInclude() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container
        let service = FakeHealthService()

        let tool = GetHealthLogTool(healthService: service, canPromptUser: true)
        let call = makeCall(name: "get_health_log", arguments: """
        {"include":[]}
        """)
        let result = await tool.execute(call, agent: agent)

        #expect(result.isError)
        #expect(result.content.contains("empty"))
    }

    @Test @MainActor func getFoodLogInvalidFields() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container
        let service = FakeHealthService()

        let tool = GetHealthLogTool(healthService: service, canPromptUser: true)
        let call = makeCall(name: "get_health_log", arguments: """
        {"include":["heart_rate","blood_pressure"]}
        """)
        let result = await tool.execute(call, agent: agent)

        #expect(result.isError)
        #expect(result.content.contains("No valid fields"))
    }

    @Test @MainActor func getFoodLogAuthDenied() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container
        let service = FakeHealthService()
        service.authResult = .denied("Health access denied.")

        let tool = GetHealthLogTool(healthService: service, canPromptUser: true)
        let call = makeCall(name: "get_health_log", arguments: """
        {"include":["weight"]}
        """)
        let result = await tool.execute(call, agent: agent)

        #expect(result.isError)
        #expect(result.content.contains("denied"))
    }

    @Test @MainActor func getFoodLogNilServiceReturnsError() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container

        let tool = GetHealthLogTool(healthService: nil, canPromptUser: true)
        let call = makeCall(name: "get_health_log", arguments: """
        {"include":["weight"]}
        """)
        let result = await tool.execute(call, agent: agent)

        #expect(result.isError)
        #expect(result.content.contains("unavailable"))
    }

    @Test @MainActor func getHealthLogActivity() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container
        let service = FakeHealthService()
        service.steps = 8423
        service.exerciseMinutes = 42

        let tool = GetHealthLogTool(healthService: service, canPromptUser: true)
        let call = makeCall(name: "get_health_log", arguments: """
        {"include":["steps","exercise_minutes"]}
        """)
        let result = await tool.execute(call, agent: agent)

        #expect(!result.isError)
        #expect(result.content.contains("8423"))
        #expect(result.content.contains("42"))
    }

    @Test @MainActor func getHealthLogVitals() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container
        let service = FakeHealthService()
        service.restingHeartRate = 54
        service.heartRateVariability = 68

        let tool = GetHealthLogTool(healthService: service, canPromptUser: true)
        let call = makeCall(name: "get_health_log", arguments: """
        {"include":["resting_heart_rate","hrv"]}
        """)
        let result = await tool.execute(call, agent: agent)

        #expect(!result.isError)
        #expect(result.content.contains("54"))
        #expect(result.content.contains("68"))
    }

    @Test @MainActor func getHealthLogVitalsUnavailable() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container
        let service = FakeHealthService()
        service.restingHeartRate = nil

        let tool = GetHealthLogTool(healthService: service, canPromptUser: true)
        let call = makeCall(name: "get_health_log", arguments: """
        {"include":["resting_heart_rate"]}
        """)
        let result = await tool.execute(call, agent: agent)

        #expect(!result.isError)
        #expect(result.content.contains("No resting heart rate"))
    }

    @Test @MainActor func getHealthLogSleep() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container
        let service = FakeHealthService()
        service.sleep = SleepSummary(
            asleep: 7.5, deep: 1.2, core: 4.3, rem: 2.0, awake: 0.4, inBed: 8.1
        )

        let tool = GetHealthLogTool(healthService: service, canPromptUser: true)
        let call = makeCall(name: "get_health_log", arguments: """
        {"include":["sleep"]}
        """)
        let result = await tool.execute(call, agent: agent)

        #expect(!result.isError)
        #expect(result.content.contains("asleep_hours"))
        #expect(result.content.contains("7.5"))
        #expect(result.content.contains("rem_hours"))
    }

    @Test @MainActor func getHealthLogSleepUnavailable() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container
        let service = FakeHealthService()
        service.sleep = nil

        let tool = GetHealthLogTool(healthService: service, canPromptUser: true)
        let call = makeCall(name: "get_health_log", arguments: """
        {"include":["sleep"]}
        """)
        let result = await tool.execute(call, agent: agent)

        #expect(!result.isError)
        #expect(result.content.contains("No sleep data"))
    }

    @Test @MainActor func getHealthLogWorkouts() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container
        let service = FakeHealthService()
        service.workouts = [
            WorkoutSample(
                type: "Running", start: Date(), duration: 1800,
                activeEnergy: 320, distance: 5000
            ),
        ]

        let tool = GetHealthLogTool(healthService: service, canPromptUser: true)
        let call = makeCall(name: "get_health_log", arguments: """
        {"include":["workouts"]}
        """)
        let result = await tool.execute(call, agent: agent)

        #expect(!result.isError)
        #expect(result.content.contains("Running"))
        #expect(result.content.contains("320"))
    }

    // MARK: - LogBodyMeasurementTool

    @Test @MainActor func logBodyMeasurementSuccess() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container
        let service = FakeHealthService()

        let tool = LogBodyMeasurementTool(healthService: service, canPromptUser: true)
        let call = makeCall(name: "log_body_measurement", arguments: """
        {"weight_kg":79.4}
        """)
        let result = await tool.execute(call, agent: agent)

        #expect(!result.isError)
        #expect(result.content.contains("79.4"))
        #expect(service.loggedWeights.count == 1)
        #expect(service.loggedWeights.first?.kilograms == 79.4)
    }

    @Test @MainActor func logBodyMeasurementMissingWeight() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container
        let service = FakeHealthService()

        let tool = LogBodyMeasurementTool(healthService: service, canPromptUser: true)
        let call = makeCall(name: "log_body_measurement", arguments: "{}")
        let result = await tool.execute(call, agent: agent)

        #expect(result.isError)
        #expect(result.content.contains("weight_kg"))
        #expect(service.loggedWeights.isEmpty)
    }

    @Test @MainActor func logBodyMeasurementAuthDenied() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container
        let service = FakeHealthService()
        service.authResult = .denied("Health access denied.")

        let tool = LogBodyMeasurementTool(healthService: service, canPromptUser: true)
        let call = makeCall(name: "log_body_measurement", arguments: """
        {"weight_kg":79.4}
        """)
        let result = await tool.execute(call, agent: agent)

        #expect(result.isError)
        #expect(result.content.contains("denied"))
        #expect(service.loggedWeights.isEmpty)
    }

    // MARK: - LogSleepTool

    @Test @MainActor func logSleepSuccess() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container
        let service = FakeHealthService()

        let tool = LogSleepTool(healthService: service, canPromptUser: true)
        let call = makeCall(name: "log_sleep", arguments: """
        {"start":"2026-04-12 23:15","end":"2026-04-13 07:00"}
        """)
        let result = await tool.execute(call, agent: agent)

        #expect(!result.isError)
        #expect(result.content.contains("duration_hours"))
        #expect(service.loggedSleep.count == 1)
        #expect(service.loggedSleep.first?
            .start ?? Date() < (service.loggedSleep.first?.end ?? Date()))
    }

    @Test @MainActor func logSleepMissingEnd() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container
        let service = FakeHealthService()

        let tool = LogSleepTool(healthService: service, canPromptUser: true)
        let call = makeCall(name: "log_sleep", arguments: """
        {"start":"2026-04-12 23:15"}
        """)
        let result = await tool.execute(call, agent: agent)

        #expect(result.isError)
        #expect(result.content.contains("end"))
        #expect(service.loggedSleep.isEmpty)
    }

    @Test @MainActor func logSleepEndBeforeStart() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container
        let service = FakeHealthService()

        let tool = LogSleepTool(healthService: service, canPromptUser: true)
        let call = makeCall(name: "log_sleep", arguments: """
        {"start":"2026-04-13 07:00","end":"2026-04-12 23:15"}
        """)
        let result = await tool.execute(call, agent: agent)

        #expect(result.isError)
        #expect(result.content.contains("after"))
        #expect(service.loggedSleep.isEmpty)
    }

    @Test @MainActor func logSleepAuthDenied() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container
        let service = FakeHealthService()
        service.authResult = .denied("Health access denied.")

        let tool = LogSleepTool(healthService: service, canPromptUser: true)
        let call = makeCall(name: "log_sleep", arguments: """
        {"start":"2026-04-12 23:15","end":"2026-04-13 07:00"}
        """)
        let result = await tool.execute(call, agent: agent)

        #expect(result.isError)
        #expect(result.content.contains("denied"))
        #expect(service.loggedSleep.isEmpty)
    }

    // MARK: - SearchFoodTool

    @Test @MainActor func searchFoodReturnsProducts() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container
        let lookup = FakeFoodLookupService()
        lookup.searchResults = [
            FoodProduct(
                barcode: "123", name: "Rolled Oats", brands: ["Bob's"],
                servingSize: "40g", caloriesPer100g: 379, caloriesPerServing: 152,
                proteinPer100g: 13.5, fatPer100g: 6.9, carbsPer100g: 67.7
            ),
            FoodProduct(
                barcode: "456", name: "Greek Yogurt", brands: ["Fage"],
                servingSize: "200g", caloriesPer100g: 97, caloriesPerServing: 194,
                proteinPer100g: 9.0, fatPer100g: 5.0, carbsPer100g: 3.6
            ),
        ]

        let tool = SearchFoodTool(foodLookup: lookup)
        let call = makeCall(name: "search_food", arguments: """
        {"query":"oats","limit":2}
        """)
        let result = await tool.execute(call, agent: agent)

        #expect(!result.isError)
        #expect(result.content.contains("Rolled Oats"))
        #expect(result.content.contains("Greek Yogurt"))
        #expect(result.content.contains("379"))
        #expect(lookup.searchQueries.count == 1)
        #expect(lookup.searchQueries.first?.query == "oats")
        #expect(lookup.searchQueries.first?.limit == 2)
    }

    @Test @MainActor func searchFoodEmptyResults() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container
        let lookup = FakeFoodLookupService()

        let tool = SearchFoodTool(foodLookup: lookup)
        let call = makeCall(name: "search_food", arguments: """
        {"query":"xyznonexistent"}
        """)
        let result = await tool.execute(call, agent: agent)

        #expect(!result.isError)
        #expect(result.content.contains("\"count\":0"))
    }

    @Test @MainActor func searchFoodNetworkError() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container
        let lookup = FakeFoodLookupService()
        lookup.searchError = OpenFoodFactsError.badStatus(503)

        let tool = SearchFoodTool(foodLookup: lookup)
        let call = makeCall(name: "search_food", arguments: """
        {"query":"oats"}
        """)
        let result = await tool.execute(call, agent: agent)

        #expect(result.isError)
        #expect(result.content.contains("503"))
    }

    @Test @MainActor func searchFoodMissingQuery() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container

        let tool = SearchFoodTool()
        let call = makeCall(name: "search_food", arguments: "{}")
        let result = await tool.execute(call, agent: agent)

        #expect(result.isError)
        #expect(result.content.contains("query"))
    }

    @Test @MainActor func searchFoodEmptyQuery() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container

        let tool = SearchFoodTool()
        let call = makeCall(name: "search_food", arguments: """
        {"query":"   "}
        """)
        let result = await tool.execute(call, agent: agent)

        #expect(result.isError)
        #expect(result.content.contains("empty"))
    }

    // MARK: - GetFoodDetailsTool

    @Test @MainActor func getFoodDetailsReturnsProduct() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container
        let lookup = FakeFoodLookupService()
        lookup.productResult = FoodProduct(
            barcode: "5060292302201", name: "Dark Chocolate 85%", brands: ["Lindt"],
            servingSize: "25g", caloriesPer100g: 600, caloriesPerServing: 150,
            proteinPer100g: 10.0, fatPer100g: 46.0, carbsPer100g: 19.0
        )

        let tool = GetFoodDetailsTool(foodLookup: lookup)
        let call = makeCall(name: "get_food_details", arguments: """
        {"barcode":"5060292302201"}
        """)
        let result = await tool.execute(call, agent: agent)

        #expect(!result.isError)
        #expect(result.content.contains("Dark Chocolate 85%"))
        #expect(result.content.contains("Lindt"))
        #expect(result.content.contains("600"))
        #expect(lookup.barcodeQueries == ["5060292302201"])
    }

    @Test @MainActor func getFoodDetailsNotFound() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container
        let lookup = FakeFoodLookupService()
        lookup.productResult = nil

        let tool = GetFoodDetailsTool(foodLookup: lookup)
        let call = makeCall(name: "get_food_details", arguments: """
        {"barcode":"0000000000"}
        """)
        let result = await tool.execute(call, agent: agent)

        #expect(result.isError)
    }

    @Test @MainActor func getFoodDetailsMissingBarcode() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container

        let tool = GetFoodDetailsTool()
        let call = makeCall(name: "get_food_details", arguments: "{}")
        let result = await tool.execute(call, agent: agent)

        #expect(result.isError)
        #expect(result.content.contains("barcode"))
    }
}
