import Foundation

/// The achievements the app ships with.
///
/// Identifiers are permanent: they are written into `AchievementUnlock` records
/// on the owner's device, so renaming one would silently orphan every unlock.
/// Titles and descriptions can change freely.
///
/// Achievements are grouped into families — walks, distance, streaks — each
/// running bronze through platinum, so the trophy case reads as a set of
/// progressions rather than a shelf of unrelated stickers. Time-of-day,
/// weekend and goal achievements are one-off badges rather than families:
/// there is no honest way to make "walked before 7am" progressively harder.
public enum AchievementCatalog {
    public static let all: [AchievementDefinition] = [
        // MARK: Walks together
        AchievementDefinition(
            id: "first_walk",
            title: "First Walk",
            details: "You recorded your first walk together.",
            symbolName: "figure.walk",
            rule: .totalActivities(count: 1),
            tier: .bronze,
            category: .walks
        ),
        AchievementDefinition(
            id: "ten_activities",
            title: "Ten Walks",
            details: "Ten walks recorded. A routine is forming.",
            symbolName: "10.circle.fill",
            rule: .totalActivities(count: 10),
            tier: .silver,
            category: .walks
        ),
        AchievementDefinition(
            id: "fifty_activities",
            title: "Fifty Walks",
            details: "Fifty walks recorded together.",
            symbolName: "50.circle.fill",
            rule: .totalActivities(count: 50),
            tier: .gold,
            category: .walks
        ),
        AchievementDefinition(
            id: "two_hundred_fifty_activities",
            title: "250 Walks",
            details: "Two hundred and fifty walks. This is a way of life.",
            symbolName: "seal.fill",
            rule: .totalActivities(count: 250),
            tier: .platinum,
            category: .walks
        ),

        // MARK: Distance
        AchievementDefinition(
            id: "first_five_km",
            title: "First 5 km",
            details: "A single walk of five kilometres or more.",
            symbolName: "flag.checkered",
            rule: .singleWalkDistance(metres: 5_000),
            tier: .bronze,
            category: .distance
        ),
        AchievementDefinition(
            id: "first_ten_km",
            title: "First 10 km",
            details: "A single walk of ten kilometres or more.",
            symbolName: "mountain.2.fill",
            rule: .singleWalkDistance(metres: 10_000),
            tier: .silver,
            category: .distance
        ),
        AchievementDefinition(
            id: "hundred_km_total",
            title: "100 km Together",
            details: "One hundred kilometres walked side by side.",
            symbolName: "road.lanes",
            rule: .cumulativeDistance(metres: 100_000),
            tier: .gold,
            category: .distance
        ),
        AchievementDefinition(
            id: "five_hundred_km_total",
            title: "500 km Together",
            details: "Five hundred kilometres. Roughly Land's End to John o' Groats.",
            symbolName: "globe.europe.africa.fill",
            rule: .cumulativeDistance(metres: 500_000),
            tier: .platinum,
            category: .distance
        ),

        // MARK: Streaks
        AchievementDefinition(
            id: "streak_three",
            title: "Three-Day Streak",
            details: "Walks on three days in a row.",
            symbolName: "flame.fill",
            rule: .streak(days: 3),
            tier: .bronze,
            category: .streaks
        ),
        AchievementDefinition(
            id: "streak_seven",
            title: "Seven-Day Streak",
            details: "A full week of daily walks.",
            symbolName: "flame.circle.fill",
            rule: .streak(days: 7),
            tier: .silver,
            category: .streaks
        ),
        AchievementDefinition(
            id: "streak_thirty",
            title: "Thirty-Day Streak",
            details: "Thirty days in a row. Remarkable consistency.",
            symbolName: "crown.fill",
            rule: .streak(days: 30),
            tier: .gold,
            category: .streaks
        ),
        AchievementDefinition(
            id: "streak_hundred",
            title: "Hundred-Day Streak",
            details: "A hundred days in a row. Genuinely rare.",
            symbolName: "trophy.fill",
            rule: .streak(days: 100),
            tier: .platinum,
            category: .streaks
        ),

        // MARK: Time of day (single tier — see the type's own note)
        AchievementDefinition(
            id: "early_bird",
            title: "Early Bird",
            details: "A walk started before 7am.",
            symbolName: "sunrise.fill",
            rule: .startedBetweenHours(from: 4, to: 7),
            tier: .bronze,
            category: .timing
        ),
        AchievementDefinition(
            id: "evening_explorer",
            title: "Evening Explorer",
            details: "A walk started after 8pm.",
            symbolName: "moon.stars.fill",
            rule: .startedBetweenHours(from: 20, to: 24),
            tier: .bronze,
            category: .timing
        ),
        AchievementDefinition(
            id: "weekend_adventurer",
            title: "Weekend Adventurer",
            details: "A walk on a Saturday or Sunday.",
            symbolName: "sparkles",
            rule: .weekendActivity,
            tier: .bronze,
            category: .timing
        ),

        // MARK: Goals
        AchievementDefinition(
            id: "weekly_goal",
            title: "Weekly Goal Complete",
            details: "A weekly goal reached in full.",
            symbolName: "target",
            rule: .goalCompleted(period: .weekly),
            tier: .bronze,
            category: .goals
        )
    ]

    private static let index: [String: AchievementDefinition] = Dictionary(
        uniqueKeysWithValues: all.map { ($0.id, $0) }
    )

    public static func definition(id: String) -> AchievementDefinition? {
        index[id]
    }
}
