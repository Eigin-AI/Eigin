#if DEBUG || EIGIN_DEV
import CoreLocation
import Foundation

final class FakeWeatherService: WeatherService, @unchecked Sendable {
    var snapshot: WeatherSnapshot?
    var error: WeatherError?

    private(set) var calls: [(latitude: Double, longitude: Double, forecastDays: Int)] = []

    func weather(
        latitude: Double,
        longitude: Double,
        forecastDays: Int
    ) async -> Result<WeatherSnapshot, WeatherError> {
        calls.append((latitude: latitude, longitude: longitude, forecastDays: forecastDays))
        if let error { return .failure(error) }
        guard let snapshot else { return .failure(.unavailable) }
        return .success(snapshot)
    }

    // MARK: - Sample Data

    static func sampleSnapshot(
        dailyCount: Int = 1
    ) -> WeatherSnapshot {
        let now = Date()
        let calendar = Calendar.current

        var hours: [HourWeather] = []
        for offset in 0 ..< 4 {
            let hour = HourWeather(
                hour: calendar.date(byAdding: .hour, value: offset, to: now)!,
                condition: offset % 2 == 0 ? "Clear" : "Rain",
                temperatureCelsius: 18 + Double(offset),
                precipitationChance: offset == 1 ? 0.7 : 0.1
            )
            hours.append(hour)
        }

        var days: [DayWeather] = []
        for offset in 1 ... max(dailyCount, 0) {
            let day = DayWeather(
                date: calendar.date(byAdding: .day, value: offset, to: now)!,
                condition: "Partly Cloudy",
                highCelsius: 21,
                lowCelsius: 13,
                precipitationChance: 0.3
            )
            days.append(day)
        }

        let current = CurrentWeather(
            condition: "Partly Cloudy",
            temperatureCelsius: 17.4,
            windSpeedKPH: 12.3
        )

        return WeatherSnapshot(
            current: current,
            restOfToday: hours,
            daily: days
        )
    }
}
#endif
