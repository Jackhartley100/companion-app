import Foundation

/// Why a candidate location fix was not added to the route.
public enum RouteRejection: String, Sendable, Hashable, CaseIterable {
    /// Horizontal accuracy was missing, negative or worse than the threshold.
    case poorAccuracy
    /// The timestamp was older than the last accepted point, or too old to trust.
    case staleTimestamp
    /// The implied speed between this fix and the last one is not physically
    /// plausible for the activity — almost always a multipath or cell-tower jump.
    case impossibleSpeed
    /// The fix is close enough to the previous one that it is GPS jitter rather
    /// than movement. Accepting these inflates distance while standing still.
    case belowMovementThreshold
}

/// Decides which location fixes become part of the recorded route.
///
/// ## Strategy
///
/// The filter is intentionally conservative in one direction only: it discards
/// fixes it cannot trust, but it never smooths or interpolates accepted ones.
/// Aggressive smoothing makes a route look tidy while quietly deleting genuine
/// movement — a dog walk full of real doubling back would be flattened into a
/// straight line, and the reported distance would be wrong in the owner's favour.
///
/// Four independent checks run in order, cheapest first:
///
/// 1. **Accuracy gate** — a fix with horizontal accuracy worse than
///    `maximumHorizontalAccuracy` (default 50 m) carries more error than the
///    distance a walker covers between fixes, so it can only add noise.
/// 2. **Timestamp sanity** — CoreLocation may deliver a cached fix on start-up.
///    Fixes older than the previous accepted point, or older than
///    `maximumFixAge`, are dropped.
/// 3. **Plausible speed** — distance over elapsed time is compared with a
///    per-activity ceiling. A 300 m jump in two seconds is a positioning error,
///    not a sprint.
/// 4. **Movement threshold** — consecutive fixes closer together than
///    `minimumMovementDistance` are treated as jitter. The threshold scales with
///    the reported accuracy of the fix, because a ±30 m fix jitters further than
///    a ±5 m one.
///
/// The filter is a value type with no stored mutable state beyond the last
/// accepted point, which makes it directly testable with synthetic traces.
public struct RouteFilter: Sendable {
    public struct Configuration: Sendable, Hashable {
        /// Fixes worse than this many metres are discarded outright.
        public var maximumHorizontalAccuracy: Double
        /// Fixes older than this many seconds are treated as stale.
        public var maximumFixAge: TimeInterval
        /// Baseline jitter threshold in metres, before accuracy scaling.
        public var minimumMovementDistance: Double
        /// Multiplier applied to a fix's horizontal accuracy when deciding the
        /// jitter threshold.
        public var accuracyJitterFactor: Double
        /// Metres per second above which movement is considered impossible.
        public var maximumPlausibleSpeed: Double

        public init(
            maximumHorizontalAccuracy: Double = 50,
            maximumFixAge: TimeInterval = 30,
            minimumMovementDistance: Double = 3,
            accuracyJitterFactor: Double = 0.5,
            maximumPlausibleSpeed: Double = 12
        ) {
            self.maximumHorizontalAccuracy = maximumHorizontalAccuracy
            self.maximumFixAge = maximumFixAge
            self.minimumMovementDistance = minimumMovementDistance
            self.accuracyJitterFactor = accuracyJitterFactor
            self.maximumPlausibleSpeed = maximumPlausibleSpeed
        }

        public static let `default` = Configuration()

        /// Ceilings chosen well above realistic human pace so that genuine
        /// movement is never discarded: a fast sprint is about 10 m/s.
        public static func forActivity(_ type: ActivityType) -> Configuration {
            var configuration = Configuration()
            switch type {
            case .walk:
                configuration.maximumPlausibleSpeed = 8
            case .hike:
                configuration.maximumPlausibleSpeed = 8
            case .run:
                configuration.maximumPlausibleSpeed = 12
            }
            return configuration
        }
    }

    public let configuration: Configuration
    private var lastAccepted: RoutePoint?

    public init(configuration: Configuration = .default) {
        self.configuration = configuration
    }

    /// The most recently accepted point, or `nil` before the first one.
    public var lastAcceptedPoint: RoutePoint? { lastAccepted }

    public enum Decision: Sendable, Hashable {
        case accepted(RoutePoint)
        case rejected(RouteRejection)
    }

    /// Evaluates a candidate fix and, when accepted, records it as the new
    /// reference point.
    ///
    /// - Parameter now: Injected so tests can reason about fix age deterministically.
    public mutating func evaluate(_ point: RoutePoint, now: Date? = nil) -> Decision {
        let referenceNow = now ?? point.timestamp

        guard let accuracy = point.horizontalAccuracy,
              accuracy > 0,
              accuracy <= configuration.maximumHorizontalAccuracy else {
            return .rejected(.poorAccuracy)
        }

        if referenceNow.timeIntervalSince(point.timestamp) > configuration.maximumFixAge {
            return .rejected(.staleTimestamp)
        }

        guard let previous = lastAccepted else {
            lastAccepted = point
            return .accepted(point)
        }

        let interval = point.timestamp.timeIntervalSince(previous.timestamp)
        guard interval > 0 else {
            return .rejected(.staleTimestamp)
        }

        let distance = previous.coordinate.distance(to: point.coordinate)

        if distance / interval > configuration.maximumPlausibleSpeed {
            return .rejected(.impossibleSpeed)
        }

        // A fix reported as ±30 m can wander ~15 m without anyone moving, so the
        // jitter threshold rises with uncertainty rather than staying fixed.
        let jitterThreshold = max(
            configuration.minimumMovementDistance,
            accuracy * configuration.accuracyJitterFactor
        )
        if distance < jitterThreshold {
            return .rejected(.belowMovementThreshold)
        }

        lastAccepted = point
        return .accepted(point)
    }

    /// Forgets the reference point. Called on resume so that the gap accumulated
    /// while paused is never counted as distance walked.
    public mutating func reset() {
        lastAccepted = nil
    }

    /// Runs a whole trace through a fresh filter. Used by tests and by recovery
    /// of an interrupted session.
    public static func filter(
        _ points: [RoutePoint],
        configuration: Configuration = .default
    ) -> (accepted: [RoutePoint], rejections: [RouteRejection]) {
        var filter = RouteFilter(configuration: configuration)
        var accepted: [RoutePoint] = []
        var rejections: [RouteRejection] = []
        for point in points {
            switch filter.evaluate(point, now: point.timestamp) {
            case .accepted(let accepted_): accepted.append(accepted_)
            case .rejected(let reason): rejections.append(reason)
            }
        }
        return (accepted, rejections)
    }
}
