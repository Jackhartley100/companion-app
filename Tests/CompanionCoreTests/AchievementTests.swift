import Testing
import Foundation
@testable import CompanionCore

private let ownerID = UUID()
private let dogID = UUID()

private var testCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    calendar.firstWeekday = 2
    return calendar
}

/// Monday 2 February 2026.
private let monday = testCalendar.date(from: DateComponents(year: 2026, month: 2, day: 2))!

private func activity(
    dayOffset: Int = 0,
    hour: Int = 9,
    distance: Double = 2_000
) -> WalkActivity {
    let start = testCalendar.date(byAdding: .day, value: dayOffset, to: monday)!
        .addingTimeInterval(TimeInterval(hour) * 3_600)
    return WalkActivity(
        title: "Walk",
        startDate: start,
        endDate: start.addingTimeInterval(1_800),
        elapsedDuration: 1_800,
        movingDuration: 1_800,
        distance: distance,
        dogIDs: [dogID],
        ownerID: ownerID
    )
}

@Suite("Achievements")
struct AchievementTests {
    let engine = AchievementEngine(calendar: testCalendar)

    @Test("The first saved walk unlocks First Walk")
    func firstWalk() {
        let unlocks = engine.newUnlocks(
            context: AchievementContext(activities: [activity()], dogID: dogID),
            existing: []
        )
        #expect(unlocks.contains { $0.achievementID == "first_walk" })
    }

    @Test("Nothing unlocks from an empty history")
    func emptyHistoryUnlocksNothing() {
        let unlocks = engine.newUnlocks(context: AchievementContext(activities: []), existing: [])
        #expect(unlocks.isEmpty)
    }

    @Test("An already-earned achievement is not unlocked twice")
    func noDuplicateUnlocks() {
        let existing = [AchievementUnlock(achievementID: "first_walk", dogID: dogID)]
        let unlocks = engine.newUnlocks(
            context: AchievementContext(activities: [activity()], dogID: dogID),
            existing: existing
        )
        #expect(unlocks.contains { $0.achievementID == "first_walk" } == false)
    }

    @Test("A single long walk unlocks the distance milestone")
    func singleWalkDistance() {
        let unlocks = engine.newUnlocks(
            context: AchievementContext(activities: [activity(distance: 5_400)], dogID: dogID),
            existing: []
        )
        #expect(unlocks.contains { $0.achievementID == "first_five_km" })
        #expect(unlocks.contains { $0.achievementID == "first_ten_km" } == false)
    }

    @Test("Cumulative distance accumulates across many short walks")
    func cumulativeDistance() {
        let activities = (0..<50).map { activity(dayOffset: -$0, distance: 2_100) }
        let unlocks = engine.newUnlocks(
            context: AchievementContext(activities: activities, dogID: dogID),
            existing: []
        )
        #expect(unlocks.contains { $0.achievementID == "hundred_km_total" })
    }

    @Test("Streak achievements use the best streak, not just the current one")
    func streakAchievement() {
        let unlocks = engine.newUnlocks(
            context: AchievementContext(
                activities: [activity()],
                streak: Streak(current: 0, best: 7, lastActiveDay: monday),
                dogID: dogID
            ),
            existing: []
        )
        #expect(unlocks.contains { $0.achievementID == "streak_three" })
        #expect(unlocks.contains { $0.achievementID == "streak_seven" })
        #expect(unlocks.contains { $0.achievementID == "streak_thirty" } == false)
    }

    @Test("An early start unlocks Early Bird")
    func earlyBird() {
        let unlocks = engine.newUnlocks(
            context: AchievementContext(activities: [activity(hour: 6)], dogID: dogID),
            existing: []
        )
        #expect(unlocks.contains { $0.achievementID == "early_bird" })
        #expect(unlocks.contains { $0.achievementID == "evening_explorer" } == false)
    }

    @Test("A late start unlocks Evening Explorer")
    func eveningExplorer() {
        let unlocks = engine.newUnlocks(
            context: AchievementContext(activities: [activity(hour: 21)], dogID: dogID),
            existing: []
        )
        #expect(unlocks.contains { $0.achievementID == "evening_explorer" })
    }

    @Test("A weekday walk does not unlock Weekend Adventurer")
    func weekendOnly() {
        // dayOffset 0 is a Monday.
        let weekday = engine.newUnlocks(
            context: AchievementContext(activities: [activity(dayOffset: 0)], dogID: dogID),
            existing: []
        )
        #expect(weekday.contains { $0.achievementID == "weekend_adventurer" } == false)

        // dayOffset 5 is a Saturday.
        let weekend = engine.newUnlocks(
            context: AchievementContext(activities: [activity(dayOffset: 5)], dogID: dogID),
            existing: []
        )
        #expect(weekend.contains { $0.achievementID == "weekend_adventurer" })
    }

    @Test("Completing a weekly goal unlocks the goal achievement")
    func goalAchievement() {
        let goal = Goal(dogID: dogID, goalType: .distance, targetValue: 1_000, period: .weekly)
        let progress = GoalProgress(
            goal: goal,
            currentValue: 1_500,
            periodStart: monday,
            periodEnd: monday.addingTimeInterval(7 * 86_400)
        )
        let unlocks = engine.newUnlocks(
            context: AchievementContext(
                activities: [activity()], goalProgress: [progress], dogID: dogID
            ),
            existing: []
        )
        #expect(unlocks.contains { $0.achievementID == "weekly_goal" })
    }

    @Test("An unlock records which walk earned it")
    func unlockRecordsTriggeringWalk() {
        let walk = activity()
        let unlocks = engine.newUnlocks(
            context: AchievementContext(activities: [walk], dogID: dogID),
            existing: [],
            triggeringWalk: walk
        )
        #expect(unlocks.allSatisfy { $0.walkID == walk.id })
        #expect(unlocks.allSatisfy { $0.dogID == dogID })
        #expect(unlocks.allSatisfy { $0.acknowledged == false })
    }

    @Test("Statuses report every achievement with its unlock state")
    func statuses() {
        let existing = [AchievementUnlock(achievementID: "first_walk", dogID: dogID)]
        let statuses = engine.statuses(
            context: AchievementContext(activities: [activity()], dogID: dogID),
            existing: existing
        )
        #expect(statuses.count == AchievementCatalog.all.count)
        #expect(statuses.first { $0.id == "first_walk" }?.isUnlocked == true)
        #expect(statuses.first { $0.id == "streak_seven" }?.isUnlocked == false)
    }

    @Test("Progress is reported for countable rules and withheld for all-or-nothing ones")
    func progressReporting() {
        let activities = (0..<5).map { activity(dayOffset: -$0) }
        let statuses = engine.statuses(
            context: AchievementContext(activities: activities, dogID: dogID),
            existing: []
        )
        let tenWalks = statuses.first { $0.id == "ten_activities" }
        #expect(tenWalks?.progress == 0.5)

        // "Did a walk start before 7am" has no meaningful halfway point.
        #expect(statuses.first { $0.id == "early_bird" }?.progress == nil)
    }

    @Test("Every catalogue identifier is unique")
    func catalogueIdentifiersUnique() {
        let ids = AchievementCatalog.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("Every catalogue entry is retrievable by its identifier")
    func catalogueLookup() {
        for definition in AchievementCatalog.all {
            #expect(AchievementCatalog.definition(id: definition.id)?.title == definition.title)
        }
        #expect(AchievementCatalog.definition(id: "not_a_real_achievement") == nil)
    }
}

@Suite("Route privacy")
struct RoutePrivacyTests {
    @Test("Sharing trims the start and finish of a route")
    func trimsEndpoints() {
        let route = SyntheticRoute.line(metres: 2_000, pointCount: 200)
        let trimmed = RoutePrivacy.trimmingEndpoints(route, radius: 200)

        #expect(trimmed.count < route.count)
        #expect(trimmed.isEmpty == false)

        let start = route[0].coordinate
        let end = route[route.count - 1].coordinate
        // Nothing within the hidden radius of either end survives.
        #expect(trimmed.allSatisfy { start.distance(to: $0.coordinate) >= 200 })
        #expect(trimmed.allSatisfy { end.distance(to: $0.coordinate) >= 200 })
    }

    /// A short walk around the block cannot be shared as a map without giving
    /// away the address it started from, so nothing is returned.
    @Test("A route shorter than the hidden radius yields nothing to share")
    func shortRouteIsNotShareable() {
        let route = SyntheticRoute.line(metres: 150, pointCount: 30)
        #expect(RoutePrivacy.trimmingEndpoints(route, radius: 200).isEmpty)
        #expect(RoutePrivacy.canShareMap(route, radius: 200) == false)
    }

    @Test("A long route remains shareable after trimming")
    func longRouteIsShareable() {
        let route = SyntheticRoute.line(metres: 3_000, pointCount: 300)
        #expect(RoutePrivacy.canShareMap(route, radius: 200))
    }

    @Test("Trimming a degenerate route returns nothing rather than crashing")
    func degenerateRoutes() {
        #expect(RoutePrivacy.trimmingEndpoints([], radius: 200).isEmpty)
        #expect(RoutePrivacy.trimmingEndpoints(SyntheticRoute.line(pointCount: 1)).isEmpty)
    }
}
