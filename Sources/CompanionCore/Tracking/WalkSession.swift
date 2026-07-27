import Foundation

/// The accumulated state of one in-progress walk.
///
/// Deliberately a plain value type with no dependency on location services or
/// observation, so the whole of the recording arithmetic — distance, pause
/// accounting, pace windows — can be tested by feeding it synthetic points.
/// `WalkRecorder` owns one of these and adds the asynchronous plumbing.
public struct WalkSession: Codable, Sendable, Equatable {
    /// A stretch of time the owner had the walk paused.
    public struct PauseInterval: Codable, Sendable, Equatable {
        public var start: Date
        /// `nil` while the walk is still paused.
        public var end: Date?

        public init(start: Date, end: Date? = nil) {
            self.start = start
            self.end = end
        }

        public func duration(asOf now: Date) -> TimeInterval {
            max(0, (end ?? now).timeIntervalSince(start))
        }
    }

    public let id: UUID
    public let startDate: Date
    public var activityType: ActivityType
    public var dogIDs: [UUID]
    public var title: String?
    /// Only fixes that passed `RouteFilter`.
    public private(set) var points: [RoutePoint]
    public private(set) var pauses: [PauseInterval]
    /// Running total in metres, accumulated incrementally so that appending a
    /// point stays O(1) rather than re-walking the whole route.
    public private(set) var distance: Double
    public var recordingSource: RecordingSource
    /// Set when a pause ends, so the first point after resuming begins a new
    /// segment instead of being measured from where the pause started.
    private var startsNewSegment: Bool

    public init(
        id: UUID = UUID(),
        startDate: Date,
        activityType: ActivityType = .walk,
        dogIDs: [UUID],
        title: String? = nil,
        recordingSource: RecordingSource = .iPhone
    ) {
        self.id = id
        self.startDate = startDate
        self.activityType = activityType
        self.dogIDs = dogIDs
        self.title = title
        self.points = []
        self.pauses = []
        self.distance = 0
        self.recordingSource = recordingSource
        self.startsNewSegment = false
    }

    public var isPaused: Bool {
        pauses.last?.end == nil && !pauses.isEmpty
    }

    /// Adds an already-filtered point.
    ///
    /// - Important: Points offered while paused are ignored rather than stored.
    ///   Storing them would draw a straight line across whatever happened during
    ///   the pause — a coffee stop shown as a walked segment.
    public mutating func append(_ point: RoutePoint) {
        guard !isPaused else { return }
        if startsNewSegment {
            // First fix after a pause. Whatever happened during the pause — a
            // drive to a different park, or just standing still — the straight
            // line back to the pre-pause point was not walked, so it adds no
            // distance.
            startsNewSegment = false
        } else if let last = points.last {
            distance += last.coordinate.distance(to: point.coordinate)
        }
        points.append(point)
    }

    public mutating func pause(at date: Date) {
        guard !isPaused else { return }
        pauses.append(PauseInterval(start: date))
    }

    public mutating func resume(at date: Date) {
        guard isPaused, var last = pauses.last else { return }
        last.end = date
        pauses[pauses.count - 1] = last
        startsNewSegment = true
    }

    /// Total seconds spent paused, counting an open pause up to `now`.
    public func pausedDuration(asOf now: Date) -> TimeInterval {
        pauses.reduce(0) { $0 + $1.duration(asOf: now) }
    }

    public func elapsedDuration(asOf now: Date) -> TimeInterval {
        max(0, now.timeIntervalSince(startDate))
    }

    /// Wall-clock time minus paused time. Never negative.
    public func movingDuration(asOf now: Date) -> TimeInterval {
        max(0, elapsedDuration(asOf: now) - pausedDuration(asOf: now))
    }

    /// Speed in metres per second over the trailing `window` seconds of route.
    ///
    /// A trailing window rather than the instantaneous fix-to-fix speed, because
    /// a single noisy pair makes the on-screen number jump around and reads as
    /// broken while walking.
    public func currentSpeed(asOf now: Date, window: TimeInterval = 30) -> Double? {
        guard !isPaused, points.count >= 2 else { return nil }
        let cutoff = now.addingTimeInterval(-window)
        let recent = points.filter { $0.timestamp >= cutoff }
        guard recent.count >= 2,
              let first = recent.first,
              let last = recent.last else { return nil }
        let interval = last.timestamp.timeIntervalSince(first.timestamp)
        guard interval > 0 else { return nil }
        return recent.totalDistance / interval
    }

    public func averageSpeed(asOf now: Date) -> Double? {
        let moving = movingDuration(asOf: now)
        guard moving > 0, distance > 0 else { return nil }
        return distance / moving
    }

    public func metrics(asOf now: Date, accuracy: AccuracyLevel) -> LiveMetrics {
        LiveMetrics(
            distance: distance,
            movingDuration: movingDuration(asOf: now),
            elapsedDuration: elapsedDuration(asOf: now),
            currentSpeed: currentSpeed(asOf: now),
            averageSpeed: averageSpeed(asOf: now),
            accuracy: accuracy,
            pointCount: points.count
        )
    }

    /// Builds the persistable activity for this session.
    public func makeActivity(
        ownerID: UUID,
        endDate: Date,
        title: String,
        visibility: ActivityVisibility
    ) -> WalkActivity {
        WalkActivity(
            id: id,
            title: title,
            activityType: activityType,
            startDate: startDate,
            endDate: endDate,
            elapsedDuration: elapsedDuration(asOf: endDate),
            movingDuration: movingDuration(asOf: endDate),
            pausedDuration: pausedDuration(asOf: endDate),
            distance: distance,
            elevationGain: points.elevationGain(),
            dogIDs: dogIDs,
            ownerID: ownerID,
            visibility: visibility,
            recordingSource: recordingSource,
            routePointCount: points.count,
            routePreview: RoutePreview.sample(from: points)
        )
    }
}

/// Reduces a full route to a handful of coordinates for list thumbnails.
public enum RoutePreview {
    /// Evenly samples at most `limit` coordinates, always keeping the first and
    /// last so the preview starts and ends where the walk did.
    public static func sample(from points: [RoutePoint], limit: Int = 60) -> [Coordinate] {
        guard points.count > limit else { return points.map(\.coordinate) }
        guard limit > 1 else { return points.first.map { [$0.coordinate] } ?? [] }

        let stride = Double(points.count - 1) / Double(limit - 1)
        return (0..<limit).map { index in
            points[Int((Double(index) * stride).rounded())].coordinate
        }
    }
}
