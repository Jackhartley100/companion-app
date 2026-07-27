import Foundation
import os

/// Product events the app records.
///
/// The associated values are deliberately coarse. Nothing here carries a route
/// coordinate, a dog's name, note text, a photo or anything about the owner's
/// identity — distances and durations are reduced to buckets before they leave
/// the call site, so even a future remote analytics backend cannot reconstruct
/// where someone walks.
public enum AnalyticsEvent: Sendable, Hashable {
    case onboardingStarted
    case onboardingCompleted
    case dogCreated(hasPhoto: Bool, hasBreed: Bool)
    case walkPreparationOpened
    case walkStarted(activityType: String, dogCount: Int)
    case walkPaused
    case walkResumed
    case walkCompleted(distanceBucket: String, durationBucket: String)
    case walkDiscarded
    case walkRecovered
    case goalCreated(type: String, period: String)
    case achievementUnlocked(id: String)
    case activityShared
    case placeSaved
    case premiumFeatureViewed(feature: String)

    public var name: String {
        switch self {
        case .onboardingStarted: "onboarding_started"
        case .onboardingCompleted: "onboarding_completed"
        case .dogCreated: "dog_created"
        case .walkPreparationOpened: "walk_preparation_opened"
        case .walkStarted: "walk_started"
        case .walkPaused: "walk_paused"
        case .walkResumed: "walk_resumed"
        case .walkCompleted: "walk_completed"
        case .walkDiscarded: "walk_discarded"
        case .walkRecovered: "walk_recovered"
        case .goalCreated: "goal_created"
        case .achievementUnlocked: "achievement_unlocked"
        case .activityShared: "activity_shared"
        case .placeSaved: "place_saved"
        case .premiumFeatureViewed: "premium_feature_viewed"
        }
    }

    public var parameters: [String: String] {
        switch self {
        case .dogCreated(let hasPhoto, let hasBreed):
            ["has_photo": String(hasPhoto), "has_breed": String(hasBreed)]
        case .walkStarted(let type, let dogCount):
            ["activity_type": type, "dog_count": String(dogCount)]
        case .walkCompleted(let distance, let duration):
            ["distance_bucket": distance, "duration_bucket": duration]
        case .goalCreated(let type, let period):
            ["goal_type": type, "period": period]
        case .achievementUnlocked(let id):
            ["achievement_id": id]
        case .premiumFeatureViewed(let feature):
            ["feature": feature]
        default:
            [:]
        }
    }

    /// Reduces a distance to a coarse band so no exact walk length is recorded.
    public static func distanceBucket(_ metres: Double) -> String {
        switch metres {
        case ..<500: "0-500m"
        case ..<1_000: "500m-1km"
        case ..<3_000: "1-3km"
        case ..<5_000: "3-5km"
        case ..<10_000: "5-10km"
        default: "10km+"
        }
    }

    public static func durationBucket(_ seconds: TimeInterval) -> String {
        switch seconds {
        case ..<600: "0-10m"
        case ..<1_800: "10-30m"
        case ..<3_600: "30-60m"
        case ..<7_200: "1-2h"
        default: "2h+"
        }
    }
}

public protocol AnalyticsService: Sendable {
    func track(_ event: AnalyticsEvent)
}

/// Records nothing. The default, and what ships until an analytics provider is
/// chosen and a privacy review is done.
public struct NoOpAnalyticsService: AnalyticsService {
    public init() {}
    public func track(_ event: AnalyticsEvent) {}
}

/// Writes events to the unified log so the event stream can be inspected during
/// development without sending anything off the device.
public struct ConsoleAnalyticsService: AnalyticsService {
    private let logger = Logger(subsystem: "com.companion.app", category: "analytics")

    public init() {}

    public func track(_ event: AnalyticsEvent) {
        let parameters = event.parameters
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        logger.debug("analytics \(event.name, privacy: .public) \(parameters, privacy: .public)")
    }
}

/// Captures events in memory so tests can assert on them.
public final class RecordingAnalyticsService: AnalyticsService, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [AnalyticsEvent] = []

    public init() {}

    public var events: [AnalyticsEvent] {
        lock.withLock { storage }
    }

    public func track(_ event: AnalyticsEvent) {
        lock.withLock { storage.append(event) }
    }
}
