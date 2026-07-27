import Testing
import Foundation
@testable import CompanionCore

private let ownerID = UUID()
private let dogA = UUID()
private let dogB = UUID()

/// A calendar pinned to UTC with Monday weeks, so these tests give the same
/// answer wherever they run.
private var testCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    calendar.firstWeekday = 2
    return calendar
}

/// Monday 2 February 2026, 00:00 UTC.
private let monday = testCalendar.date(from: DateComponents(year: 2026, month: 2, day: 2))!

private func activity(
    dayOffset: Int,
    hour: Int = 9,
    distance: Double = 2_000,
    duration: TimeInterval = 1_800,
    dogs: [UUID] = [dogA],
    type: ActivityType = .walk
) -> WalkActivity {
    let start = testCalendar.date(byAdding: .day, value: dayOffset, to: monday)!
        .addingTimeInterval(TimeInterval(hour) * 3_600)
    return WalkActivity(
        title: "Walk",
        activityType: type,
        startDate: start,
        endDate: start.addingTimeInterval(duration),
        elapsedDuration: duration,
        movingDuration: duration,
        distance: distance,
        dogIDs: dogs,
        ownerID: ownerID
    )
}

@Suite("Statistics aggregation")
struct StatisticsEngineTests {
    let engine = StatisticsEngine(calendar: testCalendar)

    @Test("Daily totals cover every day in the range, including empty ones")
    func dailyTotalsHaveNoGaps() {
        let activities = [activity(dayOffset: 0), activity(dayOffset: 3)]
        let days = engine.dailyTotals(
            for: activities,
            from: monday,
            to: testCalendar.date(byAdding: .day, value: 7, to: monday)!
        )
        #expect(days.count == 7)
        #expect(days[0].walkCount == 1)
        #expect(days[1].walkCount == 0)
        #expect(days[3].walkCount == 1)
    }

    @Test("Two walks on the same day are summed into one bucket")
    func sameDayWalksCombine() {
        let activities = [
            activity(dayOffset: 0, hour: 8, distance: 1_500),
            activity(dayOffset: 0, hour: 18, distance: 2_500)
        ]
        let days = engine.dailyTotals(
            for: activities,
            from: monday,
            to: testCalendar.date(byAdding: .day, value: 1, to: monday)!
        )
        #expect(days.count == 1)
        #expect(days[0].walkCount == 2)
        #expect(days[0].distance == 4_000)
    }

    @Test("Weekly statistics total the right walks and count active days")
    func weeklyStatistics() {
        let activities = [
            activity(dayOffset: 0, distance: 2_000, duration: 1_800),
            activity(dayOffset: 0, hour: 18, distance: 1_000, duration: 900),
            activity(dayOffset: 2, distance: 3_000, duration: 2_400),
            activity(dayOffset: 5, distance: 5_000, duration: 3_600),
            // Next week — must be excluded.
            activity(dayOffset: 8, distance: 9_999)
        ]
        let stats = engine.statistics(for: activities, period: .week, containing: monday)

        #expect(stats.walkCount == 4)
        #expect(stats.totalDistance == 11_000)
        #expect(stats.totalDuration == 8_700)
        #expect(stats.activeDayCount == 3)
        #expect(stats.longestWalk?.distance == 5_000)
        #expect(stats.days.count == 7)
    }

    @Test("The period boundary is half-open so a walk is never double-counted")
    func periodBoundaryIsHalfOpen() {
        let nextMonday = testCalendar.date(byAdding: .day, value: 7, to: monday)!
        let boundaryWalk = WalkActivity(
            title: "Boundary",
            startDate: nextMonday,
            endDate: nextMonday.addingTimeInterval(600),
            elapsedDuration: 600,
            movingDuration: 600,
            distance: 1_000,
            dogIDs: [dogA],
            ownerID: ownerID
        )
        let thisWeek = engine.statistics(for: [boundaryWalk], period: .week, containing: monday)
        let nextWeek = engine.statistics(for: [boundaryWalk], period: .week, containing: nextMonday)
        #expect(thisWeek.walkCount == 0)
        #expect(nextWeek.walkCount == 1)
    }

    @Test("Statistics for a period with no walks are empty rather than absent")
    func emptyPeriodStillHasDays() {
        let stats = engine.statistics(for: [], period: .week, containing: monday)
        #expect(stats.walkCount == 0)
        #expect(stats.totalDistance == 0)
        #expect(stats.days.count == 7)
        #expect(stats.hasData == false)
        #expect(stats.averageDistancePerWalk == nil)
    }

    @Test("Averages divide by walk count, not by day count")
    func averagesUseWalkCount() {
        let activities = [
            activity(dayOffset: 0, distance: 2_000, duration: 1_200),
            activity(dayOffset: 1, distance: 4_000, duration: 2_400)
        ]
        let stats = engine.statistics(for: activities, period: .week, containing: monday)
        #expect(stats.averageDistancePerWalk == 3_000)
        #expect(stats.averageDurationPerWalk == 1_800)
    }

    @Test("Monthly statistics span the whole calendar month")
    func monthlyStatistics() {
        let activities = (0..<28).map { activity(dayOffset: $0, distance: 1_000) }
        let stats = engine.statistics(for: activities, period: .month, containing: monday)
        // February 2026 has 28 days; walks on days 2–28 of it fall in range.
        #expect(stats.days.count == 28)
        #expect(stats.walkCount == 27)
    }

    @Test("Today's totals cover only today")
    func todayTotals() {
        let activities = [
            activity(dayOffset: 0, hour: 8, distance: 1_500),
            activity(dayOffset: 0, hour: 20, distance: 2_500),
            activity(dayOffset: 1, distance: 9_999)
        ]
        let today = engine.today(for: activities, date: monday.addingTimeInterval(12 * 3_600))
        #expect(today.walkCount == 2)
        #expect(today.distance == 4_000)
    }

    @Test("Most active weekday is withheld until there is enough data")
    func mostActiveWeekdayNeedsEnoughData() {
        let few = [activity(dayOffset: 0), activity(dayOffset: 1)]
        #expect(engine.mostActiveWeekday(for: few) == nil)
    }

    @Test("Most active weekday finds the day with the greatest distance")
    func mostActiveWeekday() {
        var activities = (0..<6).map { activity(dayOffset: $0, distance: 1_000) }
        activities.append(activity(dayOffset: 5, distance: 20_000)) // Saturday
        let best = engine.mostActiveWeekday(for: activities)
        #expect(best != nil)
        // Day offset 5 from Monday is Saturday; Calendar weekday 7.
        #expect(best?.weekday == 7)
    }

    @Test("Week boundaries follow the owner's week-start preference")
    func weekStartPreferenceChangesBoundaries() {
        let mondayCalendar = StatisticsEngine.calendar(for: .monday, base: testCalendar)
        let sundayCalendar = StatisticsEngine.calendar(for: .sunday, base: testCalendar)

        let sundayBefore = testCalendar.date(byAdding: .day, value: -1, to: monday)!
        let walk = WalkActivity(
            title: "Sunday",
            startDate: sundayBefore.addingTimeInterval(10 * 3_600),
            endDate: sundayBefore.addingTimeInterval(11 * 3_600),
            elapsedDuration: 3_600,
            movingDuration: 3_600,
            distance: 3_000,
            dogIDs: [dogA],
            ownerID: ownerID
        )

        // With Monday weeks that Sunday belongs to the previous week...
        #expect(
            StatisticsEngine(calendar: mondayCalendar)
                .statistics(for: [walk], period: .week, containing: monday).walkCount == 0
        )
        // ...with Sunday weeks it belongs to this one.
        #expect(
            StatisticsEngine(calendar: sundayCalendar)
                .statistics(for: [walk], period: .week, containing: monday).walkCount == 1
        )
    }
}

@Suite("Streaks")
struct StreakTests {
    let calculator = StreakCalculator(calendar: testCalendar)

    @Test("No activities means no streak")
    func emptyStreak() {
        #expect(calculator.streak(for: [], asOf: monday) == .none)
    }

    @Test("Consecutive days build a streak")
    func consecutiveDays() {
        let activities = (0..<4).map { activity(dayOffset: -$0) }
        let streak = calculator.streak(for: activities, asOf: monday.addingTimeInterval(12 * 3_600))
        #expect(streak.current == 4)
        #expect(streak.best == 4)
    }

    /// The product decision that a streak is not lost until a whole day passes.
    @Test("A streak survives a today that has not been walked yet")
    func todayNotYetWalked() {
        let activities = (1...3).map { activity(dayOffset: -$0) }
        let streak = calculator.streak(for: activities, asOf: monday.addingTimeInterval(8 * 3_600))
        #expect(streak.current == 3)
    }

    @Test("A streak ends once a full day has been missed")
    func missedDayBreaksStreak() {
        let activities = (2...5).map { activity(dayOffset: -$0) }
        let streak = calculator.streak(for: activities, asOf: monday.addingTimeInterval(8 * 3_600))
        #expect(streak.current == 0)
        #expect(streak.best == 4)
    }

    @Test("Best streak is remembered after it is broken")
    func bestStreakRemembered() {
        var activities = (10...16).map { activity(dayOffset: -$0) } // 7 in a row
        activities += [activity(dayOffset: -1), activity(dayOffset: 0)] // 2 in a row now
        let streak = calculator.streak(for: activities, asOf: monday.addingTimeInterval(12 * 3_600))
        #expect(streak.current == 2)
        #expect(streak.best == 7)
    }

    @Test("Several walks on one day count as one day of streak")
    func multipleWalksOneDay() {
        let activities = [
            activity(dayOffset: 0, hour: 7),
            activity(dayOffset: 0, hour: 13),
            activity(dayOffset: 0, hour: 20)
        ]
        let streak = calculator.streak(for: activities, asOf: monday.addingTimeInterval(21 * 3_600))
        #expect(streak.current == 1)
        #expect(streak.best == 1)
    }
}

@Suite("Goal progress")
struct GoalTests {
    let evaluator = GoalEvaluator(calendar: testCalendar)

    @Test("A weekly distance goal sums the week's walks")
    func weeklyDistanceProgress() {
        let goal = Goal(dogID: dogA, goalType: .distance, targetValue: 20_000, period: .weekly)
        let activities = [
            activity(dayOffset: 0, distance: 5_000),
            activity(dayOffset: 2, distance: 3_000),
            activity(dayOffset: 9, distance: 9_999) // next week
        ]
        let progress = evaluator.progress(
            for: goal, activities: activities, asOf: monday.addingTimeInterval(3 * 86_400)
        )
        #expect(progress.currentValue == 8_000)
        #expect(progress.remaining == 12_000)
        #expect(abs(progress.fraction - 0.4) < 0.001)
        #expect(progress.isComplete == false)
    }

    @Test("Only the goal's own dog counts towards a dog-specific goal")
    func dogSpecificGoalFiltersByDog() {
        let goal = Goal(dogID: dogA, goalType: .distance, targetValue: 10_000, period: .weekly)
        let activities = [
            activity(dayOffset: 0, distance: 3_000, dogs: [dogA]),
            activity(dayOffset: 1, distance: 4_000, dogs: [dogB])
        ]
        let progress = evaluator.progress(for: goal, activities: activities, asOf: monday)
        #expect(progress.currentValue == 3_000)
    }

    @Test("A walk with two dogs counts towards both dogs' goals")
    func sharedWalkCountsForBothDogs() {
        let activities = [activity(dayOffset: 0, distance: 4_000, dogs: [dogA, dogB])]
        let goalA = Goal(dogID: dogA, goalType: .distance, targetValue: 10_000, period: .weekly)
        let goalB = Goal(dogID: dogB, goalType: .distance, targetValue: 10_000, period: .weekly)
        #expect(evaluator.progress(for: goalA, activities: activities, asOf: monday).currentValue == 4_000)
        #expect(evaluator.progress(for: goalB, activities: activities, asOf: monday).currentValue == 4_000)
    }

    @Test("A goal with no dog counts every walk")
    func householdGoalCountsEverything() {
        let goal = Goal(dogID: nil, goalType: .walkCount, targetValue: 5, period: .weekly)
        let activities = [
            activity(dayOffset: 0, dogs: [dogA]),
            activity(dayOffset: 1, dogs: [dogB])
        ]
        #expect(evaluator.progress(for: goal, activities: activities, asOf: monday).currentValue == 2)
    }

    @Test("Active-days goals count distinct days, not walks")
    func activeDaysCountsDays() {
        let goal = Goal(dogID: dogA, goalType: .activeDays, targetValue: 5, period: .weekly)
        let activities = [
            activity(dayOffset: 0, hour: 8),
            activity(dayOffset: 0, hour: 18),
            activity(dayOffset: 1)
        ]
        #expect(evaluator.progress(for: goal, activities: activities, asOf: monday).currentValue == 2)
    }

    @Test("Duration goals sum moving time")
    func durationGoal() {
        let goal = Goal(dogID: dogA, goalType: .duration, targetValue: 7_200, period: .weekly)
        let activities = [
            activity(dayOffset: 0, duration: 1_800),
            activity(dayOffset: 1, duration: 2_700)
        ]
        let progress = evaluator.progress(for: goal, activities: activities, asOf: monday)
        #expect(progress.currentValue == 4_500)
    }

    @Test("Exceeding a goal reports complete and does not overflow the ring")
    func exceedingGoalClamps() {
        let goal = Goal(dogID: dogA, goalType: .distance, targetValue: 5_000, period: .weekly)
        let activities = [activity(dayOffset: 0, distance: 12_000)]
        let progress = evaluator.progress(for: goal, activities: activities, asOf: monday)
        #expect(progress.isComplete)
        #expect(progress.fraction == 1.0)
        #expect(progress.remaining == 0)
    }

    @Test("A daily goal only counts today")
    func dailyGoalPeriod() {
        let goal = Goal(dogID: dogA, goalType: .distance, targetValue: 3_000, period: .daily)
        let activities = [
            activity(dayOffset: 0, distance: 2_000),
            activity(dayOffset: 1, distance: 5_000)
        ]
        let progress = evaluator.progress(
            for: goal, activities: activities, asOf: monday.addingTimeInterval(12 * 3_600)
        )
        #expect(progress.currentValue == 2_000)
    }

    @Test("Suggested targets scale with the dog's activity level")
    func suggestedTargetsScale() {
        let relaxed = Goal.suggestedTarget(for: .distance, activityLevel: .relaxed, period: .weekly)
        let moderate = Goal.suggestedTarget(for: .distance, activityLevel: .moderate, period: .weekly)
        let veryActive = Goal.suggestedTarget(for: .distance, activityLevel: .veryActive, period: .weekly)
        #expect(relaxed < moderate)
        #expect(moderate < veryActive)
        #expect(relaxed > 0)
    }

    @Test("Suggested active-day targets never exceed a week")
    func activeDayTargetCapped() {
        let target = Goal.suggestedTarget(
            for: .activeDays, activityLevel: .veryActive, period: .weekly
        )
        #expect(target <= 7)
    }
}
