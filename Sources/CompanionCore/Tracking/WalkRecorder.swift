import Foundation
import Observation

/// Drives one walk from preparation to a saved activity.
///
/// The single owner of the recording state machine. Views read `state` and
/// `metrics` and call `start` / `pause` / `resume` / `finish`; no view performs
/// distance arithmetic, touches a location manager, or writes to a repository.
///
/// ## State machine
/// ```
/// idle ──prepare──▶ preparing ──▶ ready ──start──▶ recording ⇄ paused
///                       │                              │         │
///                       ▼                              └────┬────┘
///                    failed ◀──────────────────────────┐    │
///                                                      │  finish
///                                                      │    ▼
///                                                   (save)  finishing ──▶ completed
/// ```
/// `failed` is reachable from anywhere and always carries a `RecordingFailure`
/// that explains what happened and what the owner can do.
@MainActor
@Observable
public final class WalkRecorder {
    public private(set) var state: RecordingState = .idle
    public private(set) var metrics: LiveMetrics = .empty
    /// Accepted route points for the current session, for the live map.
    public private(set) var routePoints: [RoutePoint] = []
    /// The most recent fix, accepted or not, so the map can show where the owner
    /// is even while the filter is rejecting noisy points.
    public private(set) var lastKnownPoint: RoutePoint?
    /// Set when the signal drops mid-walk; cleared when it returns.
    public private(set) var isSignalInterrupted = false
    /// A recovered session found on launch, awaiting the owner's decision.
    public private(set) var recoverableSession: WalkSession?

    private let source: any ActivityTrackingSource
    private let activityRepository: any ActivityRepository
    private let achievementRepository: any AchievementRepository
    private let goalRepository: any GoalRepository
    private let snapshotStore: any SessionSnapshotStore
    private let permissions: any LocationPermissionProviding
    private let analytics: any AnalyticsService
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    private var session: WalkSession?
    private var filter = RouteFilter()
    private var updatesTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?
    private var snapshotTask: Task<Void, Never>?
    private var ownerID: UUID?
    private var defaultVisibility: ActivityVisibility = .privateOnly

    /// Achievements unlocked by the walk that has just been saved, for the
    /// summary screen to celebrate.
    public private(set) var pendingUnlocks: [AchievementUnlock] = []

    /// Dogs on the walk in progress, in the order the owner chose them.
    ///
    /// Exposed so the active-walk screen shows who is actually on this walk
    /// rather than inferring it from whichever dog Today happens to have
    /// selected — the two diverge as soon as someone records a walk with both
    /// dogs, or changes the selection mid-walk.
    public var currentDogIDs: [UUID] { session?.dogIDs ?? [] }

    /// The activity type of the walk in progress, which decides whether the
    /// live rate is shown as pace or as speed.
    public var currentActivityType: ActivityType? { session?.activityType }

    public init(
        source: any ActivityTrackingSource,
        activityRepository: any ActivityRepository,
        achievementRepository: any AchievementRepository,
        goalRepository: any GoalRepository,
        snapshotStore: any SessionSnapshotStore,
        permissions: any LocationPermissionProviding,
        analytics: any AnalyticsService = NoOpAnalyticsService(),
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.source = source
        self.activityRepository = activityRepository
        self.achievementRepository = achievementRepository
        self.goalRepository = goalRepository
        self.snapshotStore = snapshotStore
        self.permissions = permissions
        self.analytics = analytics
        self.calendar = calendar
        self.now = now
    }

    // No `deinit` cancellation: the tasks capture `self` weakly and exit on the
    // first iteration after the recorder is released, and a `deinit` cannot
    // touch main-actor-isolated state anyway.

    // MARK: - Preparation

    /// Checks permission and warms up the location stack.
    ///
    /// Called when the preparation sheet appears, so that by the time the owner
    /// taps Start there is usually already a usable fix and recording begins
    /// immediately rather than after a ten-second search.
    public func prepare() async {
        state = .preparing
        guard await permissions.servicesEnabled() else {
            state = .failed(.locationServicesDisabled)
            return
        }
        let status = await permissions.currentStatus()
        if let failure = status.failure {
            state = .failed(failure)
            return
        }
        state = .ready
    }

    /// Requests location permission in response to a deliberate tap.
    @discardableResult
    public func requestLocationPermission() async -> LocationAuthorizationStatus {
        let status = await permissions.requestWhenInUseAuthorization()
        if let failure = status.failure {
            state = .failed(failure)
        } else if status.isUsable {
            state = .ready
        }
        return status
    }

    // MARK: - Recording

    public func start(
        dogIDs: [UUID],
        ownerID: UUID,
        activityType: ActivityType = .walk,
        title: String? = nil,
        visibility: ActivityVisibility = .privateOnly
    ) async {
        guard !state.hasSession else { return }

        self.ownerID = ownerID
        self.defaultVisibility = visibility
        let startDate = now()
        var newSession = WalkSession(
            startDate: startDate,
            activityType: activityType,
            dogIDs: dogIDs,
            title: title,
            recordingSource: source.recordingSource
        )
        newSession.title = title
        session = newSession
        routePoints = []
        metrics = .empty
        filter = RouteFilter(configuration: .forActivity(activityType))
        isSignalInterrupted = false
        pendingUnlocks = []

        // Subscribe before starting the session. The stream's continuation only
        // exists once `sessionUpdates()` has returned, so starting first would
        // silently drop every fix that arrived before the observer task got
        // scheduled — the first few seconds of every walk.
        await observeUpdates()

        do {
            try await source.startSession(
                configuration: TrackingConfiguration(activityType: activityType)
            )
        } catch let error as TrackingError {
            state = .failed(failure(for: error))
            session = nil
            return
        } catch {
            state = .failed(.sourceUnavailable(reason: error.localizedDescription))
            session = nil
            return
        }

        state = .recording
        analytics.track(.walkStarted(activityType: activityType.rawValue, dogCount: dogIDs.count))
        startTicking()
        startSnapshotting()
    }

    public func pause() async {
        guard state.isRecording, var session else { return }
        session.pause(at: now())
        self.session = session
        state = .paused
        try? await source.pauseSession()
        analytics.track(.walkPaused)
        await persistSnapshot()
    }

    public func resume() async {
        guard state.isPaused, var session else { return }
        session.resume(at: now())
        self.session = session
        state = .recording
        // The filter's reference point is discarded so the straight line across
        // the pause is never counted as distance walked.
        filter.reset()
        try? await source.resumeSession()
        analytics.track(.walkResumed)
    }

    /// Stops recording and saves the activity.
    ///
    /// - Parameters:
    ///   - title: Overrides the generated title when the owner typed one.
    ///   - discard: When true the session is thrown away instead of saved.
    public func finish(title: String? = nil, discard: Bool = false) async {
        guard state.hasSession, let session, let ownerID else { return }
        state = .finishing

        updatesTask?.cancel(); updatesTask = nil
        tickTask?.cancel(); tickTask = nil
        snapshotTask?.cancel(); snapshotTask = nil

        _ = try? await source.stopSession()

        guard !discard else {
            analytics.track(.walkDiscarded)
            try? await snapshotStore.clear()
            reset()
            return
        }

        let endDate = now()
        let resolvedTitle = title
            ?? session.title
            ?? WalkTitleGenerator(calendar: calendar)
                .title(for: session.startDate, activityType: session.activityType)

        let activity = session.makeActivity(
            ownerID: ownerID,
            endDate: endDate,
            title: resolvedTitle,
            visibility: defaultVisibility
        )

        do {
            try await activityRepository.save(activity, route: session.points)
            try? await snapshotStore.clear()
            await evaluateAchievements(after: activity)
            analytics.track(
                .walkCompleted(
                    distanceBucket: AnalyticsEvent.distanceBucket(activity.distance),
                    durationBucket: AnalyticsEvent.durationBucket(activity.movingDuration)
                )
            )
            state = .completed(activity)
        } catch let error as RepositoryError {
            // The route is deliberately left in `session` so the owner can retry
            // rather than losing the walk.
            state = .failed(.saveFailed(reason: error.userMessage))
        } catch {
            state = .failed(.saveFailed(reason: error.localizedDescription))
        }
    }

    /// Retries a save that previously failed. The session is still in memory.
    public func retrySave(title: String? = nil) async {
        guard case .failed(.saveFailed) = state, session != nil else { return }
        state = .finishing
        await finishSaveOnly(title: title)
    }

    private func finishSaveOnly(title: String?) async {
        guard let session, let ownerID else { return }
        let resolvedTitle = title
            ?? session.title
            ?? WalkTitleGenerator(calendar: calendar)
                .title(for: session.startDate, activityType: session.activityType)
        let activity = session.makeActivity(
            ownerID: ownerID,
            endDate: now(),
            title: resolvedTitle,
            visibility: defaultVisibility
        )
        do {
            try await activityRepository.save(activity, route: session.points)
            try? await snapshotStore.clear()
            await evaluateAchievements(after: activity)
            state = .completed(activity)
        } catch {
            state = .failed(.saveFailed(reason: error.localizedDescription))
        }
    }

    /// Returns the recorder to idle after the summary screen is dismissed.
    public func reset() {
        updatesTask?.cancel(); updatesTask = nil
        tickTask?.cancel(); tickTask = nil
        snapshotTask?.cancel(); snapshotTask = nil
        session = nil
        routePoints = []
        metrics = .empty
        lastKnownPoint = nil
        isSignalInterrupted = false
        pendingUnlocks = []
        state = .idle
    }

    // MARK: - Interruption recovery

    /// Looks for a session left behind by a crash or a force-quit.
    ///
    /// Called at launch. The owner is asked what to do rather than having a
    /// half-finished walk silently resurrected or silently deleted.
    public func checkForRecoverableSession() async {
        guard state == .idle else { return }
        guard let saved = try? await snapshotStore.load() else { return }
        // A session with nothing in it is not worth asking about.
        guard saved.points.count > 1 else {
            try? await snapshotStore.clear()
            return
        }
        recoverableSession = saved
    }

    /// Saves a recovered session as a finished walk.
    public func saveRecoveredSession(ownerID: UUID) async {
        guard let saved = recoverableSession else { return }
        self.ownerID = ownerID
        session = saved
        recoverableSession = nil
        state = .finishing
        await finishSaveOnly(title: saved.title)
    }

    public func discardRecoveredSession() async {
        recoverableSession = nil
        try? await snapshotStore.clear()
    }

    // MARK: - Update handling

    /// Awaits the source's update stream, then consumes it on a detached task.
    ///
    /// The `await` is what makes the subscription ordered: by the time this
    /// returns, the source holds a live continuation, so nothing it emits next
    /// can be lost.
    private func observeUpdates() async {
        let stream = await source.sessionUpdates()
        updatesTask = Task { [weak self] in
            for await update in stream {
                if Task.isCancelled { return }
                guard let self else { return }
                self.apply(update)
            }
        }
    }

    private func apply(_ update: TrackingUpdate) {
        switch update {
        case .location(let point):
            lastKnownPoint = point
            guard state.isRecording, var session else { return }
            if case .accepted(let accepted) = filter.evaluate(point, now: now()) {
                session.append(accepted)
                self.session = session
                routePoints.append(accepted)
            }
            refreshMetrics()

        case .accuracyChanged(let level):
            metrics.accuracy = level

        case .interrupted(.authorisationLost):
            state = .failed(.locationPermissionDenied)

        case .interrupted:
            isSignalInterrupted = true

        case .resumedAfterInterruption:
            isSignalInterrupted = false

        case .batteryLevel:
            // Reserved for hardware sources; the phone source never sends this.
            break
        }
    }

    /// Updates the clock-driven metrics once a second so elapsed time advances
    /// even when the owner is standing still and no fixes are arriving.
    private func startTicking() {
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                self.refreshMetrics()
            }
        }
    }

    private func refreshMetrics() {
        guard let session else { return }
        var updated = session.metrics(asOf: now(), accuracy: metrics.accuracy)
        updated.accuracy = metrics.accuracy
        metrics = updated
    }

    /// Writes the session to disk periodically.
    ///
    /// Thirty seconds is a deliberate compromise: often enough that a crash
    /// costs at most half a minute of route, rare enough that a two-hour hike
    /// does not spend its battery on disk writes.
    private func startSnapshotting() {
        snapshotTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard let self, !Task.isCancelled else { return }
                await self.persistSnapshot()
            }
        }
    }

    private func persistSnapshot() async {
        guard let session, state.hasSession else { return }
        try? await snapshotStore.save(session)
    }

    // MARK: - Achievements

    private func evaluateAchievements(after activity: WalkActivity) async {
        guard let allActivities = try? await activityRepository.activities(matching: .all),
              let existing = try? await achievementRepository.unlocks() else { return }

        let dogID = activity.dogIDs.first
        let dogActivities = dogID.map { id in
            allActivities.filter { $0.dogIDs.contains(id) }
        } ?? allActivities

        let goals = (try? await goalRepository.activeGoals()) ?? []
        let evaluator = GoalEvaluator(calendar: calendar)
        let progress = evaluator.progress(for: goals, activities: allActivities, asOf: now())
        let streak = StreakCalculator(calendar: calendar).streak(for: dogActivities, asOf: now())

        let engine = AchievementEngine(calendar: calendar)
        let unlocks = engine.newUnlocks(
            context: AchievementContext(
                activities: dogActivities,
                goalProgress: progress,
                streak: streak,
                dogID: dogID
            ),
            existing: existing,
            triggeringWalk: activity,
            now: now()
        )

        for unlock in unlocks {
            try? await achievementRepository.save(unlock)
            analytics.track(.achievementUnlocked(id: unlock.achievementID))
        }
        pendingUnlocks = unlocks
    }

    // MARK: - Helpers

    private func failure(for error: TrackingError) -> RecordingFailure {
        switch error {
        case .authorisationDenied: .locationPermissionDenied
        case .authorisationRestricted: .locationPermissionRestricted
        case .locationServicesDisabled: .locationServicesDisabled
        case .alreadyRecording: .sourceUnavailable(reason: "a walk is already being recorded")
        case .notRecording: .sourceUnavailable(reason: "no walk is being recorded")
        case .sourceUnavailable(let detail): .sourceUnavailable(reason: detail)
        }
    }
}
