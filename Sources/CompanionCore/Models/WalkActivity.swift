import Foundation

/// The kind of outing being recorded. Only cases the app genuinely treats
/// differently (in naming, iconography and pace presentation) are offered.
public enum ActivityType: String, Codable, Sendable, CaseIterable, Identifiable {
    case walk
    case hike
    case run

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .walk: "Walk"
        case .hike: "Hike"
        case .run: "Run"
        }
    }

    public var symbolName: String {
        switch self {
        case .walk: "figure.walk"
        case .hike: "figure.hiking"
        case .run: "figure.run"
        }
    }

    /// Runs are conventionally read as pace (time per unit distance); walks and
    /// hikes read more naturally as speed.
    public var prefersPaceOverSpeed: Bool {
        self == .run
    }
}

/// Who the owner has chosen to make an activity visible to.
///
/// The MVP has no network, so this is stored and honoured locally only: it gates
/// what a future feed would publish, and it is surfaced honestly in the UI as a
/// preference rather than as an existing audience.
public enum ActivityVisibility: String, Codable, Sendable, CaseIterable, Identifiable {
    case privateOnly
    case followers
    case publicFeed

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .privateOnly: "Private"
        case .followers: "Followers"
        case .publicFeed: "Public"
        }
    }

    public var symbolName: String {
        switch self {
        case .privateOnly: "lock.fill"
        case .followers: "person.2.fill"
        case .publicFeed: "globe"
        }
    }
}

/// Where the location data in an activity came from.
///
/// This exists so the app can never imply it measured the dog's own movement when
/// it only tracked the owner's phone. It is surfaced verbatim on activity detail.
public enum RecordingSource: String, Codable, Sendable {
    case iPhone
    /// Reserved for the future Companion Tracker. Not produced by the MVP.
    case companionTracker
    /// Reserved for a future Apple Watch app. Not produced by the MVP.
    case appleWatch
    /// Generated demo content. Never mixed with the owner's real data.
    case demo
    /// Entered by hand with no route.
    case manual

    public var displayName: String {
        switch self {
        case .iPhone: "Recorded with iPhone"
        case .companionTracker: "Recorded with Companion Tracker"
        case .appleWatch: "Recorded with Apple Watch"
        case .demo: "Demo activity"
        case .manual: "Entered manually"
        }
    }

    /// True when the route describes the dog's own movement rather than the owner's.
    public var measuresDogDirectly: Bool {
        self == .companionTracker
    }
}

/// Where a record stands relative to a future cloud backend.
public enum SyncStatus: String, Codable, Sendable {
    case localOnly
    case pendingUpload
    case synced
    case conflict
    case failed
}

/// A completed walk. Route points live in a separate store keyed by `id`; this
/// type carries only what a list or summary needs.
public struct WalkActivity: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public var title: String
    public var activityType: ActivityType
    public var startDate: Date
    public var endDate: Date
    /// Wall-clock seconds between start and finish, including pauses.
    public var elapsedDuration: TimeInterval
    /// Seconds spent actually recording, excluding pauses.
    public var movingDuration: TimeInterval
    public var pausedDuration: TimeInterval
    /// Metres.
    public var distance: Double
    /// Metres of cumulative ascent, when the fixes carried usable altitude.
    public var elevationGain: Double?
    /// Dogs that came along. At least one in normal use; an empty array is
    /// tolerated so that a walk is never lost if its dog is deleted mid-flight.
    public var dogIDs: [UUID]
    public var ownerID: UUID
    public var notes: String?
    public var imageReferences: [String]
    public var visibility: ActivityVisibility
    public var recordingSource: RecordingSource
    /// Number of route points stored for this activity, so lists can show a map
    /// affordance without loading the route.
    public var routePointCount: Int
    /// A small, evenly-spaced sample of the route for thumbnails and previews.
    /// Never used for distance — `distance` is computed from the full route.
    public var routePreview: [Coordinate]
    public var syncStatus: SyncStatus
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        activityType: ActivityType = .walk,
        startDate: Date,
        endDate: Date,
        elapsedDuration: TimeInterval,
        movingDuration: TimeInterval,
        pausedDuration: TimeInterval = 0,
        distance: Double,
        elevationGain: Double? = nil,
        dogIDs: [UUID],
        ownerID: UUID,
        notes: String? = nil,
        imageReferences: [String] = [],
        visibility: ActivityVisibility = .privateOnly,
        recordingSource: RecordingSource = .iPhone,
        routePointCount: Int = 0,
        routePreview: [Coordinate] = [],
        syncStatus: SyncStatus = .localOnly,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.activityType = activityType
        self.startDate = startDate
        self.endDate = endDate
        self.elapsedDuration = elapsedDuration
        self.movingDuration = movingDuration
        self.pausedDuration = pausedDuration
        self.distance = distance
        self.elevationGain = elevationGain
        self.dogIDs = dogIDs
        self.ownerID = ownerID
        self.notes = notes
        self.imageReferences = imageReferences
        self.visibility = visibility
        self.recordingSource = recordingSource
        self.routePointCount = routePointCount
        self.routePreview = routePreview
        self.syncStatus = syncStatus
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Average speed in metres per second over the moving portion of the walk.
    public var averageSpeed: Double? {
        guard movingDuration > 0, distance > 0 else { return nil }
        return distance / movingDuration
    }

    /// Average pace in seconds per metre. Callers convert to per-km or per-mile.
    public var averagePace: Double? {
        guard distance > 0, movingDuration > 0 else { return nil }
        return movingDuration / distance
    }

    public var hasRoute: Bool { routePointCount > 1 }

    /// True when this record came from `DemoDataProvider` rather than the owner.
    public var isDemo: Bool { recordingSource == .demo }
}
