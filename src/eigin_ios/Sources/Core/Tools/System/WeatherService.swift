import Foundation

// MARK: - Protocol

/// Boundary for weather lookups: current conditions, the rest of today by
/// hour, and a short daily forecast.
protocol WeatherService: Sendable {
    /// Weather for a location. `forecastDays` is the number of daily entries
    /// beyond today (0 = none); hours through the end of today are always
    /// included.
    func weather(
        latitude: Double,
        longitude: Double,
        forecastDays: Int
    ) async -> Result<WeatherSnapshot, WeatherError>
}

// MARK: - Value Types

/// Current conditions plus the near-term forecast for a location.
struct WeatherSnapshot {
    /// Conditions right now.
    let current: CurrentWeather
    /// Hourly entries from now through the end of today.
    let restOfToday: [HourWeather]
    /// Daily entries for the days after today; empty when no forecast asked for.
    let daily: [DayWeather]
}

/// Conditions right now.
struct CurrentWeather {
    /// Short English label, e.g. "Partly Cloudy".
    let condition: String
    let temperatureCelsius: Double
    /// Kilometres per hour.
    let windSpeedKPH: Double
}

/// One hour of forecast weather.
struct HourWeather {
    /// Start of the hour.
    let hour: Date
    /// Short English label, e.g. "Rain".
    let condition: String
    let temperatureCelsius: Double
    /// 0...1
    let precipitationChance: Double
}

/// One day of forecast weather.
struct DayWeather {
    /// Start of the day.
    let date: Date
    /// Short English label, e.g. "Mostly Sunny".
    let condition: String
    let highCelsius: Double
    let lowCelsius: Double
    /// 0...1
    let precipitationChance: Double
}

/// Errors a `WeatherService` can surface.
enum WeatherError: Error, Equatable {
    /// Weather data could not be fetched or was empty.
    case unavailable
    /// The backend rejected the request; carries the underlying reason.
    case failed(String)
}
