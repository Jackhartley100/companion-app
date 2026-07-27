import Foundation

/// A reminder the app can schedule.
///
/// Every case is opt-in and worded as an invitation. Nothing here tells the
/// owner they have let their dog down — a missed walk produces silence, not a
/// notification.
public enum LocalReminder: Sendable, Hashable {
    /// A daily nudge at a time the owner picked.
    case dailyWalk(hour: Int, minute: Int)
    /// Late in the week, when a goal is within reach.
    case weeklyGoalWithinReach(dogName: String, remainingText: String)
    case achievementUnlocked(title: String)

    public var identifier: String {
        switch self {
        case .dailyWalk: "reminder.daily_walk"
        case .weeklyGoalWithinReach: "reminder.weekly_goal"
        case .achievementUnlocked(let title): "achievement.\(title)"
        }
    }

    public var title: String {
        switch self {
        case .dailyWalk: "Time for a walk?"
        case .weeklyGoalWithinReach: "Nearly there"
        case .achievementUnlocked: "Achievement unlocked"
        }
    }

    public var body: String {
        switch self {
        case .dailyWalk:
            "Even a short one counts."
        case .weeklyGoalWithinReach(let dogName, let remaining):
            "\(remaining) would complete \(dogName)'s weekly goal."
        case .achievementUnlocked(let title):
            "You earned \(title)."
        }
    }
}

public enum NotificationAuthorization: String, Sendable {
    case notDetermined
    case denied
    case authorised
}

public protocol NotificationService: Sendable {
    func authorizationStatus() async -> NotificationAuthorization
    func requestAuthorization() async -> NotificationAuthorization
    func schedule(_ reminder: LocalReminder) async
    func cancel(identifier: String) async
    func cancelAll() async
}

/// The notification service the MVP ships with.
///
/// It does nothing. Reminders are designed and modelled, but nothing is
/// scheduled until the reminder settings screen exists and the owner has chosen
/// a time — scheduling notifications an owner never asked for is exactly the
/// behaviour this product avoids.
///
// TODO: Replace with a UserNotifications implementation when the reminder
// preferences UI lands. `LocalReminder` already carries everything a
// UNMutableNotificationContent needs.
public struct InactiveNotificationService: NotificationService {
    public init() {}
    public func authorizationStatus() async -> NotificationAuthorization { .notDetermined }
    public func requestAuthorization() async -> NotificationAuthorization { .notDetermined }
    public func schedule(_ reminder: LocalReminder) async {}
    public func cancel(identifier: String) async {}
    public func cancelAll() async {}
}
