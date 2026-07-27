import Foundation

/// The achievements the app ships with.
///
/// Identifiers are permanent: they are written into `AchievementUnlock` records
/// on the owner's device, so renaming one would silently orphan every unlock.
/// Titles and descriptions can change freely.
public enum AchievementCatalog {
    public static let all: [AchievementDefinition] = [
        AchievementDefinition(
            id: "first_walk",
            title: "First Walk",
            details: "You recorded your first walk together.",
            symbolName: "figure.walk",
            rule: .totalActivities(count: 1)
        ),
        AchievementDefinition(
            id: "ten_activities",
            title: "Ten Walks",
            details: "Ten walks recorded. A routine is forming.",
            symbolName: "10.circle.fill",
            rule: .totalActivities(count: 10)
        ),
        AchievementDefinition(
            id: "fifty_activities",
            title: "Fifty Walks",
            details: "Fifty walks recorded together.",
            symbolName: "50.circle.fill",
            rule: .totalActivities(count: 50)
        ),
        AchievementDefinition(
            id: "first_five_km",
            title: "First 5 km",
            details: "A single walk of five kilometres or more.",
            symbolName: "flag.checkered",
            rule: .singleWalkDistance(metres: 5_000)
        ),
        AchievementDefinition(
            id: "first_ten_km",
            title: "First 10 km",
            details: "A single walk of ten kilometres or more.",
            symbolName: "mountain.2.fill",
            rule: .singleWalkDistance(metres: 10_000)
        ),
        AchievementDefinition(
            id: "hundred_km_total",
            title: "100 km Together",
            details: "One hundred kilometres walked side by side.",
            symbolName: "road.lanes",
            rule: .cumulativeDistance(metres: 100_000)
        ),
        AchievementDefinition(
            id: "streak_three",
            title: "Three-Day Streak",
            details: "Walks on three days in a row.",
            symbolName: "flame.fill",
            rule: .streak(days: 3)
        ),
        AchievementDefinition(
            id: "streak_seven",
            title: "Seven-Day Streak",
            details: "A full week of daily walks.",
            symbolName: "flame.circle.fill",
            rule: .streak(days: 7)
        ),
        AchievementDefinition(
            id: "streak_thirty",
            title: "Thirty-Day Streak",
            details: "Thirty days in a row. Remarkable consistency.",
            symbolName: "crown.fill",
            rule: .streak(days: 30)
        ),
        AchievementDefinition(
            id: "early_bird",
            title: "Early Bird",
            details: "A walk started before 7am.",
            symbolName: "sunrise.fill",
            rule: .startedBetweenHours(from: 4, to: 7)
        ),
        AchievementDefinition(
            id: "evening_explorer",
            title: "Evening Explorer",
            details: "A walk started after 8pm.",
            symbolName: "moon.stars.fill",
            rule: .startedBetweenHours(from: 20, to: 24)
        ),
        AchievementDefinition(
            id: "weekend_adventurer",
            title: "Weekend Adventurer",
            details: "A walk on a Saturday or Sunday.",
            symbolName: "sparkles",
            rule: .weekendActivity
        ),
        AchievementDefinition(
            id: "weekly_goal",
            title: "Weekly Goal Complete",
            details: "A weekly goal reached in full.",
            symbolName: "target",
            rule: .goalCompleted(period: .weekly)
        )
    ]

    private static let index: [String: AchievementDefinition] = Dictionary(
        uniqueKeysWithValues: all.map { ($0.id, $0) }
    )

    public static func definition(id: String) -> AchievementDefinition? {
        index[id]
    }
}
