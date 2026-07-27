import Foundation

/// Replays a scripted route at a controllable speed.
///
/// Used by SwiftUI previews, by unit tests and by anyone running the app in the
/// Simulator, where there is no real GPS. It is the only way to exercise the
/// active-walk screen without walking outside, so it deliberately behaves like a
/// real source: it honours pause, it emits accuracy changes, and it can be told
/// to drop out mid-session to test the interruption path.
public actor MockTrackingSource: ActivityTrackingSource {
    public nonisolated let sourceID = "mock"
    public nonisolated let displayName = "Simulated route"
    public nonisolated let capabilities: TrackingCapabilities = [.ownerLocation, .speed, .elevation]
    public nonisolated let recordingSource: RecordingSource

    private let script: [RoutePoint]
    /// Seconds of wall-clock time between emitted points.
    private let interval: Duration
    /// Emit an `.interrupted` update after this many points, for testing.
    private let interruptAfter: Int?

    private var continuation: AsyncStream<TrackingUpdate>.Continuation?
    private var task: Task<Void, Never>?
    private var emitted: [RoutePoint] = []
    private var isPaused = false
    private var startDate = Date()

    public init(
        script: [RoutePoint],
        interval: Duration = .milliseconds(1_000),
        interruptAfter: Int? = nil,
        recordingSource: RecordingSource = .iPhone
    ) {
        self.script = script
        self.interval = interval
        self.interruptAfter = interruptAfter
        self.recordingSource = recordingSource
    }

    public func sessionUpdates() async -> AsyncStream<TrackingUpdate> {
        AsyncStream { continuation in
            self.continuation = continuation
        }
    }

    public func startSession(configuration: TrackingConfiguration) async throws {
        guard task == nil else { throw TrackingError.alreadyRecording }
        startDate = Date()
        emitted = []
        isPaused = false
        continuation?.yield(.accuracyChanged(.good))

        let script = self.script
        let interval = self.interval
        task = Task { [weak self] in
            for (index, point) in script.enumerated() {
                if Task.isCancelled { return }
                try? await Task.sleep(for: interval)
                if Task.isCancelled { return }
                await self?.emit(point, index: index)
            }
        }
    }

    private func emit(_ point: RoutePoint, index: Int) {
        guard !isPaused else { return }
        // Points are re-stamped to now so that elapsed time in a simulated walk
        // matches the wall clock the owner is watching.
        let stamped = RoutePoint(
            coordinate: point.coordinate,
            altitude: point.altitude,
            horizontalAccuracy: point.horizontalAccuracy ?? 5,
            verticalAccuracy: point.verticalAccuracy,
            speed: point.speed,
            course: point.course,
            timestamp: Date()
        )
        emitted.append(stamped)
        continuation?.yield(.location(stamped))

        if let interruptAfter, index == interruptAfter {
            continuation?.yield(.interrupted(.signalLost))
            continuation?.yield(.accuracyChanged(.unusable))
        }
    }

    /// Pushes an update straight into the stream, bypassing the timed replay.
    ///
    /// Tests need to control exactly when each fix arrives; waiting on the
    /// replay timer would make them slow and timing-dependent.
    public func inject(_ update: TrackingUpdate) {
        if case .location(let point) = update { emitted.append(point) }
        continuation?.yield(update)
    }

    public func pauseSession() async throws {
        guard task != nil else { throw TrackingError.notRecording }
        isPaused = true
    }

    public func resumeSession() async throws {
        guard task != nil else { throw TrackingError.notRecording }
        isPaused = false
        continuation?.yield(.resumedAfterInterruption)
    }

    public func stopSession() async throws -> TrackingSessionResult {
        guard task != nil else { throw TrackingError.notRecording }
        task?.cancel()
        task = nil
        continuation?.finish()
        continuation = nil
        return TrackingSessionResult(points: emitted, startDate: startDate, endDate: Date())
    }
}

/// Builds synthetic routes for previews, tests and Simulator use.
public enum SyntheticRoute {
    /// A roughly circular loop of `pointCount` fixes around `centre`.
    ///
    /// - Parameter radiusMetres: Radius of the loop. A 250 m radius loop is
    ///   about 1.6 km around, which is a realistic short walk.
    public static func loop(
        centre: Coordinate = Coordinate(latitude: 51.5074, longitude: -0.1278),
        radiusMetres: Double = 250,
        pointCount: Int = 120,
        startingAt start: Date = Date(),
        secondsBetweenPoints: TimeInterval = 5,
        horizontalAccuracy: Double = 5
    ) -> [RoutePoint] {
        // Degrees of latitude are ~111.32 km everywhere; longitude shrinks with
        // the cosine of latitude, so the loop stays circular on the ground.
        let metresPerDegreeLatitude = 111_320.0
        let metresPerDegreeLongitude = metresPerDegreeLatitude * cos(centre.latitude * .pi / 180)

        return (0..<pointCount).map { index in
            let angle = (Double(index) / Double(pointCount)) * 2 * .pi
            let latitude = centre.latitude + (radiusMetres * sin(angle)) / metresPerDegreeLatitude
            let longitude = centre.longitude + (radiusMetres * cos(angle)) / metresPerDegreeLongitude
            return RoutePoint(
                coordinate: Coordinate(latitude: latitude, longitude: longitude),
                altitude: 20 + 6 * sin(angle * 2),
                horizontalAccuracy: horizontalAccuracy,
                verticalAccuracy: 8,
                speed: 1.35,
                course: (angle * 180 / .pi).truncatingRemainder(dividingBy: 360),
                timestamp: start.addingTimeInterval(Double(index) * secondsBetweenPoints)
            )
        }
    }

    /// A straight line, useful when a test needs a known exact distance.
    public static func line(
        from start: Coordinate = Coordinate(latitude: 51.5074, longitude: -0.1278),
        metres: Double = 1_000,
        pointCount: Int = 50,
        startingAt startDate: Date = Date(),
        secondsBetweenPoints: TimeInterval = 5
    ) -> [RoutePoint] {
        let metresPerDegreeLatitude = 111_320.0
        return (0..<pointCount).map { index in
            let fraction = Double(index) / Double(max(1, pointCount - 1))
            return RoutePoint(
                coordinate: Coordinate(
                    latitude: start.latitude + (metres * fraction) / metresPerDegreeLatitude,
                    longitude: start.longitude
                ),
                altitude: 15,
                horizontalAccuracy: 5,
                verticalAccuracy: 8,
                speed: 1.4,
                course: 0,
                timestamp: startDate.addingTimeInterval(Double(index) * secondsBetweenPoints)
            )
        }
    }
}
