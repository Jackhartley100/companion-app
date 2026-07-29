import Foundation

/// The rule that unlocks an achievement.
///
/// Rules are data, not code paths in views: `AchievementEngine` evaluates every
/// definition against the same activity history, so adding an achievement means
/// adding a definition to `AchievementCatalog` and nothing else.
public enum AchievementRule: Codable, Sendable, Hashable {
    /// Total number of saved activities reaches `count`.
    case totalActivities(count: Int)
    /// A single activity covers at least `metres`.
    case singleWalkDistance(metres: Double)
    /// Lifetime distance reaches `metres`.
    case cumulativeDistance(metres: Double)
    /// `days` consecutive calendar days with at least one activity.
    case streak(days: Int)
    /// An activity starts within the local hour range `from..<to` (24-hour clock).
    case startedBetweenHours(from: Int, to: Int)
    /// An activity starts on a Saturday or Sunday.
    case weekendActivity
    /// A weekly goal is completed.
    case goalCompleted(period: GoalPeriod)
}

/// How hard an achievement is, within its family.
///
/// Purely presentational — the unlock rule itself is what decides when
/// something is earned. Tiers exist so a badge can be coloured (bronze,
/// silver, gold, platinum) and so families like "Walks Together" read as a
/// progression rather than a shelf of unrelated stickers.
public enum AchievementTier: String, Codable, Sendable, CaseIterable, Equatable, Comparable {
    case bronze
    case silver
    case gold
    case platinum

    public var displayName: String {
        switch self {
        case .bronze: "Bronze"
        case .silver: "Silver"
        case .gold: "Gold"
        case .platinum: "Platinum"
        }
    }

    private var rank: Int {
        switch self {
        case .bronze: 0
        case .silver: 1
        case .gold: 2
        case .platinum: 3
        }
    }

    public static func < (lhs: AchievementTier, rhs: AchievementTier) -> Bool {
        lhs.rank < rhs.rank
    }
}

/// The family an achievement belongs to, for grouping the trophy case into
/// sections rather than one flat, uncategorised grid.
public enum AchievementCategory: String, Codable, Sendable, CaseIterable, Hashable {
    case walks
    case distance
    case streaks
    case timing
    case goals

    public var displayName: String {
        switch self {
        case .walks: "Walks Together"
        case .distance: "Distance"
        case .streaks: "Streaks"
        case .timing: "Time of Day"
        case .goals: "Goals"
        }
    }
}

/// The definition of an achievement. Immutable reference data.
public struct AchievementDefinition: Identifiable, Codable, Sendable, Hashable {
    /// Stable identifier persisted in unlocks — never change an existing value.
    public let id: String
    public let title: String
    public let details: String
    public let symbolName: String
    public let rule: AchievementRule
    public let tier: AchievementTier
    public let category: AchievementCategory

    public init(
        id: String,
        title: String,
        details: String,
        symbolName: String,
        rule: AchievementRule,
        tier: AchievementTier,
        category: AchievementCategory
    ) {
        self.id = id
        self.title = title
        self.details = details
        self.symbolName = symbolName
        self.rule = rule
        self.tier = tier
        self.category = category
    }
}

/// A record that an achievement has been earned.
public struct AchievementUnlock: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public let achievementID: String
    /// The dog the achievement was earned with, when it is dog-specific.
    public let dogID: UUID?
    /// The activity that triggered the unlock, when there was one.
    public let walkID: UUID?
    public let unlockedAt: Date
    /// False until the owner has seen the celebration for it.
    public var acknowledged: Bool

    public init(
        id: UUID = UUID(),
        achievementID: String,
        dogID: UUID? = nil,
        walkID: UUID? = nil,
        unlockedAt: Date = Date(),
        acknowledged: Bool = false
    ) {
        self.id = id
        self.achievementID = achievementID
        self.dogID = dogID
        self.walkID = walkID
        self.unlockedAt = unlockedAt
        self.acknowledged = acknowledged
    }
}

/// A definition paired with its current state, ready for display.
public struct AchievementStatus: Identifiable, Sendable, Hashable {
    public var id: String { definition.id }
    public let definition: AchievementDefinition
    public let unlock: AchievementUnlock?
    /// 0...1 towards unlocking, where the rule supports partial progress.
    public let progress: Double?

    public init(definition: AchievementDefinition, unlock: AchievementUnlock?, progress: Double?) {
        self.definition = definition
        self.unlock = unlock
        self.progress = progress
    }

    public var isUnlocked: Bool { unlock != nil }
}
