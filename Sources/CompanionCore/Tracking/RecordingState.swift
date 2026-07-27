import Foundation

/// The explicit state of a walk recording.
///
/// Modelled as one enum rather than several booleans (`isRecording`,
/// `isPaused`, `hasFinished`…) because those permit nonsense combinations and
/// every view then has to re-derive what they mean.
public enum RecordingState: Sendable, Hashable {
    /// Nothing is happening.
    case idle
    /// Permission is being requested or the location stack is warming up.
    case preparing
    /// Permission granted and a usable fix has arrived; the owner may start.
    case ready
    case recording
    case paused
    /// The owner confirmed finish; the session is being closed and saved.
    case finishing
    /// Saved successfully. Carries the activity so the summary screen can show it.
    case completed(WalkActivity)
    case failed(RecordingFailure)

    public var isActive: Bool {
        switch self {
        case .recording, .paused: true
        default: false
        }
    }

    public var isRecording: Bool {
        if case .recording = self { return true }
        return false
    }

    public var isPaused: Bool {
        if case .paused = self { return true }
        return false
    }

    /// True once the owner has committed to a session, so the UI can keep the
    /// active-walk screen presented across pauses and interruptions.
    public var hasSession: Bool {
        switch self {
        case .recording, .paused, .finishing: true
        default: false
        }
    }
}

/// A recording failure the owner needs to understand and act on.
///
/// Every case answers three questions: what happened, whether their data is
/// safe, and what to do next. Vague failures are deliberately not representable.
public enum RecordingFailure: Sendable, Hashable {
    case locationPermissionDenied
    case locationPermissionRestricted
    case locationServicesDisabled
    /// No usable fix arrived before the owner tried to start.
    case noSignal
    /// The walk finished but could not be written to disk. The route is retained
    /// in memory so the owner can retry.
    case saveFailed(reason: String)
    case sourceUnavailable(reason: String)

    public var title: String {
        switch self {
        case .locationPermissionDenied: "Location access is off"
        case .locationPermissionRestricted: "Location access is restricted"
        case .locationServicesDisabled: "Location Services are off"
        case .noSignal: "Waiting for a GPS signal"
        case .saveFailed: "That walk could not be saved yet"
        case .sourceUnavailable: "Tracking is unavailable"
        }
    }

    /// What happened and what the owner can do about it, in that order.
    public var message: String {
        switch self {
        case .locationPermissionDenied:
            "Companion needs your location to draw your route and measure distance. "
            + "You can turn it back on in Settings › Privacy & Security › Location Services › Companion."
        case .locationPermissionRestricted:
            "Location access is limited on this device, so walks cannot be recorded. "
            + "This is usually controlled by Screen Time or a device management profile."
        case .locationServicesDisabled:
            "Location Services are switched off for the whole device. "
            + "Turn them on in Settings › Privacy & Security › Location Services."
        case .noSignal:
            "Your iPhone has not found a good enough GPS fix yet. Standing outside with a clear "
            + "view of the sky usually takes a few seconds. You can start anyway — recording will "
            + "begin as soon as the signal arrives."
        case .saveFailed(let reason):
            "Your route is still here and nothing has been lost. Saving failed because: \(reason). "
            + "Try saving again, and if it keeps failing you can check available storage."
        case .sourceUnavailable(let reason):
            "Recording could not start: \(reason)."
        }
    }

    /// Whether the owner's recorded data survived the failure.
    public var dataIsSafe: Bool {
        switch self {
        case .saveFailed: true
        default: true
        }
    }

    /// True when the fix is in the Settings app rather than in Companion.
    public var requiresSystemSettings: Bool {
        switch self {
        case .locationPermissionDenied, .locationServicesDisabled: true
        default: false
        }
    }
}

/// Live numbers shown during a recording.
public struct LiveMetrics: Sendable, Hashable {
    /// Metres covered so far.
    public var distance: Double
    /// Seconds since the walk started, excluding paused time.
    public var movingDuration: TimeInterval
    /// Seconds since the walk started, including paused time.
    public var elapsedDuration: TimeInterval
    /// Metres per second over the recent window, or `nil` before enough data.
    public var currentSpeed: Double?
    /// Metres per second over the whole walk, or `nil` before enough data.
    public var averageSpeed: Double?
    public var accuracy: AccuracyLevel
    public var pointCount: Int

    public init(
        distance: Double = 0,
        movingDuration: TimeInterval = 0,
        elapsedDuration: TimeInterval = 0,
        currentSpeed: Double? = nil,
        averageSpeed: Double? = nil,
        accuracy: AccuracyLevel = .unusable,
        pointCount: Int = 0
    ) {
        self.distance = distance
        self.movingDuration = movingDuration
        self.elapsedDuration = elapsedDuration
        self.currentSpeed = currentSpeed
        self.averageSpeed = averageSpeed
        self.accuracy = accuracy
        self.pointCount = pointCount
    }

    public static let empty = LiveMetrics()
}
