@testable import Eigin
import Foundation
import SwiftData
import Testing

@Suite("Weather Tools", .serialized)
struct WeatherToolTests {
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

    /// A resolver that never touches CoreLocation.
    private static func fixedLocation(
        _ location: ResolvedLocation? = ResolvedLocation(
            name: "Fuengirola", latitude: 36.54, longitude: -4.62
        )
    ) -> @Sendable (Bool) async -> Result<ResolvedLocation, LocationError> {
        { _ in
            if let location { return .success(location) }
            return .failure(.noFix)
        }
    }

    /// Thread-safe call counter for resolver closures.
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0

        func increment() {
            lock.lock()
            count += 1
            lock.unlock()
        }

        var value: Int {
            lock.lock()
            defer { lock.unlock() }
            return count
        }
    }

    // MARK: - Current + Forecast

    @Test @MainActor func returnsCurrentAndForecast() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container
        let weather = FakeWeatherService()
        weather.snapshot = FakeWeatherService.sampleSnapshot(dailyCount: 2)

        let tool = GetWeatherTool(weather: weather, resolveLocation: Self.fixedLocation())
        let call = makeCall(name: "get_weather", arguments: """
        {"forecast_days":2}
        """)
        let result = await tool.execute(call, agent: agent)

        #expect(!result.isError)
        #expect(result.content.contains("Partly Cloudy"))
        #expect(result.content.contains("Fuengirola"))
        #expect(result.content.contains("rest_of_today"))
        #expect(result.content.contains("forecast"))

        #expect(weather.calls.count == 1)
        #expect(weather.calls.first?.latitude == 36.54)
        #expect(weather.calls.first?.longitude == -4.62)
        #expect(weather.calls.first?.forecastDays == 2)

        // The snapshot passes through: 4 hours and 2 forecast days.
        let json = try #require(JSONSerialization
            .jsonObject(with: Data(result.content.utf8)) as? [String: Any])
        let payload = try #require(json["result"] as? [String: Any])
        #expect((payload["rest_of_today"] as? [[String: Any]])?.count == 4)
        #expect((payload["forecast"] as? [[String: Any]])?.count == 2)
    }

    @Test @MainActor func defaultsToOneForecastDay() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container
        let weather = FakeWeatherService()
        weather.snapshot = FakeWeatherService.sampleSnapshot(dailyCount: 1)

        let tool = GetWeatherTool(weather: weather, resolveLocation: Self.fixedLocation())
        let call = makeCall(name: "get_weather", arguments: "{}")
        let result = await tool.execute(call, agent: agent)

        #expect(!result.isError)
        #expect(weather.calls.first?.forecastDays == 1)
    }

    @Test @MainActor func clampsForecastDaysToValidRange() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container
        let weather = FakeWeatherService()
        weather.snapshot = FakeWeatherService.sampleSnapshot()

        let tool = GetWeatherTool(weather: weather, resolveLocation: Self.fixedLocation())

        let high = await tool.execute(
            makeCall(name: "get_weather", arguments: #"{"forecast_days":99}"#), agent: agent
        )
        #expect(!high.isError)
        #expect(weather.calls.last?.forecastDays == 10)

        let negative = await tool.execute(
            makeCall(name: "get_weather", arguments: #"{"forecast_days":-3}"#), agent: agent
        )
        #expect(!negative.isError)
        #expect(weather.calls.last?.forecastDays == 0)
    }

    // MARK: - Compact Output

    @Test @MainActor func outputIsCompact() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container
        let weather = FakeWeatherService()
        weather.snapshot = FakeWeatherService.sampleSnapshot(dailyCount: 1)

        let tool = GetWeatherTool(weather: weather, resolveLocation: Self.fixedLocation())
        let result = await tool.execute(
            makeCall(name: "get_weather", arguments: "{}"), agent: agent
        )

        #expect(!result.isError)
        #expect(result.content.contains("temperature_c"))
        #expect(result.content.contains("wind_kph"))
        #expect(result.content.contains("precip_chance"))
        #expect(result.content.contains("high_c"))
        #expect(result.content.contains("low_c"))
        // Essentials only — no feels-like, humidity, or daytime flag.
        #expect(!result.content.contains("feels_like"))
        #expect(!result.content.contains("humidity"))
        #expect(!result.content.contains("is_daytime"))
    }

    // MARK: - Coordinates

    @Test @MainActor func usesGivenCoordinatesWithoutResolvingLocation() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container
        let weather = FakeWeatherService()
        weather.snapshot = FakeWeatherService.sampleSnapshot()

        let resolverCalls = Counter()
        let tool = GetWeatherTool(
            weather: weather,
            resolveLocation: { _ in
                resolverCalls.increment()
                return .failure(.noFix)
            }
        )
        let result = await tool.execute(
            makeCall(
                name: "get_weather",
                arguments: #"{"latitude":55.6761,"longitude":12.5683}"#
            ),
            agent: agent
        )

        #expect(!result.isError)
        #expect(resolverCalls.value == 0)
        #expect(weather.calls.first?.latitude == 55.6761)
        #expect(weather.calls.first?.longitude == 12.5683)
        // No reverse-geocoded name for given coordinates
        #expect(!result.content.contains("location"))
    }

    @Test @MainActor func partialCoordinatesReturnError() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container
        let weather = FakeWeatherService()
        weather.snapshot = FakeWeatherService.sampleSnapshot()

        let tool = GetWeatherTool(weather: weather, resolveLocation: Self.fixedLocation())
        let result = await tool.execute(
            makeCall(name: "get_weather", arguments: #"{"latitude":55.6761}"#), agent: agent
        )

        #expect(result.isError)
        #expect(result.content.contains("both latitude and longitude"))
        // No weather call and no location fallback for a partial request.
        #expect(weather.calls.isEmpty)
    }

    @Test @MainActor func missingLocationReturnsError() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container
        let weather = FakeWeatherService()
        weather.snapshot = FakeWeatherService.sampleSnapshot()

        let tool = GetWeatherTool(weather: weather, resolveLocation: Self.fixedLocation(nil))
        let result = await tool.execute(
            makeCall(name: "get_weather", arguments: "{}"), agent: agent
        )

        #expect(result.isError)
        #expect(result.content.contains("Could not determine current location."))
        #expect(weather.calls.isEmpty)
    }

    // MARK: - Errors

    @Test @MainActor func unavailableWeatherIsWarningNotError() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container
        let weather = FakeWeatherService()
        weather.error = .unavailable

        let tool = GetWeatherTool(weather: weather, resolveLocation: Self.fixedLocation())
        let result = await tool.execute(
            makeCall(name: "get_weather", arguments: "{}"), agent: agent
        )

        #expect(!result.isError)
        #expect(result.content.contains("isn't available"))
    }

    @Test @MainActor func backendFailureSurfacesReason() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container
        let weather = FakeWeatherService()
        weather.error = .failed("WeatherKit is not entitled")

        let tool = GetWeatherTool(weather: weather, resolveLocation: Self.fixedLocation())
        let result = await tool.execute(
            makeCall(name: "get_weather", arguments: "{}"), agent: agent
        )

        #expect(!result.isError)
        #expect(result.content.contains("Reason: WeatherKit is not entitled"))
    }

    @Test @MainActor func invalidJSONArgumentsIsError() async throws {
        let (agent, _container) = try makeAgent()
        _ = _container
        let tool = GetWeatherTool(
            weather: FakeWeatherService(), resolveLocation: Self.fixedLocation()
        )
        let result = await tool.execute(
            makeCall(name: "get_weather", arguments: "not json"), agent: agent
        )

        #expect(result.isError)
        #expect(result.content.contains("Invalid JSON"))
    }
}
