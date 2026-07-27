import Foundation

/// One day's totals. The unit of every chart in the app.
public struct DailyTotals: Sendable, Hashable, Identifiable {
    /// Start of the day in the calendar the totals were computed with.
    public let date: Date
    /// Metres.
    public let distance: Double
    /// Seconds of moving time.
    public let duration: TimeInterval
    public let walkCount: Int

    public var id: Date { date }
    public var isActive: Bool { walkCount > 0 }

    public init(date: Date, distance: Double = 0, duration: TimeInterval = 0, walkCount: Int = 0) {
        self.date = date
        self.distance = distance
        self.duration = duration
        self.walkCount = walkCount
    }
}

/// Aggregated numbers for a period, ready for the statistics screen.
public struct PeriodStatistics: Sendable, Hashable {
    public let start: Date
    /// Exclusive.
    public let end: Date
    /// One entry per calendar day in the period, including days with no walks,
    /// so charts have a continuous axis rather than gaps.
    public let days: [DailyTotals]
    public let totalDistance: Double
    public let totalDuration: TimeInterval
    public let walkCount: Int
    public let activeDayCount: Int
    public let longestWalk: WalkActivity?

    public init(
        start: Date,
        end: Date,
        days: [DailyTotals],
        totalDistance: Double,
        totalDuration: TimeInterval,
        walkCount: Int,
        activeDayCount: Int,
        longestWalk: WalkActivity?
    ) {
        self.start = start
        self.end = end
        self.days = days
        self.totalDistance = totalDistance
        self.totalDuration = totalDuration
        self.walkCount = walkCount
        self.activeDayCount = activeDayCount
        self.longestWalk = longestWalk
    }

    public var averageDistancePerWalk: Double? {
        walkCount > 0 ? totalDistance / Double(walkCount) : nil
    }

    public var averageDurationPerWalk: TimeInterval? {
        walkCount > 0 ? totalDuration / Double(walkCount) : nil
    }

    public var hasData: Bool { walkCount > 0 }

    public static func empty(start: Date, end: Date) -> PeriodStatistics {
        PeriodStatistics(
            start: start, end: end, days: [], totalDistance: 0,
            totalDuration: 0, walkCount: 0, activeDayCount: 0, longestWalk: nil
        )
    }
}

/// The ranges the statistics screen offers.
public enum StatisticsPeriod: String, Sendable, CaseIterable, Identifiable {
    case week
    case month
    case threeMonths

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .week: "This week"
        case .month: "This month"
        case .threeMonths: "Last 3 months"
        }
    }

    /// Resolves to a concrete half-open date range containing `date`.
    public func range(containing date: Date, calendar: Calendar) -> (start: Date, end: Date) {
        switch self {
        case .week:
            let start = calendar.startOfWeek(for: date)
            return (start, calendar.date(byAdding: .day, value: 7, to: start) ?? date)
        case .month:
            let start = calendar.startOfMonth(for: date)
            return (start, calendar.date(byAdding: .month, value: 1, to: start) ?? date)
        case .threeMonths:
            let end = calendar.date(
                byAdding: .day, value: 1, to: calendar.startOfDay(for: date)
            ) ?? date
            let start = calendar.date(byAdding: .month, value: -3, to: end) ?? date
            return (calendar.startOfDay(for: start), end)
        }
    }
}

/// Aggregates saved activities into the numbers the app displays.
///
/// Every function is pure and takes its `Calendar` explicitly: week boundaries
/// depend on the owner's week-start preference and their locale, and a hidden
/// dependency on `Calendar.current` makes that untestable.
public struct StatisticsEngine: Sendable {
    public let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    /// Builds a calendar with the owner's week-start preference applied.
    public static func calendar(for weekStart: WeekStart, base: Calendar = .current) -> Calendar {
        var calendar = base
        calendar.firstWeekday = weekStart.firstWeekday(in: base)
        return calendar
    }

    /// Totals per day across the half-open range `start..<end`.
    ///
    /// Days with no activity are present with zero totals so charts do not have
    /// to invent them and cannot silently drop them.
    public func dailyTotals(
        for activities: [WalkActivity],
        from start: Date,
        to end: Date
    ) -> [DailyTotals] {
        var buckets: [Date: (distance: Double, duration: TimeInterval, count: Int)] = [:]
        for activity in activities where activity.startDate >= start && activity.startDate < end {
            let day = calendar.startOfDay(for: activity.startDate)
            var bucket = buckets[day] ?? (0, 0, 0)
            bucket.distance += activity.distance
            bucket.duration += activity.movingDuration
            bucket.count += 1
            buckets[day] = bucket
        }

        var results: [DailyTotals] = []
        var cursor = calendar.startOfDay(for: start)
        let limit = calendar.startOfDay(for: end)
        while cursor < limit {
            let bucket = buckets[cursor] ?? (0, 0, 0)
            results.append(
                DailyTotals(
                    date: cursor,
                    distance: bucket.distance,
                    duration: bucket.duration,
                    walkCount: bucket.count
                )
            )
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor), next > cursor else {
                break
            }
            cursor = next
        }
        return results
    }

    public func statistics(
        for activities: [WalkActivity],
        from start: Date,
        to end: Date
    ) -> PeriodStatistics {
        let inRange = activities.filter { $0.startDate >= start && $0.startDate < end }
        let days = dailyTotals(for: inRange, from: start, to: end)
        return PeriodStatistics(
            start: start,
            end: end,
            days: days,
            totalDistance: inRange.reduce(0) { $0 + $1.distance },
            totalDuration: inRange.reduce(0) { $0 + $1.movingDuration },
            walkCount: inRange.count,
            activeDayCount: days.count(where: \.isActive),
            longestWalk: inRange.max { $0.distance < $1.distance }
        )
    }

    public func statistics(
        for activities: [WalkActivity],
        period: StatisticsPeriod,
        containing date: Date = Date()
    ) -> PeriodStatistics {
        let range = period.range(containing: date, calendar: calendar)
        return statistics(for: activities, from: range.start, to: range.end)
    }

    /// Totals for the calendar day containing `date`.
    public func today(for activities: [WalkActivity], date: Date = Date()) -> DailyTotals {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? date
        return dailyTotals(for: activities, from: start, to: end).first
            ?? DailyTotals(date: start)
    }

    /// The weekday that has the highest total distance across `activities`.
    /// Returns `nil` until there is enough data for the claim to mean anything.
    public func mostActiveWeekday(
        for activities: [WalkActivity],
        minimumWalks: Int = 5
    ) -> (weekday: Int, distance: Double)? {
        guard activities.count >= minimumWalks else { return nil }
        var totals: [Int: Double] = [:]
        for activity in activities {
            let weekday = calendar.component(.weekday, from: activity.startDate)
            totals[weekday, default: 0] += activity.distance
        }
        guard let best = totals.max(by: { $0.value < $1.value }), best.value > 0 else { return nil }
        return (best.key, best.value)
    }
}

// MARK: - Calendar helpers

public extension Calendar {
    /// Start of the week containing `date`, honouring `firstWeekday`.
    func startOfWeek(for date: Date) -> Date {
        let components = dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return self.date(from: components) ?? startOfDay(for: date)
    }

    func startOfMonth(for date: Date) -> Date {
        let components = dateComponents([.year, .month], from: date)
        return self.date(from: components) ?? startOfDay(for: date)
    }

    /// Number of whole days from `start` to `end`, ignoring time of day.
    func dayCount(from start: Date, to end: Date) -> Int {
        dateComponents([.day], from: startOfDay(for: start), to: startOfDay(for: end)).day ?? 0
    }
}
