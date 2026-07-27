import Foundation

/// The distance unit the owner prefers to read distances in.
///
/// Storage is always metric (metres); this preference only affects presentation.
public enum DistanceUnit: String, Codable, Sendable, CaseIterable, Identifiable {
    case kilometres
    case miles

    public var id: String { rawValue }

    public var unit: UnitLength {
        switch self {
        case .kilometres: .kilometers
        case .miles: .miles
        }
    }

    /// The unit used when expressing a short distance (for example GPS accuracy).
    public var shortUnit: UnitLength {
        switch self {
        case .kilometres: .meters
        case .miles: .feet
        }
    }

    public var displayName: String {
        switch self {
        case .kilometres: "Kilometres"
        case .miles: "Miles"
        }
    }

    /// A sensible default for the supplied locale.
    ///
    /// `Locale.measurementSystem` is authoritative where available, so we do not
    /// maintain a hand-written list of country codes.
    public static func `default`(for locale: Locale = .current) -> DistanceUnit {
        locale.measurementSystem == .metric ? .kilometres : .miles
    }
}

/// The weight unit the owner prefers. Storage is always in kilograms.
public enum WeightUnit: String, Codable, Sendable, CaseIterable, Identifiable {
    case kilograms
    case pounds

    public var id: String { rawValue }

    public var unit: UnitMass {
        switch self {
        case .kilograms: .kilograms
        case .pounds: .pounds
        }
    }

    public var displayName: String {
        switch self {
        case .kilograms: "Kilograms"
        case .pounds: "Pounds"
        }
    }

    public static func `default`(for locale: Locale = .current) -> WeightUnit {
        locale.measurementSystem == .metric ? .kilograms : .pounds
    }
}

/// The day a statistics week begins on.
public enum WeekStart: String, Codable, Sendable, CaseIterable, Identifiable {
    case system
    case monday
    case sunday

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .system: "Automatic"
        case .monday: "Monday"
        case .sunday: "Sunday"
        }
    }

    /// Resolves to a `Calendar.firstWeekday` value (1 = Sunday).
    public func firstWeekday(in calendar: Calendar) -> Int {
        switch self {
        case .system: calendar.firstWeekday
        case .sunday: 1
        case .monday: 2
        }
    }
}

/// The app's appearance preference.
public enum AppearancePreference: String, Codable, Sendable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

// MARK: - Conversions

public extension Double {
    /// Interprets the receiver as a distance in metres.
    var metres: Measurement<UnitLength> { Measurement(value: self, unit: .meters) }

    /// Interprets the receiver as a mass in kilograms.
    var kilograms: Measurement<UnitMass> { Measurement(value: self, unit: .kilograms) }
}
