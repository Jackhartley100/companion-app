import Testing
import Foundation
@testable import CompanionCore

/// A tracking source driven by hand, so recorder tests do not depend on timing.
private actor ScriptedTrackingSource: ActivityTrackingSource {
    nonisolated let sourceID = "scripted"
    nonisolated let displayName = "Scripted"
    nonisolated let capabilities: TrackingCapabilities = [.ownerLocation]
    nonisolated let recordingSource: RecordingSource = .iPhone

    private var continuation: AsyncStream<TrackingUpdate>.Continuation?
    private(set) var didStart = false
    private(set) var didStop = false
    private(set) var pauseCount = 0
    private(set) var resumeCount = 0
    private var startError: TrackingError?
    private var points: [RoutePoint] = []

    init(startError: TrackingError? = nil) {
        self.startError = startError
    }

    func sessionUpdates() async -> AsyncStream<TrackingUpdate> {
        AsyncStream { continuation in self.continuation = continuation }
    }

    func startSession(configuration: TrackingConfiguration) async throws {
        if let startError { throw startError }
        didStart = true
    }

    func pauseSession() async throws { pauseCount += 1 }
    func resumeSession() async throws { resumeCount += 1 }

    func stopSession() async throws -> TrackingSessionResult {
        didStop = true
        continuation?.finish()
        return TrackingSessionResult(points: points, startDate: Date(), endDate: Date())
    }

    func send(_ update: TrackingUpdate) {
        if case .location(let point) = update { points.append(point) }
        continuation?.yield(update)
    }
}

@MainActor
private struct RecorderHarness {
    let recorder: WalkRecorder
    let source: ScriptedTrackingSource
    let store: InMemoryStore
    let analytics: RecordingAnalyticsService
    let ownerID = UUID()
    let dogID = UUID()

    init(startError: TrackingError? = nil, permission: LocationAuthorizationStatus = .whenInUse) {
        let store = InMemoryStore()
        let source = ScriptedTrackingSource(startError: startError)
        let analytics = RecordingAnalyticsService()
        self.store = store
        self.source = source
        self.analytics = analytics
        self.recorder = WalkRecorder(
            source: source,
            activityRepository: InMemoryActivityRepository(store: store),
            achievementRepository: InMemoryAchievementRepository(store: store),
            goalRepository: InMemoryGoalRepository(store: store),
            snapshotStore: InMemorySessionSnapshotStore(store: store),
            permissions: StubLocationPermissionProvider(status: permission),
            analytics: analytics
        )
    }

    func startWalk() async {
        await recorder.start(dogIDs: [dogID], ownerID: ownerID)
    }

    /// Emits an update and returns only once the recorder has consumed it.
    ///
    /// The recorder drains its stream on a main-actor task, so a bare
    /// `Task.yield()` is not a guarantee that it has run. Waiting on an
    /// observable consequence is deterministic; the iteration cap turns a
    /// genuine hang into a failed expectation rather than a hung test run.
    func send(_ update: TrackingUpdate) async {
        let before = recorder.routePoints.count
        let expectsPoint: Bool = if case .location = update { recorder.state.isRecording } else { false }

        await source.send(update)

        for _ in 0..<200 {
            await Task.yield()
            if !expectsPoint { continue }
            if recorder.routePoints.count > before { return }
        }
    }

    func send(_ updates: [RoutePoint]) async {
        for point in updates { await send(.location(point)) }
    }
}

/// A short trace of realistic walking steps, 8 m apart every 5 seconds.
private func walkingTrace(count: Int, from start: Date = Date()) -> [RoutePoint] {
    (0..<count).map { index in
        RoutePoint(
            coordinate: Coordinate(
                latitude: 51.5074 + (Double(index) * 8) / 111_320.0,
                longitude: -0.1278
            ),
            horizontalAccuracy: 5,
            timestamp: start.addingTimeInterval(Double(index) * 5)
        )
    }
}

@Suite("Walk recorder state machine")
@MainActor
struct WalkRecorderTests {
    @Test("A new recorder is idle")
    func startsIdle() async {
        let harness = RecorderHarness()
        #expect(harness.recorder.state == .idle)
        #expect(harness.recorder.metrics.distance == 0)
    }

    @Test("Preparing with permission granted reaches ready")
    func prepareReady() async {
        let harness = RecorderHarness(permission: .whenInUse)
        await harness.recorder.prepare()
        #expect(harness.recorder.state == .ready)
    }

    @Test("Preparing with permission denied fails with an actionable reason")
    func prepareDenied() async {
        let harness = RecorderHarness(permission: .denied)
        await harness.recorder.prepare()
        #expect(harness.recorder.state == .failed(.locationPermissionDenied))
        guard case .failed(let failure) = harness.recorder.state else { return }
        #expect(failure.requiresSystemSettings)
        #expect(failure.dataIsSafe)
    }

    @Test("Preparing with restricted permission fails distinctly from denied")
    func prepareRestricted() async {
        let harness = RecorderHarness(permission: .restricted)
        await harness.recorder.prepare()
        #expect(harness.recorder.state == .failed(.locationPermissionRestricted))
    }

    @Test("Starting moves to recording and tells the source to start")
    func startRecording() async {
        let harness = RecorderHarness()
        await harness.startWalk()
        #expect(harness.recorder.state == .recording)
        #expect(await harness.source.didStart)
    }

    @Test("A source that refuses to start leaves the recorder failed, not recording")
    func startFailure() async {
        let harness = RecorderHarness(startError: .authorisationDenied)
        await harness.startWalk()
        #expect(harness.recorder.state == .failed(.locationPermissionDenied))
        #expect(harness.recorder.state.hasSession == false)
    }

    @Test("Starting twice does not begin a second session")
    func doubleStartIgnored() async {
        let harness = RecorderHarness()
        await harness.startWalk()
        await harness.startWalk()
        #expect(harness.recorder.state == .recording)
    }

    @Test("Accepted fixes accumulate distance and route points")
    func locationUpdatesAccumulate() async {
        let harness = RecorderHarness()
        await harness.startWalk()
        for point in walkingTrace(count: 10) {
            await harness.send(.location(point))
        }
        #expect(harness.recorder.routePoints.count == 10)
        // Nine 8 m steps.
        #expect(abs(harness.recorder.metrics.distance - 72) < 2)
    }

    @Test("Noisy fixes are filtered out of the recorded distance")
    func noisyFixesFiltered() async {
        let harness = RecorderHarness()
        await harness.startWalk()

        let trace = walkingTrace(count: 5)
        for point in trace { await harness.send(.location(point)) }

        // A 5 km jump two seconds later is a positioning error.
        let jump = RoutePoint(
            coordinate: Coordinate(latitude: 51.5524, longitude: -0.1278),
            horizontalAccuracy: 5,
            timestamp: trace[4].timestamp.addingTimeInterval(2)
        )
        await harness.send(.location(jump))

        #expect(harness.recorder.routePoints.count == 5)
        #expect(harness.recorder.metrics.distance < 100)
    }

    @Test("Recording pauses and resumes")
    func pauseResume() async {
        let harness = RecorderHarness()
        await harness.startWalk()

        await harness.recorder.pause()
        #expect(harness.recorder.state == .paused)
        #expect(harness.recorder.state.isPaused)
        #expect(await harness.source.pauseCount == 1)

        await harness.recorder.resume()
        #expect(harness.recorder.state == .recording)
        #expect(await harness.source.resumeCount == 1)
    }

    /// The behaviour that stops a drive home during a pause becoming distance.
    @Test("Fixes arriving while paused add no distance")
    func pausedFixesIgnored() async {
        let harness = RecorderHarness()
        await harness.startWalk()

        let trace = walkingTrace(count: 5)
        for point in trace { await harness.send(.location(point)) }
        let distanceBeforePause = harness.recorder.metrics.distance

        await harness.recorder.pause()
        for point in walkingTrace(count: 20, from: trace[4].timestamp.addingTimeInterval(10)) {
            await harness.send(.location(point))
        }

        #expect(harness.recorder.metrics.distance == distanceBeforePause)
        #expect(harness.recorder.routePoints.count == 5)
    }

    @Test("The gap crossed while paused is not counted after resuming")
    func pauseGapNotCounted() async {
        let harness = RecorderHarness()
        await harness.startWalk()

        for point in walkingTrace(count: 3) { await harness.send(.location(point)) }
        let before = harness.recorder.metrics.distance

        await harness.recorder.pause()
        await harness.recorder.resume()

        // Resume a kilometre away — the owner drove somewhere while paused.
        let elsewhere = RoutePoint(
            coordinate: Coordinate(latitude: 51.5174, longitude: -0.1278),
            horizontalAccuracy: 5,
            timestamp: Date().addingTimeInterval(600)
        )
        await harness.send(.location(elsewhere))

        #expect(harness.recorder.metrics.distance == before)
    }

    @Test("Pausing while idle does nothing")
    func pauseWhenIdleIgnored() async {
        let harness = RecorderHarness()
        await harness.recorder.pause()
        #expect(harness.recorder.state == .idle)
    }

    @Test("Finishing saves the activity and its route")
    func finishSaves() async throws {
        let harness = RecorderHarness()
        await harness.startWalk()
        for point in walkingTrace(count: 20) { await harness.send(.location(point)) }
        await harness.recorder.finish()

        guard case .completed(let activity) = harness.recorder.state else {
            Issue.record("Expected the recorder to complete, got \(harness.recorder.state)")
            return
        }
        #expect(activity.dogIDs == [harness.dogID])
        #expect(activity.ownerID == harness.ownerID)
        #expect(activity.recordingSource == .iPhone)
        #expect(activity.routePointCount == 20)
        #expect(await harness.source.didStop)

        let repository = InMemoryActivityRepository(store: harness.store)
        #expect(try await repository.activities(matching: .all).count == 1)
        #expect(try await repository.route(for: activity.id).count == 20)
    }

    @Test("A generated title is used when the owner does not type one")
    func generatedTitle() async {
        let harness = RecorderHarness()
        await harness.startWalk()
        await harness.recorder.finish()
        guard case .completed(let activity) = harness.recorder.state else { return }
        #expect(activity.title.isEmpty == false)
    }

    @Test("A typed title overrides the generated one")
    func customTitle() async {
        let harness = RecorderHarness()
        await harness.startWalk()
        await harness.recorder.finish(title: "Canal towpath loop")
        guard case .completed(let activity) = harness.recorder.state else { return }
        #expect(activity.title == "Canal towpath loop")
    }

    @Test("Discarding a walk saves nothing and returns to idle")
    func discard() async throws {
        let harness = RecorderHarness()
        await harness.startWalk()
        for point in walkingTrace(count: 10) { await harness.send(.location(point)) }
        await harness.recorder.finish(discard: true)

        #expect(harness.recorder.state == .idle)
        let repository = InMemoryActivityRepository(store: harness.store)
        #expect(try await repository.activities(matching: .all).isEmpty)
    }

    @Test("A save failure keeps the route so the owner can retry")
    func saveFailureIsRecoverable() async throws {
        let harness = RecorderHarness()
        await harness.startWalk()
        for point in walkingTrace(count: 10) { await harness.send(.location(point)) }

        await harness.store.setInjectedFailure(.writeFailed("disk full"))
        await harness.recorder.finish()

        guard case .failed(let failure) = harness.recorder.state else {
            Issue.record("Expected a failed state")
            return
        }
        guard case .saveFailed = failure else {
            Issue.record("Expected a save failure, got \(failure)")
            return
        }
        #expect(failure.dataIsSafe)

        // Clearing the fault and retrying succeeds, with the route intact.
        await harness.store.setInjectedFailure(nil)
        await harness.recorder.retrySave()

        guard case .completed(let activity) = harness.recorder.state else {
            Issue.record("Expected the retry to complete")
            return
        }
        #expect(activity.routePointCount == 10)
    }

    @Test("Losing the signal mid-walk flags an interruption without ending the walk")
    func signalInterruption() async {
        let harness = RecorderHarness()
        await harness.startWalk()
        await harness.send(.interrupted(.signalLost))

        #expect(harness.recorder.isSignalInterrupted)
        #expect(harness.recorder.state == .recording)

        await harness.send(.resumedAfterInterruption)
        #expect(harness.recorder.isSignalInterrupted == false)
    }

    @Test("Losing authorisation mid-walk fails the recording")
    func authorisationLostMidWalk() async {
        let harness = RecorderHarness()
        await harness.startWalk()
        await harness.send(.interrupted(.authorisationLost))
        #expect(harness.recorder.state == .failed(.locationPermissionDenied))
    }

    @Test("Accuracy changes are reflected in the live metrics")
    func accuracyReported() async {
        let harness = RecorderHarness()
        await harness.startWalk()
        await harness.send(.accuracyChanged(.good))
        #expect(harness.recorder.metrics.accuracy == .good)
        await harness.send(.accuracyChanged(.poor))
        #expect(harness.recorder.metrics.accuracy == .poor)
    }

    @Test("Resetting clears everything back to idle")
    func reset() async {
        let harness = RecorderHarness()
        await harness.startWalk()
        for point in walkingTrace(count: 5) { await harness.send(.location(point)) }
        await harness.recorder.finish()
        harness.recorder.reset()

        #expect(harness.recorder.state == .idle)
        #expect(harness.recorder.routePoints.isEmpty)
        #expect(harness.recorder.metrics.distance == 0)
    }

    @Test("Completing a first walk unlocks First Walk")
    func achievementsEvaluatedOnFinish() async {
        let harness = RecorderHarness()
        await harness.startWalk()
        for point in walkingTrace(count: 10) { await harness.send(.location(point)) }
        await harness.recorder.finish()

        #expect(harness.recorder.pendingUnlocks.contains { $0.achievementID == "first_walk" })
    }

    @Test("The recording lifecycle is reported to analytics without route data")
    func analyticsEvents() async {
        let harness = RecorderHarness()
        await harness.startWalk()
        await harness.recorder.pause()
        await harness.recorder.resume()
        await harness.recorder.finish()

        let names = harness.analytics.events.map(\.name)
        #expect(names.contains("walk_started"))
        #expect(names.contains("walk_paused"))
        #expect(names.contains("walk_resumed"))
        #expect(names.contains("walk_completed"))

        // Distances leave the app only as coarse buckets.
        let completed = harness.analytics.events.first { $0.name == "walk_completed" }
        #expect(completed?.parameters["distance_bucket"] != nil)
    }
}

@Suite("Interrupted session recovery")
@MainActor
struct SessionRecoveryTests {
    @Test("A substantial abandoned session is offered for recovery")
    func recoverableSessionFound() async throws {
        let harness = RecorderHarness()
        var abandoned = WalkSession(startDate: Date().addingTimeInterval(-1_800), dogIDs: [harness.dogID])
        for point in walkingTrace(count: 40) { abandoned.append(point) }
        try await InMemorySessionSnapshotStore(store: harness.store).save(abandoned)

        await harness.recorder.checkForRecoverableSession()
        #expect(harness.recorder.recoverableSession?.id == abandoned.id)
    }

    @Test("An empty abandoned session is discarded rather than offered")
    func emptySessionNotOffered() async throws {
        let harness = RecorderHarness()
        let empty = WalkSession(startDate: Date(), dogIDs: [harness.dogID])
        try await InMemorySessionSnapshotStore(store: harness.store).save(empty)

        await harness.recorder.checkForRecoverableSession()
        #expect(harness.recorder.recoverableSession == nil)
        #expect(try await InMemorySessionSnapshotStore(store: harness.store).load() == nil)
    }

    @Test("A recovered session can be saved as a finished walk")
    func recoveredSessionSaved() async throws {
        let harness = RecorderHarness()
        var abandoned = WalkSession(startDate: Date().addingTimeInterval(-1_800), dogIDs: [harness.dogID])
        for point in walkingTrace(count: 40) { abandoned.append(point) }
        try await InMemorySessionSnapshotStore(store: harness.store).save(abandoned)

        await harness.recorder.checkForRecoverableSession()
        await harness.recorder.saveRecoveredSession(ownerID: harness.ownerID)

        guard case .completed(let activity) = harness.recorder.state else {
            Issue.record("Expected the recovered session to be saved")
            return
        }
        #expect(activity.routePointCount == 40)
        #expect(activity.distance > 0)
        #expect(try await InMemorySessionSnapshotStore(store: harness.store).load() == nil)
    }

    @Test("A recovered session can be discarded")
    func recoveredSessionDiscarded() async throws {
        let harness = RecorderHarness()
        var abandoned = WalkSession(startDate: Date(), dogIDs: [harness.dogID])
        for point in walkingTrace(count: 40) { abandoned.append(point) }
        try await InMemorySessionSnapshotStore(store: harness.store).save(abandoned)

        await harness.recorder.checkForRecoverableSession()
        await harness.recorder.discardRecoveredSession()

        #expect(harness.recorder.recoverableSession == nil)
        #expect(try await InMemorySessionSnapshotStore(store: harness.store).load() == nil)
    }
}
