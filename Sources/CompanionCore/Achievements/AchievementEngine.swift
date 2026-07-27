import Foundation

/// Everything the achievement rules are evaluated against.
public struct AchievementContext: Sendable {
    /// Every saved activity, newest first or otherwise — order is not relied on.
    public let activities: [WalkActivity]
    public let goalProgress: [GoalProgress]
    public let streak: Streak
    /// Restricts evaluation to one dog's history, when set.
    public let dogID: UUID?

    public init(
        activities: [WalkActivity],
        goalProgress: [GoalProgress] = [],
        streak: Streak = .none,
        dogID: UUID? = nil
    ) {
        self.activities = activities
        self.goalProgress = goalProgress
        self.streak = streak
        self.dogID = dogID
    }
}

/// Decides which achievements are earned.
///
/// Rules are evaluated here and nowhere else — no view unlocks an achievement as
/// a side effect of being displayed. The engine is pure: it reports what *should*
/// be unlocked, and the caller persists the difference.
public struct AchievementEngine: Sendable {
    public let definitions: [AchievementDefinition]
    public let calendar: Calendar

    public init(
        definitions: [AchievementDefinition] = AchievementCatalog.all,
        calendar: Calendar = .current
    ) {
        self.definitions = definitions
        self.calendar = calendar
    }

    /// Achievements satisfied by `context` that are not already in `existing`.
    ///
    /// - Returns: New unlocks, ready to persist. Empty when nothing was earned.
    public func newUnlocks(
        context: AchievementContext,
        existing: [AchievementUnlock],
        triggeringWalk: WalkActivity? = nil,
        now: Date = Date()
    ) -> [AchievementUnlock] {
        let alreadyUnlocked = Set(existing.map(\.achievementID))
        return definitions.compactMap { definition in
            guard !alreadyUnlocked.contains(definition.id) else { return nil }
            guard isSatisfied(definition.rule, context: context) else { return nil }
            return AchievementUnlock(
                achievementID: definition.id,
                dogID: context.dogID,
                walkID: triggeringWalk?.id,
                unlockedAt: now,
                acknowledged: false
            )
        }
    }

    /// Every achievement with its unlock state and, where meaningful, progress.
    public func statuses(
        context: AchievementContext,
        existing: [AchievementUnlock]
    ) -> [AchievementStatus] {
        let unlocksByID = Dictionary(
            existing.map { ($0.achievementID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return definitions.map { definition in
            AchievementStatus(
                definition: definition,
                unlock: unlocksByID[definition.id],
                progress: progress(for: definition.rule, context: context)
            )
        }
    }

    // MARK: - Rule evaluation

    func isSatisfied(_ rule: AchievementRule, context: AchievementContext) -> Bool {
        let activities = context.activities
        switch rule {
        case .totalActivities(let count):
            return activities.count >= count

        case .singleWalkDistance(let metres):
            return activities.contains { $0.distance >= metres }

        case .cumulativeDistance(let metres):
            return activities.reduce(0) { $0 + $1.distance } >= metres

        case .streak(let days):
            return context.streak.best >= days

        case .startedBetweenHours(let from, let to):
            return activities.contains { activity in
                let hour = calendar.component(.hour, from: activity.startDate)
                return hour >= from && hour < to
            }

        case .weekendActivity:
            return activities.contains { activity in
                calendar.isDateInWeekend(activity.startDate)
            }

        case .goalCompleted(let period):
            return context.goalProgress.contains { $0.goal.period == period && $0.isComplete }
        }
    }

    /// 0...1 towards a rule, for rules where a partial value is meaningful.
    /// Returns `nil` for all-or-nothing rules, where a progress bar would be noise.
    func progress(for rule: AchievementRule, context: AchievementContext) -> Double? {
        switch rule {
        case .totalActivities(let count):
            guard count > 0 else { return nil }
            return min(1, Double(context.activities.count) / Double(count))

        case .cumulativeDistance(let metres):
            guard metres > 0 else { return nil }
            let total = context.activities.reduce(0) { $0 + $1.distance }
            return min(1, total / metres)

        case .streak(let days):
            guard days > 0 else { return nil }
            return min(1, Double(max(context.streak.current, context.streak.best)) / Double(days))

        case .singleWalkDistance(let metres):
            guard metres > 0, let best = context.activities.map(\.distance).max() else { return nil }
            return min(1, best / metres)

        case .startedBetweenHours, .weekendActivity, .goalCompleted:
            return nil
        }
    }
}
