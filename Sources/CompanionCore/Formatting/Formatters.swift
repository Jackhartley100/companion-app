import Foundation

/// Turns stored base-unit values into text for display and for VoiceOver.
///
/// All formatting is locale-aware and goes through `Measurement` and
/// `Date.FormatStyle` rather than string concatenation, so decimal separators,
/// unit abbreviations and date order follow the device's settings.
///
/// Two variants exist for most values: a compact one for on-screen metrics, and
/// a spelled-out one for accessibility, because VoiceOver reading "3.4 km" as
/// "three point four kay em" is worse than "3.4 kilometres".
public struct Formatters: Sendable {
    public let distanceUnit: DistanceUnit
    public let weightUnit: WeightUnit
    public let locale: Locale

    public init(
        distanceUnit: DistanceUnit = .default(),
        weightUnit: WeightUnit = .default(),
        locale: Locale = .current
    ) {
        self.distanceUnit = distanceUnit
        self.weightUnit = weightUnit
        self.locale = locale
    }

    // MARK: - Distance

    /// A distance in metres, shown in the owner's preferred unit.
    ///
    /// Distances under a kilometre are shown in metres (or feet) because "0.2 km"
    /// reads as less informative than "180 m" on a short walk.
    public func distance(_ metres: Double, style: Measurement<UnitLength>.FormatStyle.UnitWidth = .abbreviated) -> String {
        let measurement = Measurement(value: metres, unit: UnitLength.meters)
        let useShortUnit = metres < 1_000 && distanceUnit == .kilometres
            || (distanceUnit == .miles && metres < 160.9)

        if useShortUnit {
            return measurement.converted(to: distanceUnit.shortUnit).formatted(
                .measurement(width: style, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0)))
                .locale(locale)
            )
        }
        return measurement.converted(to: distanceUnit.unit).formatted(
            .measurement(
                width: style,
                usage: .asProvided,
                numberFormatStyle: .number.precision(.fractionLength(metres >= 10_000 ? 1 : 2))
            ).locale(locale)
        )
    }

    public func accessibleDistance(_ metres: Double) -> String {
        distance(metres, style: .wide)
    }

    /// The unit label alone, e.g. "km", for metric cards that show the number
    /// large and the unit small.
    public var distanceUnitLabel: String {
        distanceUnit == .kilometres ? "km" : "mi"
    }

    /// The numeric part of a distance, without a unit.
    public func distanceValue(_ metres: Double) -> String {
        let converted = Measurement(value: metres, unit: UnitLength.meters)
            .converted(to: distanceUnit.unit).value
        return converted.formatted(
            .number.precision(.fractionLength(converted >= 100 ? 1 : 2)).locale(locale)
        )
    }

    // MARK: - Duration

    /// Compact duration: `8:42` under an hour, `1:08:42` above.
    public func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    /// Duration in words, e.g. "1 hour 8 minutes". Used for VoiceOver and for
    /// sentences in insight cards.
    public func spelledDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60

        var components: [String] = []
        if hours > 0 {
            components.append("\(hours) \(hours == 1 ? "hour" : "hours")")
        }
        if minutes > 0 || hours == 0 {
            components.append("\(minutes) \(minutes == 1 ? "minute" : "minutes")")
        }
        return components.joined(separator: " ")
    }

    // MARK: - Pace and speed

    /// Pace as minutes and seconds per kilometre or mile, e.g. `12:30 /km`.
    /// Returns `nil` when there is no meaningful movement to describe.
    public func pace(secondsPerMetre: Double?) -> String? {
        guard let secondsPerMetre, secondsPerMetre > 0, secondsPerMetre.isFinite else { return nil }
        let metresPerUnit = distanceUnit == .kilometres ? 1_000.0 : 1_609.344
        let secondsPerUnit = secondsPerMetre * metresPerUnit
        // Above about 100 minutes per unit the number is meaningless — the owner
        // is standing still, not walking very slowly.
        guard secondsPerUnit < 6_000 else { return nil }
        let minutes = Int(secondsPerUnit) / 60
        let seconds = Int(secondsPerUnit) % 60
        return String(format: "%d:%02d /%@", minutes, seconds, distanceUnitLabel)
    }

    public func pace(metresPerSecond: Double?) -> String? {
        guard let metresPerSecond, metresPerSecond > 0 else { return nil }
        return pace(secondsPerMetre: 1 / metresPerSecond)
    }

    /// Speed, e.g. `4.8 km/h`.
    public func speed(metresPerSecond: Double?) -> String? {
        guard let metresPerSecond, metresPerSecond >= 0, metresPerSecond.isFinite else { return nil }
        let unit: UnitSpeed = distanceUnit == .kilometres ? .kilometersPerHour : .milesPerHour
        return Measurement(value: metresPerSecond, unit: UnitSpeed.metersPerSecond)
            .converted(to: unit)
            .formatted(
                .measurement(
                    width: .abbreviated,
                    usage: .asProvided,
                    numberFormatStyle: .number.precision(.fractionLength(1))
                ).locale(locale)
            )
    }

    /// Whichever of pace or speed reads more naturally for the activity type.
    public func rate(metresPerSecond: Double?, activityType: ActivityType) -> String? {
        activityType.prefersPaceOverSpeed
            ? pace(metresPerSecond: metresPerSecond)
            : speed(metresPerSecond: metresPerSecond)
    }

    // MARK: - Weight

    public func weight(kilograms: Double) -> String {
        Measurement(value: kilograms, unit: UnitMass.kilograms)
            .converted(to: weightUnit.unit)
            .formatted(
                .measurement(
                    width: .abbreviated,
                    usage: .asProvided,
                    numberFormatStyle: .number.precision(.fractionLength(1))
                ).locale(locale)
            )
    }

    // MARK: - Dates

    public func dateTime(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()
            .locale(locale))
    }

    public func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute().locale(locale))
    }

    public func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).locale(locale))
    }

    public func monthAndYear(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).year().locale(locale))
    }

    /// "Today", "Yesterday" or a date, whichever is clearest.
    public func relativeDay(_ date: Date, calendar: Calendar = .current, now: Date = Date()) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if let week = calendar.date(byAdding: .day, value: -7, to: now), date > week {
            return date.formatted(.dateTime.weekday(.wide).locale(locale))
        }
        return shortDate(date)
    }

    // MARK: - Dog age

    /// Age in words, phrased so an estimate never looks like a known birthday.
    public func age(_ age: DogAge, asOf date: Date = Date(), calendar: Calendar = .current) -> String? {
        guard let months = age.months(asOf: date, calendar: calendar) else { return nil }
        let text: String = if months < 24 {
            "\(months) \(months == 1 ? "month" : "months")"
        } else {
            "\(months / 12) \(months / 12 == 1 ? "year" : "years")"
        }
        return age.isEstimate ? "About \(text)" : text
    }
}
