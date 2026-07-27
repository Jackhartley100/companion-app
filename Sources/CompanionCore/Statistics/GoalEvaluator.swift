import Foundation

/// Works out how far through their goals a dog is.
public struct GoalEvaluator: Sendable {
    public let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    /// The half-open period a goal is currently being measured over.
    public func currentPeriod(for goal: Goal, containing date: Date = Date()) -> (start: Date, end: Date) {
        switch goal.period {
        case .daily:
            let start = calendar.startOfDay(for: date)
            return (start, calendar.date(byAdding: .day, value: 1, to: start) ?? date)
        case .weekly:
            let start = calendar.startOfWeek(for: date)
            return (start, calendar.date(byAdding: .day, value: 7, to: start) ?? date)
        }
    }

    public func progress(
        for goal: Goal,
        activities: [WalkActivity],
        asOf date: Date = Date()
    ) -> GoalProgress {
        let period = currentPeriod(for: goal, containing: date)
        // A goal with no dog counts every walk; a dog-specific goal counts only
        // walks that dog came on.
        let relevant = activities.filter { activity in
            guard activity.startDate >= period.start, activity.startDate < period.end else {
                return false
            }
            guard let dogID = goal.dogID else { return true }
            return activity.dogIDs.contains(dogID)
        }

        let value: Double = switch goal.goalType {
        case .distance:
            relevant.reduce(0) { $0 + $1.distance }
        case .duration:
            relevant.reduce(0) { $0 + $1.movingDuration }
        case .walkCount:
            Double(relevant.count)
        case .activeDays:
            Double(Set(relevant.map { calendar.startOfDay(for: $0.startDate) }).count)
        }

        return GoalProgress(
            goal: goal,
            currentValue: value,
            periodStart: period.start,
            periodEnd: period.end
        )
    }

    public func progress(
        for goals: [Goal],
        activities: [WalkActivity],
        asOf date: Date = Date()
    ) -> [GoalProgress] {
        goals.map { progress(for: $0, activities: activities, asOf: date) }
    }
}
