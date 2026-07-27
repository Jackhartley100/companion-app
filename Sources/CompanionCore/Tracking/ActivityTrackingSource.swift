import Foundation

/// What a tracking source is able to report.
///
/// The app asks the source what it can do rather than checking which concrete
/// type it is, so that adding the Companion Tracker later does not require
/// changes at every call site.
public struct TrackingCapabilities: OptionSet, Codable, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// Reports where the owner is. The iPhone can do this.
    public static let ownerLocation = TrackingCapabilities(rawValue: 1 << 0)
    /// Reports where the *dog* is, independently of the owner. Requires hardware.
    public static let dogLocation = TrackingCapabilities(rawValue: 1 << 1)
    /// Streams location while the app is not recording (for a live map).
    public static let liveLocation = TrackingCapabilities(rawValue: 1 << 2)
    public static let speed = TrackingCapabilities(rawValue: 1 << 3)
    public static let elevation = TrackingCapabilities(rawValue: 1 << 4)
    public static let activityIntensity = TrackingCapabilities(rawValue: 1 << 5)
    public static let sleep = TrackingCapabilities(rawValue: 1 << 6)
    public static let heartRate = TrackingCapabilities(rawValue: 1 << 7)
    public static let batteryStatus = TrackingCapabilities(rawValue: 1 << 8)
}

/// How a session should be recorded.
public struct TrackingConfiguration: Sendable, Hashable {
    public var activityType: ActivityType
    /// Fixes worse than this many metres of horizontal accuracy are discarded.
    public var accuracyThreshold: Double
    /// Whether the source should keep delivering updates in the background.
    public var allowsBackgroundUpdates: Bool

    public init(
        activityType: ActivityType = .walk,
        accuracyThreshold: Double = RouteFilter.Configuration.default.maximumHorizontalAccuracy,
        allowsBackgroundUpdates: Bool = true
    ) {
        self.activityType = activityType
        self.accuracyThreshold = accuracyThreshold
        self.allowsBackgroundUpdates = allowsBackgroundUpdates
    }
}

/// Something a tracking source tells the app while a session is running.
public enum TrackingUpdate: Sendable {
    /// A location fix that passed the source's own validity checks. Route
    /// filtering still happens downstream in `WalkRecorder`.
    case location(RoutePoint)
    /// The source's view of signal quality changed.
    case accuracyChanged(AccuracyLevel)
    /// The source stopped being able to produce fixes, with a reason.
    case interrupted(TrackingInterruption)
    /// The source recovered after an interruption.
    case resumedAfterInterruption
    /// Reserved for hardware sources.
    case batteryLevel(Int)
}

/// A coarse, presentable description of GPS signal quality.
public enum AccuracyLevel: String, Sendable, Comparable, CaseIterable {
    case unusable
    case poor
    case fair
    case good

    public var displayName: String {
        switch self {
        case .unusable: "Searching"
        case .poor: "Weak signal"
        case .fair: "Fair signal"
        case .good: "Good signal"
        }
    }

    /// Derived from horizontal accuracy in metres.
    public init(horizontalAccuracy: Double?) {
        guard let accuracy = horizontalAccuracy, accuracy > 0 else {
            self = .unusable
            return
        }
        switch accuracy {
        case ..<10: self = .good
        case ..<30: self = .fair
        case ..<65: self = .poor
        default: self = .unusable
        }
    }

    private var order: Int {
        switch self {
        case .unusable: 0
        case .poor: 1
        case .fair: 2
        case .good: 3
        }
    }

    public static func < (lhs: AccuracyLevel, rhs: AccuracyLevel) -> Bool {
        lhs.order < rhs.order
    }
}

public enum TrackingInterruption: Sendable, Hashable {
    case authorisationLost
    case signalLost
    case sourceDisconnected
}

/// The result of a finished session.
public struct TrackingSessionResult: Sendable {
    public let points: [RoutePoint]
    public let startDate: Date
    public let endDate: Date

    public init(points: [RoutePoint], startDate: Date, endDate: Date) {
        self.points = points
        self.startDate = startDate
        self.endDate = endDate
    }
}

public enum TrackingError: Error, Sendable, Equatable {
    case authorisationDenied
    case authorisationRestricted
    case locationServicesDisabled
    case alreadyRecording
    case notRecording
    case sourceUnavailable(String)
}

/// Anything that can record an activity: the iPhone today, a Companion Tracker or
/// an Apple Watch later. Consumers depend on this protocol, not on CoreLocation.
public protocol ActivityTrackingSource: Sendable {
    var sourceID: String { get }
    var displayName: String { get }
    var capabilities: TrackingCapabilities { get }
    /// The provenance recorded on activities produced by this source.
    var recordingSource: RecordingSource { get }

    func startSession(configuration: TrackingConfiguration) async throws
    func pauseSession() async throws
    func resumeSession() async throws
    func stopSession() async throws -> TrackingSessionResult

    /// Updates for the current session. A source finishes the stream when the
    /// session stops.
    ///
    /// - Note: `async` rather than synchronous as originally sketched, because
    ///   every real implementation stores the stream continuation in isolated
    ///   state (an actor, or the main actor for CoreLocation). A synchronous
    ///   requirement cannot be witnessed by an isolated method, so making it
    ///   `async` is what allows the concrete sources to be data-race safe under
    ///   Swift 6 without an `@unchecked Sendable` escape hatch.
    func sessionUpdates() async -> AsyncStream<TrackingUpdate>
}
