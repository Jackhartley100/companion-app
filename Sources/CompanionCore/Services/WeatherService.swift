import Foundation

/// A simplified weather reading — just enough to decide whether now (or some
/// other hour today) is a good time for a walk, not a general-purpose weather
/// model.
public struct WeatherSnapshot: Sendable, Hashable {
    public enum Condition: String, Sendable, Hashable {
        case clear
        case cloudy
        case rain
        case snow
        case wind
        case fog
        case other

        public var symbolName: String {
            switch self {
            case .clear: "sun.max.fill"
            case .cloudy: "cloud.fill"
            case .rain: "cloud.rain.fill"
            case .snow: "cloud.snow.fill"
            case .wind: "wind"
            case .fog: "cloud.fog.fill"
            case .other: "cloud.fill"
            }
        }

        public var displayName: String {
            switch self {
            case .clear: "Clear"
            case .cloudy: "Cloudy"
            case .rain: "Rain"
            case .snow: "Snow"
            case .wind: "Windy"
            case .fog: "Foggy"
            case .other: "Mild"
            }
        }
    }

    public let date: Date
    public let temperatureCelsius: Double
    public let condition: Condition
    public let windSpeedKmh: Double

    public init(date: Date, temperatureCelsius: Double, condition: Condition, windSpeedKmh: Double) {
        self.date = date
        self.temperatureCelsius = temperatureCelsius
        self.condition = condition
        self.windSpeedKmh = windSpeedKmh
    }

    /// A blunt, walk-specific judgement rather than a general weather rating —
    /// heavy rain, snow, high wind or extreme temperature all say no; nothing
    /// else does. Deliberately conservative: a false "good" sends someone out
    /// into weather they'd have preferred to know about.
    public var isGoodForWalking: Bool {
        guard temperatureCelsius > -5, temperatureCelsius < 32 else { return false }
        guard windSpeedKmh < 40 else { return false }
        switch condition {
        case .rain, .snow: return false
        case .clear, .cloudy, .wind, .fog, .other: return true
        }
    }
}

public enum WeatherServiceError: Error, Sendable, Equatable {
    case unavailable
    case locationUnavailable
}

/// Weather integration, behind a protocol so the app builds and runs with no
/// weather entitlement, and so Today's nudge and the "best time to walk"
/// suggestion can be previewed with fixed data.
public protocol WeatherService: Sendable {
    var isAvailable: Bool { get }
    func currentWeather(at coordinate: Coordinate) async throws -> WeatherSnapshot
    /// The next `hours` hours from now, one reading per hour, for picking a
    /// good window later today.
    func hourlyForecast(at coordinate: Coordinate, hours: Int) async throws -> [WeatherSnapshot]
}

/// The weather service the MVP ships with when no weather entitlement is
/// configured: reports unavailable and fetches nothing.
///
// TODO: Replace with `AppleWeatherService` once the WeatherKit capability is
// added to the app target in Xcode (Signing & Capabilities → WeatherKit) —
// deliberately not a hard launch requirement, since it needs an Apple
// Developer account entitlement this repo can't grant itself.
public struct UnavailableWeatherService: WeatherService {
    public init() {}
    public var isAvailable: Bool { false }
    public func currentWeather(at coordinate: Coordinate) async throws -> WeatherSnapshot {
        throw WeatherServiceError.unavailable
    }
    public func hourlyForecast(at coordinate: Coordinate, hours: Int) async throws -> [WeatherSnapshot] {
        throw WeatherServiceError.unavailable
    }
}

/// A weather service that returns fixed data. For previews and tests.
public struct StubWeatherService: WeatherService {
    public let current: WeatherSnapshot?
    public let hourly: [WeatherSnapshot]

    public init(current: WeatherSnapshot? = nil, hourly: [WeatherSnapshot] = []) {
        self.current = current
        self.hourly = hourly
    }

    public var isAvailable: Bool { true }

    public func currentWeather(at coordinate: Coordinate) async throws -> WeatherSnapshot {
        guard let current else { throw WeatherServiceError.unavailable }
        return current
    }

    public func hourlyForecast(at coordinate: Coordinate, hours: Int) async throws -> [WeatherSnapshot] {
        Array(hourly.prefix(hours))
    }
}
