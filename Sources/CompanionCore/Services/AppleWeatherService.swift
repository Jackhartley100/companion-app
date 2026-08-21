import Foundation

#if canImport(WeatherKit) && canImport(CoreLocation) && !os(Linux)
import WeatherKit
import CoreLocation

/// Weather backed by Apple's WeatherKit.
///
/// Requires the WeatherKit capability on the app target (Signing &
/// Capabilities), which needs an Apple Developer account — see the TODO on
/// `UnavailableWeatherService`. Falls back to `.unavailable` at the call site
/// rather than crashing when the entitlement isn't present; WeatherKit itself
/// throws in that case.
public struct AppleWeatherService: WeatherService {
    public init() {}
    public var isAvailable: Bool { true }

    public func currentWeather(at coordinate: Coordinate) async throws -> WeatherSnapshot {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let current = try await WeatherKit.WeatherService.shared.weather(for: location, including: .current)
        return WeatherSnapshot(current)
    }

    public func hourlyForecast(at coordinate: Coordinate, hours: Int) async throws -> [WeatherSnapshot] {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let hourly = try await WeatherKit.WeatherService.shared.weather(for: location, including: .hourly)
        return hourly.prefix(hours).map(WeatherSnapshot.init)
    }
}

private extension WeatherSnapshot {
    init(_ hour: HourWeather) {
        self.init(
            date: hour.date,
            temperatureCelsius: hour.temperature.converted(to: .celsius).value,
            condition: Condition(hour.condition),
            windSpeedKmh: hour.wind.speed.converted(to: .kilometersPerHour).value
        )
    }

    init(_ current: CurrentWeather) {
        self.init(
            date: current.date,
            temperatureCelsius: current.temperature.converted(to: .celsius).value,
            condition: Condition(current.condition),
            windSpeedKmh: current.wind.speed.converted(to: .kilometersPerHour).value
        )
    }
}

private extension WeatherSnapshot.Condition {
    init(_ condition: WeatherKit.WeatherCondition) {
        switch condition {
        case .clear, .mostlyClear, .hot:
            self = .clear
        case .cloudy, .mostlyCloudy, .partlyCloudy:
            self = .cloudy
        case .rain, .drizzle, .heavyRain, .isolatedThunderstorms, .scatteredThunderstorms,
             .strongStorms, .thunderstorms, .sunShowers, .freezingRain,
             .hurricane, .tropicalStorm:
            self = .rain
        case .snow, .flurries, .heavySnow, .blizzard, .blowingSnow, .freezingDrizzle,
             .sleet, .wintryMix, .sunFlurries:
            self = .snow
        case .windy, .breezy:
            self = .wind
        case .foggy, .haze, .smoky:
            self = .fog
        default:
            self = .other
        }
    }
}
#endif
