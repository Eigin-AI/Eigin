import CoreLocation
import Foundation
@preconcurrency import WeatherKit

/// WeatherKit-backed weather service.
///
/// Requires the WeatherKit capability on the app's App ID in the Apple
/// Developer portal, in addition to the `com.apple.developer.weatherkit`
/// entitlement.
struct AppleWeatherService: WeatherService {
    func weather(
        latitude: Double,
        longitude: Double,
        forecastDays: Int
    ) async -> Result<WeatherSnapshot, WeatherError> {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        let now = Date()

        do {
            // Qualified: WeatherKit exports types matching our value-type names.
            let (current, hourly, daily) = try await WeatherKit.WeatherService.shared
                .weather(for: location, including: .current, .hourly, .daily)
            return .success(
                snapshot(
                    current: current,
                    hourly: hourly,
                    daily: daily,
                    now: now,
                    forecastDays: forecastDays
                )
            )
        } catch {
            // Surface the underlying reason — WeatherKit failures are almost
            // always setup (capability/entitlement), and a generic warning
            // alone hides it.
            return .failure(.failed(error.localizedDescription))
        }
    }

    // MARK: - Mapping

    private func snapshot(
        current: WeatherKit.CurrentWeather,
        hourly: WeatherKit.Forecast<WeatherKit.HourWeather>,
        daily: WeatherKit.Forecast<WeatherKit.DayWeather>,
        now: Date,
        forecastDays: Int
    ) -> WeatherSnapshot {
        // Map to our own value types immediately, then window on plain arrays —
        // keeps the windowing logic pure and testable.
        let hours = hourly.map { hour in
            HourWeather(
                hour: hour.date,
                condition: conditionLabel(hour.condition),
                temperatureCelsius: celsius(hour.temperature),
                precipitationChance: hour.precipitationChance
            )
        }

        let days = daily.map { day in
            DayWeather(
                date: day.date,
                condition: conditionLabel(day.condition),
                highCelsius: celsius(day.highTemperature),
                lowCelsius: celsius(day.lowTemperature),
                precipitationChance: day.precipitationChance
            )
        }

        let calendar = Calendar.current
        return WeatherSnapshot(
            current: CurrentWeather(
                condition: conditionLabel(current.condition),
                temperatureCelsius: celsius(current.temperature),
                windSpeedKPH: kph(current.wind.speed)
            ),
            restOfToday: Self.restOfToday(hours: hours, after: now, calendar: calendar),
            daily: Self.forecast(days: days, after: now, count: forecastDays, calendar: calendar)
        )
    }

    /// Hours from `after` through the end of `after`'s day. The in-progress
    /// hour is kept: its forecast window is mostly ahead, and dropping it would
    /// hide near-term precipitation. Later days are excluded.
    static func restOfToday(
        hours: [HourWeather],
        after now: Date,
        calendar: Calendar = .current
    ) -> [HourWeather] {
        hours.filter { hour in
            calendar.isDate(hour.hour, inSameDayAs: now)
                && hour.hour + hourInterval > now
        }
    }

    /// The first `count` days strictly after `after`'s day. WeatherKit's daily
    /// forecast begins with the current day, so that entry is dropped.
    static func forecast(
        days: [DayWeather],
        after now: Date,
        count: Int,
        calendar: Calendar = .current
    ) -> [DayWeather] {
        Array(days.drop { calendar.isDate($0.date, inSameDayAs: now) }.prefix(count))
    }

    private static let hourInterval: TimeInterval = 60 * 60

    private func celsius(_ temperature: Measurement<UnitTemperature>) -> Double {
        temperature.converted(to: .celsius).value
    }

    private func kph(_ speed: Measurement<UnitSpeed>) -> Double {
        speed.converted(to: .kilometersPerHour).value
    }
}

// MARK: - Labels

/// Short English labels keep agent context deterministic across locales.
func conditionLabel(_ condition: WeatherCondition) -> String {
    switch condition {
    case .clear, .mostlyClear: "Clear"
    case .partlyCloudy: "Partly Cloudy"
    case .mostlyCloudy, .cloudy: "Cloudy"
    case .foggy, .haze: "Fog"
    case .drizzle: "Drizzle"
    case .rain, .heavyRain: "Rain"
    case .sunShowers: "Sun Showers"
    case .sleet, .wintryMix: "Sleet"
    case .snow, .heavySnow, .blowingSnow: "Snow"
    case .sunFlurries: "Snow Flurries"
    case .blizzard, .blowingDust: "Blizzard"
    case .frigid: "Frigid"
    case .hot: "Hot"
    case .breezy, .windy: "Windy"
    case .isolatedThunderstorms, .scatteredThunderstorms, .thunderstorms: "Thunderstorms"
    case .strongStorms, .hurricane, .tropicalStorm: "Storm"
    case .hail: "Hail"
    @unknown default: "Unknown"
    }
}
