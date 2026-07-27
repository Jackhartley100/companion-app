import Foundation

public struct Streak: Sendable, Hashable {
    /// Consecutive active days ending today or yesterday.
    public let current: Int
    /// The longest run of consecutive active days ever recorded.
    public let best: Int
    /// The last day with at least one walk, if there is one.
    public let lastActiveDay: Date?

    public init(current: Int, best: Int, lastActiveDay: Date?) {
        self.current = current
        self.best = best
        self.lastActiveDay = lastActiveDay
    }

    public static let none = Streak(current: 0, best: 0, lastActiveDay: nil)
}

/// Counts consecutive days on which at least one walk was recorded.
///
/// ## Why yesterday still counts
///
/// A streak is broken only once a whole day has passed with no walk. If the
/// owner walked yesterday but has not yet walked today, the streak is still
/// live — today is not over. Ending the streak at midnight would mean the app
/// tells someone at 8am that they have "lost" something they still have all day
/// to keep, which is exactly the guilt-driven pattern the product avoids.
public struct StreakCalculator: Sendable {
    public let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func streak(for activities: [WalkActivity], asOf now: Date = Date()) -> Streak {
        guard !activities.isEmpty else { return .none }

        let activeDays = Set(activities.map { calendar.startOfDay(for: $0.startDate) })
        guard !activeDays.isEmpty else { return .none }

        let sorted = activeDays.sorted()
        let today = calendar.startOfDay(for: now)

        // Best streak: walk the sorted unique days and count consecutive runs.
        var best = 1
        var run = 1
        for index in 1..<max(1, sorted.count) where sorted.count > 1 {
            let gap = calendar.dayCount(from: sorted[index - 1], to: sorted[index])
            if gap == 1 {
                run += 1
                best = max(best, run)
            } else {
                run = 1
            }
        }

        // Current streak: count backwards from today, tolerating an unwalked today.
        var current = 0
        var cursor = today
        if !activeDays.contains(today) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
                  activeDays.contains(yesterday) else {
                return Streak(current: 0, best: best, lastActiveDay: sorted.last)
            }
            cursor = yesterday
        }
        while activeDays.contains(cursor) {
            current += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }

        return Streak(current: current, best: max(best, current), lastActiveDay: sorted.last)
    }
}
