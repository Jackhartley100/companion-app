import SwiftUI
import CompanionCore

/// Every dependency the app needs, assembled in one place.
///
/// Views receive this rather than reaching for singletons, which is what makes
/// previews cheap: a preview builds an environment backed by in-memory stores
/// and gets a fully working screen with no disk, no network and no GPS.
@MainActor
public final class AppEnvironment {
    public let profileRepository: any UserProfileRepository
    public let dogRepository: any DogRepository
    public let activityRepository: any ActivityRepository
    public let goalRepository: any GoalRepository
    public let achievementRepository: any AchievementRepository
    public let placeRepository: any PlaceRepository
    public let sessionSnapshotStore: any SessionSnapshotStore
    public let imageStore: any ImageStore

    public let authentication: any AuthenticationService
    public let subscriptions: any SubscriptionService
    public let notifications: any NotificationService
    public let health: any HealthService
    public let analytics: any AnalyticsService

    public let trackingSource: any ActivityTrackingSource
    public let locationPermissions: any LocationPermissionProviding

    public init(
        profileRepository: any UserProfileRepository,
        dogRepository: any DogRepository,
        activityRepository: any ActivityRepository,
        goalRepository: any GoalRepository,
        achievementRepository: any AchievementRepository,
        placeRepository: any PlaceRepository,
        sessionSnapshotStore: any SessionSnapshotStore,
        imageStore: any ImageStore,
        authentication: any AuthenticationService,
        subscriptions: any SubscriptionService,
        notifications: any NotificationService,
        health: any HealthService,
        analytics: any AnalyticsService,
        trackingSource: any ActivityTrackingSource,
        locationPermissions: any LocationPermissionProviding
    ) {
        self.profileRepository = profileRepository
        self.dogRepository = dogRepository
        self.activityRepository = activityRepository
        self.goalRepository = goalRepository
        self.achievementRepository = achievementRepository
        self.placeRepository = placeRepository
        self.sessionSnapshotStore = sessionSnapshotStore
        self.imageStore = imageStore
        self.authentication = authentication
        self.subscriptions = subscriptions
        self.notifications = notifications
        self.health = health
        self.analytics = analytics
        self.trackingSource = trackingSource
        self.locationPermissions = locationPermissions
    }

    /// The production environment: files on disk, the iPhone's GPS.
    ///
    /// - Parameter storeName: The directory under Application Support. Demo mode
    ///   passes a different name, which is what keeps demonstration content out
    ///   of the owner's real data — a filesystem boundary rather than a flag.
    public static func live(storeName: String = "Companion") throws -> AppEnvironment {
        let root = try FileStore.defaultRoot().deletingLastPathComponent()
            .appendingPathComponent(storeName, isDirectory: true)
        let store = FileStore(root: root)
        let profileRepository = FileUserProfileRepository(store: store)
        let phoneSource = PhoneLocationTrackingSource()

        return AppEnvironment(
            profileRepository: profileRepository,
            dogRepository: FileDogRepository(store: store),
            activityRepository: FileActivityRepository(store: store),
            goalRepository: FileGoalRepository(store: store),
            achievementRepository: FileAchievementRepository(store: store),
            placeRepository: LocalSearchPlaceRepository(store: store),
            sessionSnapshotStore: FileSessionSnapshotStore(store: store),
            imageStore: FileImageStore(store: store),
            authentication: LocalAuthenticationService(profileRepository: profileRepository),
            subscriptions: FreeTierSubscriptionService(),
            notifications: InactiveNotificationService(),
            health: UnavailableHealthService(),
            analytics: NoOpAnalyticsService(),
            trackingSource: phoneSource,
            locationPermissions: phoneSource
        )
    }

    /// A live environment rooted at a separate store and pre-filled with
    /// demonstration content, for capturing screenshots.
    ///
    /// The separate `storeName` is what keeps demo content out of the owner's
    /// real data — a filesystem boundary rather than a flag a bug could flip.
    /// Seeding is skipped when the demo store already has a profile, so
    /// relaunching does not pile up duplicate history.
    public static func demonstration() async throws -> AppEnvironment {
        let environment = try live(storeName: "CompanionDemo")
        if try await environment.profileRepository.load() == nil {
            try await environment.seedDemonstrationContent()
        }
        return environment
    }

    private func seedDemonstrationContent() async throws {
        try await profileRepository.save(DemoDataProvider.profile())
        for dog in DemoDataProvider.dogs {
            try await dogRepository.save(dog)
        }
        for goal in DemoDataProvider.goals() {
            try await goalRepository.save(goal)
        }
        // History runs up to today rather than the provider's fixed reference
        // date, so the screens show live totals and a goal in progress instead
        // of a week of zeroes.
        //
        // Only the newest walks get their full route written. Those are the
        // ones anyone opens from the top of the history list, and the list and
        // charts draw the stored `routePreview` regardless — so writing points
        // for all eight weeks would slow first launch for nothing visible.
        let history = DemoDataProvider.activitiesWithRoutes(endingAt: Date())
        for (index, entry) in history.enumerated() {
            try await activityRepository.save(
                entry.activity,
                route: index < 12 ? entry.route : nil
            )
        }
    }

    /// An environment backed entirely by memory, for previews and tests.
    ///
    /// - Parameter simulatedRoute: When supplied, the tracking source replays it
    ///   instead of using GPS, which is the only way to exercise the recording
    ///   screens in the Simulator.
    public static func preview(
        store: InMemoryStore = DemoDataProvider.store(),
        locationStatus: LocationAuthorizationStatus = .whenInUse,
        currentLocation: Coordinate? = nil,
        simulatedRoute: [RoutePoint]? = SyntheticRoute.loop(pointCount: 200),
        subscription: SubscriptionStatus = .free
    ) -> AppEnvironment {
        AppEnvironment(
            profileRepository: InMemoryUserProfileRepository(store: store),
            dogRepository: InMemoryDogRepository(store: store),
            activityRepository: InMemoryActivityRepository(store: store),
            goalRepository: InMemoryGoalRepository(store: store),
            achievementRepository: InMemoryAchievementRepository(store: store),
            placeRepository: SamplePlaceRepository(),
            sessionSnapshotStore: InMemorySessionSnapshotStore(store: store),
            imageStore: InMemoryImageStore(store: store),
            authentication: StubAuthenticationService(),
            subscriptions: FreeTierSubscriptionService(status: subscription),
            notifications: InactiveNotificationService(),
            health: UnavailableHealthService(),
            analytics: NoOpAnalyticsService(),
            trackingSource: MockTrackingSource(
                script: simulatedRoute ?? [],
                interval: .milliseconds(400)
            ),
            locationPermissions: StubLocationPermissionProvider(
                status: locationStatus,
                fixedLocation: currentLocation
            )
        )
    }

    /// A recorder wired to this environment's dependencies.
    public func makeRecorder(calendar: Calendar) -> WalkRecorder {
        WalkRecorder(
            source: trackingSource,
            activityRepository: activityRepository,
            achievementRepository: achievementRepository,
            goalRepository: goalRepository,
            snapshotStore: sessionSnapshotStore,
            permissions: locationPermissions,
            analytics: analytics,
            calendar: calendar
        )
    }
}
