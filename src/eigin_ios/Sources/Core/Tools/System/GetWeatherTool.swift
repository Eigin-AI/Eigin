import CoreLocation
import Foundation

struct GetWeatherTool: Tool {
    static let capability = ToolCapability(
        kind: .builtIn, key: "get_weather",
        displayName: Localized.Tools.System.weather,
        defaultPermissionLevel: .always, category: .timeAndPlace
    )

    let name = "get_weather"
    var isSmallContext: Bool = false
    let weather: any WeatherService
    var displayName: String {
        Self.capability.displayName
    }

    var capabilities: [ToolCapability] {
        [Self.capability]
    }

    var category: ToolCapability.Category {
        .timeAndPlace
    }

    var defaultPermissionLevel: ToolPermissionLevel {
        .always
    }

    /// Whether the tool may trigger a location permission prompt (false during live calls).
    let canPromptUser: Bool

    /// Resolves the current location. Injectable for tests.
    let resolveLocation: @Sendable (Bool) async -> Result<
        ResolvedLocation, LocationError
    >

    init(
        weather: any WeatherService = AppleWeatherService(),
        canPromptUser: Bool = true,
        resolveLocation: @escaping @Sendable (Bool) async -> Result<
            ResolvedLocation, LocationError
        > = { await LocationResolver.resolve(canPromptUser: $0) }
    ) {
        self.weather = weather
        self.canPromptUser = canPromptUser
        self.resolveLocation = resolveLocation
    }

    func definition() -> ToolDefinition {
        ToolDefinition(
            name: name,
            description: """
            Get weather for a location: current conditions, the rest of today by \
            hour, and a short daily forecast. Omit coordinates to use the user's \
            current location (get the user's coordinates with get_time_and_place, \
            or another spot's with search_places). Pass forecast_days for a longer \
            outlook.
            """,
            parameters: JSONSchema(
                type: "object",
                properties: [
                    "latitude": .init(
                        type: "number",
                        description: "Optional latitude. Omit to use the current location."
                    ),
                    "longitude": .init(
                        type: "number",
                        description: "Optional longitude. Omit to use the current location."
                    ),
                    "forecast_days": .init(
                        type: "integer",
                        description: "Days of daily forecast beyond today, 0–10 (default 1)."
                    ),
                ]
            )
        )
    }

    @MainActor func execute(_ toolCall: ToolCall, agent: Agent) async -> ToolResult {
        let id = toolCall.id

        guard let args = ToolHelpers.parseArguments(toolCall.function.arguments) else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["Invalid JSON arguments."]),
                isError: true
            )
        }

        let forecastDays = Self.clampForecastDays(args["forecast_days"])

        let latitude = args["latitude"] as? Double
        let longitude = args["longitude"] as? Double

        // Partial coordinates are a model mistake — fail loudly rather than
        // silently answering for the wrong place.
        switch (latitude, longitude) {
        case (let latitude?, let longitude?):
            let location = ResolvedLocation(
                name: nil, latitude: latitude, longitude: longitude
            )
            return await Self.weatherResult(
                at: location, forecastDays: forecastDays, toolCallID: id, service: weather
            )
        case (nil, nil):
            let resolved = await resolveLocation(canPromptUser)
            switch resolved {
            case .success(let location):
                return await Self.weatherResult(
                    at: location, forecastDays: forecastDays, toolCallID: id, service: weather
                )
            case .failure(let error):
                // No location means no weather — report as an error.
                return ToolResult(
                    toolCallID: id,
                    content: ToolHelpers.output(errors: [LocationResolver.message(for: error)]),
                    isError: true
                )
            }
        default:
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(
                    errors: ["Provide both latitude and longitude, or neither."]
                ),
                isError: true
            )
        }
    }

    /// Fetches weather for a resolved location and formats the result.
    private static func weatherResult(
        at location: ResolvedLocation,
        forecastDays: Int,
        toolCallID id: String,
        service: any WeatherService
    ) async -> ToolResult {
        let result = await service.weather(
            latitude: location.latitude,
            longitude: location.longitude,
            forecastDays: forecastDays
        )

        switch result {
        case .success(let snapshot):
            var output: [String: Any] = [
                "latitude": location.latitude,
                "longitude": location.longitude,
                "current": currentDict(snapshot.current),
                "rest_of_today": snapshot.restOfToday.map(hourDict),
                "forecast": snapshot.daily.map(dayDict),
            ]
            if let name = location.name, !name.isEmpty { output["location"] = name }

            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(result: output),
                isError: false
            )

        case .failure(let error):
            var message = "Weather data isn't available for this location."
            if case .failed(let reason) = error { message += " Reason: \(reason)" }
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(warnings: [message]),
                isError: false
            )
        }
    }

    // MARK: - Helpers

    private static func clampForecastDays(_ value: Any?) -> Int {
        guard let days = value as? Int else { return 1 }
        return min(max(days, 0), 10)
    }

    private static func currentDict(_ current: CurrentWeather) -> [String: Any] {
        [
            "condition": current.condition,
            "temperature_c": round(current.temperatureCelsius),
            "wind_kph": round(current.windSpeedKPH),
        ]
    }

    private static func hourDict(_ hour: HourWeather) -> [String: Any] {
        [
            "hour": timeString(hour.hour),
            "condition": hour.condition,
            "temperature_c": round(hour.temperatureCelsius),
            "precip_chance": round(hour.precipitationChance * 100),
        ]
    }

    private static func dayDict(_ day: DayWeather) -> [String: Any] {
        [
            "date": dayString(day.date),
            "condition": day.condition,
            "high_c": round(day.highCelsius),
            "low_c": round(day.lowCelsius),
            "precip_chance": round(day.precipitationChance * 100),
        ]
    }

    private static func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private static func dayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: date)
    }
}
