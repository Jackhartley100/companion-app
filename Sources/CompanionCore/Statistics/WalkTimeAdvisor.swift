import Foundation

/// A suggestion for when to walk today, shown on Today alongside the current
/// conditions.
public struct WalkTimeSuggestion: Sendable, Hashable {
    public enum Tone: Sendable, Hashable {
        case good
        case poor
    }

    public let text: String
    public let symbolName: String
    public let tone: Tone

    public init(text: String, symbolName: String, tone: Tone) {
        self.text = text
        self.symbolName = symbolName
        self.tone = tone
    }
}

/// Suggests a time to walk today from the owner's own history and the hourly
/// forecast — never from the dog's health or behaviour, which this has no
/// visibility into.
///
/// The "usual hour" is a plain mode of past start times, not a machine-learned
/// preference; with fewer than `minimumHistory` walks it's dropped entirely
/// rather than asserting a routine from too small a sample.
public struct WalkTimeAdvisor: Sendable {
    public let calendar: Calendar
    public let minimumHistory: Int

    public init(calendar: Calendar = .current, minimumHistory: Int = 5) {
        self.calendar = calendar
        self.minimumHistory = minimumHistory
    }

    /// - Parameters:
    ///   - activities: The dog's walk history, any period.
    ///   - hourlyForecast: Today's remaining hourly forecast, in order.
    public func suggestion(
        activities: [WalkActivity],
        hourlyForecast: [WeatherSnapshot],
        now: Date = Date()
    ) -> WalkTimeSuggestion? {
        guard let restOfToday = restOfToday(hourlyForecast, now: now), !restOfToday.isEmpty else {
            return nil
        }

        let usualHour = usualHour(from: activities)
        let goodHours = restOfToday.filter(\.isGoodForWalking)

        guard let best = closest(to: usualHour, in: goodHours, fallback: restOfToday.first) else {
            return nil
        }

        let timeText = formattedHour(best.date)

        if let usualHour, let usualReading = restOfToday.first(where: { hour($0.date) == usualHour }),
           !usualReading.isGoodForWalking {
            return WalkTimeSuggestion(
                text: "Your usual \(formattedHour(usualReading.date)) walk looks \(usualReading.condition.displayName.lowercased()) — "
                    + "\(timeText) looks better, \(Int(best.temperatureCelsius.rounded()))°C.",
                symbolName: "clock.badge.exclamationmark",
                tone: .poor
            )
        }

        if best.isGoodForWalking {
            let openingText = usualHour == hour(best.date) ? "Good time for your usual walk" : "Good time to walk"
            return WalkTimeSuggestion(
                text: "\(openingText): around \(timeText), \(best.condition.displayName.lowercased()) "
                    + "and \(Int(best.temperatureCelsius.rounded()))°C.",
                symbolName: "checkmark.circle",
                tone: .good
            )
        }

        return WalkTimeSuggestion(
            text: "Weather looks \(best.condition.displayName.lowercased()) for the rest of today — "
                + "\(timeText) is the mildest window left.",
            symbolName: "exclamationmark.triangle",
            tone: .poor
        )
    }

    private func restOfToday(_ hourly: [WeatherSnapshot], now: Date) -> [WeatherSnapshot]? {
        guard !hourly.isEmpty else { return nil }
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        return hourly.filter { $0.date >= now && $0.date < endOfDay }
    }

    private func hour(_ date: Date) -> Int { calendar.component(.hour, from: date) }

    private func usualHour(from activities: [WalkActivity]) -> Int? {
        guard activities.count >= minimumHistory else { return nil }
        let hours = activities.map { hour($0.startDate) }
        let counts = Dictionary(hours.map { ($0, 1) }, uniquingKeysWith: +)
        return counts.max(by: { $0.value < $1.value })?.key
    }

    /// The reading whose hour is nearest `usualHour`, among `candidates`
    /// (falling back to `fallback` when `candidates` is empty or there is no
    /// usual hour to measure against).
    private func closest(
        to usualHour: Int?,
        in candidates: [WeatherSnapshot],
        fallback: WeatherSnapshot?
    ) -> WeatherSnapshot? {
        guard let usualHour, !candidates.isEmpty else { return candidates.first ?? fallback }
        return candidates.min { lhs, rhs in
            abs(hour(lhs.date) - usualHour) < abs(hour(rhs.date) - usualHour)
        }
    }

    private func formattedHour(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "h a"
        return formatter.string(from: date).lowercased()
    }
}
