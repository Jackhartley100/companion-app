import Foundation

/// What a goal measures. Values are stored in base units (metres, seconds, counts).
public enum GoalType: String, Codable, Sendable, CaseIterable, Identifiable {
    case distance
    case duration
    case activeDays
    case walkCount

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .distance: "Distance"
        case .duration: "Time"
        case .activeDays: "Active days"
        case .walkCount: "Walks"
        }
    }

    public var symbolName: String {
        switch self {
        case .distance: "point.topleft.down.to.point.bottomright.curvepath"
        case .duration: "clock"
        case .activeDays: "calendar"
        case .walkCount: "figure.walk"
        }
    }
}

public enum GoalPeriod: String, Codable, Sendable, CaseIterable, Identifiable {
    case daily
    case weekly

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .daily: "Daily"
        case .weekly: "Weekly"
        }
    }
}

/// A target the owner has set for a dog.
///
/// Goals are chosen by the owner. Suggested starting values exist, but they are
/// presented as general starting points, never as veterinary recommendations.
public struct Goal: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    /// `nil` means the goal applies to all of the owner's dogs combined.
    public var dogID: UUID?
    public var goalType: GoalType
    /// Metres for `.distance`, seconds for `.duration`, whole counts otherwise.
    public var targetValue: Double
    public var period: GoalPeriod
    public var startDate: Date
    public var isActive: Bool
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        dogID: UUID?,
        goalType: GoalType,
        targetValue: Double,
        period: GoalPeriod = .weekly,
        startDate: Date = Date(),
        isActive: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.dogID = dogID
        self.goalType = goalType
        self.targetValue = targetValue
        self.period = period
        self.startDate = startDate
        self.isActive = isActive
        self.createdAt = createdAt
    }

    /// A starting point for a new goal, scaled by how much exercise the dog is
    /// already used to. Deliberately modest so the first week feels achievable.
    ///
    /// - Important: These are conversational defaults, not health advice. The UI
    ///   must label them as starting points and let the owner change them.
    public static func suggestedTarget(
        for type: GoalType,
        activityLevel: ActivityLevel,
        period: GoalPeriod
    ) -> Double {
        let weeklyMultiplier: Double = switch activityLevel {
        case .relaxed: 0.6
        case .moderate: 1.0
        case .active: 1.5
        case .veryActive: 2.0
        }
        let periodScale: Double = period == .daily ? 1.0 / 7.0 : 1.0

        switch type {
        case .distance:
            // 20 km per week at "moderate", rounded to a friendly value.
            return (20_000 * weeklyMultiplier * periodScale / 500).rounded() * 500
        case .duration:
            // 5 hours per week at "moderate".
            return (18_000 * weeklyMultiplier * periodScale / 300).rounded() * 300
        case .activeDays:
            return period == .daily ? 1 : min(7, (4 * weeklyMultiplier).rounded())
        case .walkCount:
            return period == .daily
                ? max(1, (1.5 * weeklyMultiplier).rounded())
                : max(1, (8 * weeklyMultiplier).rounded())
        }
    }
}

/// How far through a goal the dog currently is.
public struct GoalProgress: Sendable, Hashable, Identifiable {
    public var id: UUID { goal.id }
    public let goal: Goal
    /// Achieved so far, in the goal's base unit.
    public let currentValue: Double
    /// Start of the period the progress was measured over.
    public let periodStart: Date
    /// End of the period, exclusive.
    public let periodEnd: Date

    public init(goal: Goal, currentValue: Double, periodStart: Date, periodEnd: Date) {
        self.goal = goal
        self.currentValue = currentValue
        self.periodStart = periodStart
        self.periodEnd = periodEnd
    }

    /// 0...1, clamped. Values above the target report as complete rather than
    /// overflowing a progress ring.
    public var fraction: Double {
        guard goal.targetValue > 0 else { return 0 }
        return min(1, max(0, currentValue / goal.targetValue))
    }

    public var isComplete: Bool { currentValue >= goal.targetValue }

    /// How much is left, in the goal's base unit. Zero once complete.
    public var remaining: Double { max(0, goal.targetValue - currentValue) }

    public func timeRemaining(from date: Date = Date()) -> TimeInterval {
        max(0, periodEnd.timeIntervalSince(date))
    }
}
