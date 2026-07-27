import Foundation

/// In-memory repositories used by SwiftUI previews and unit tests.
///
/// They share the query and ordering semantics of the file-backed versions by
/// delegating to `ActivityQuery.matches`, so a preview cannot show behaviour the
/// real store would not produce.
public actor InMemoryStore {
    public var profile: UserProfile?
    public var dogs: [Dog] = []
    public var activities: [WalkActivity] = []
    public var routes: [UUID: [RoutePoint]] = [:]
    public var goals: [Goal] = []
    public var unlocks: [AchievementUnlock] = []
    public var savedPlaceIDs: Set<UUID> = []
    public var session: WalkSession?
    public var images: [String: Data] = [:]
    /// When set, every mutating call throws it. Used to exercise error states.
    public var injectedFailure: RepositoryError?

    public init(
        profile: UserProfile? = nil,
        dogs: [Dog] = [],
        activities: [WalkActivity] = [],
        routes: [UUID: [RoutePoint]] = [:],
        goals: [Goal] = [],
        unlocks: [AchievementUnlock] = []
    ) {
        self.profile = profile
        self.dogs = dogs
        self.activities = activities
        self.routes = routes
        self.goals = goals
        self.unlocks = unlocks
    }

    public func setInjectedFailure(_ failure: RepositoryError?) {
        injectedFailure = failure
    }

    func check() throws {
        if let injectedFailure { throw injectedFailure }
    }

    // MARK: Mutations

    func setProfile(_ profile: UserProfile?) throws { try check(); self.profile = profile }

    func upsertDog(_ dog: Dog) throws {
        try check()
        if let index = dogs.firstIndex(where: { $0.id == dog.id }) { dogs[index] = dog }
        else { dogs.append(dog) }
    }

    func removeDog(_ id: UUID) throws { try check(); dogs.removeAll { $0.id == id } }

    func upsertActivity(_ activity: WalkActivity, route: [RoutePoint]?) throws {
        try check()
        if let route { routes[activity.id] = route }
        if let index = activities.firstIndex(where: { $0.id == activity.id }) {
            activities[index] = activity
        } else {
            activities.append(activity)
        }
    }

    func removeActivity(_ id: UUID) throws {
        try check()
        activities.removeAll { $0.id == id }
        routes[id] = nil
    }

    func removeAllActivities() throws { try check(); activities = []; routes = [:] }

    func upsertGoal(_ goal: Goal) throws {
        try check()
        if let index = goals.firstIndex(where: { $0.id == goal.id }) { goals[index] = goal }
        else { goals.append(goal) }
    }

    func removeGoal(_ id: UUID) throws { try check(); goals.removeAll { $0.id == id } }

    func upsertUnlock(_ unlock: AchievementUnlock) throws {
        try check()
        if let index = unlocks.firstIndex(where: { $0.id == unlock.id }) { unlocks[index] = unlock }
        else { unlocks.append(unlock) }
    }

    func acknowledgeUnlocks(_ ids: Set<UUID>) throws {
        try check()
        for index in unlocks.indices where ids.contains(unlocks[index].id) {
            unlocks[index].acknowledged = true
        }
    }

    func setSaved(_ saved: Bool, placeID: UUID) throws {
        try check()
        if saved { savedPlaceIDs.insert(placeID) } else { savedPlaceIDs.remove(placeID) }
    }

    func setSession(_ session: WalkSession?) throws { try check(); self.session = session }

    func putImage(_ data: Data) throws -> String {
        try check()
        let reference = "\(UUID().uuidString).jpg"
        images[reference] = data
        return reference
    }

    func removeImage(_ reference: String) throws { try check(); images[reference] = nil }

    func wipe() throws {
        try check()
        profile = nil; dogs = []; activities = []; routes = [:]
        goals = []; unlocks = []; session = nil; images = [:]
    }
}

public struct InMemoryUserProfileRepository: UserProfileRepository {
    let store: InMemoryStore
    public init(store: InMemoryStore) { self.store = store }
    public func load() async throws -> UserProfile? { await store.profile }
    public func save(_ profile: UserProfile) async throws { try await store.setProfile(profile) }
    public func deleteEverything() async throws { try await store.wipe() }
}

public struct InMemoryDogRepository: DogRepository {
    let store: InMemoryStore
    public init(store: InMemoryStore) { self.store = store }
    public func all() async throws -> [Dog] {
        await store.dogs.sorted { $0.sortIndex < $1.sortIndex }
    }
    public func active() async throws -> [Dog] { try await all().filter { !$0.isArchived } }
    public func dog(id: UUID) async throws -> Dog? { await store.dogs.first { $0.id == id } }
    public func save(_ dog: Dog) async throws { try await store.upsertDog(dog) }
    public func delete(id: UUID) async throws { try await store.removeDog(id) }
}

public struct InMemoryActivityRepository: ActivityRepository {
    let store: InMemoryStore
    public init(store: InMemoryStore) { self.store = store }

    public func activities(matching query: ActivityQuery) async throws -> [WalkActivity] {
        var result = await store.activities
            .filter(query.matches)
            .sorted { $0.startDate > $1.startDate }
        if let limit = query.limit, result.count > limit {
            result = Array(result.prefix(limit))
        }
        return result
    }

    public func activity(id: UUID) async throws -> WalkActivity? {
        await store.activities.first { $0.id == id }
    }

    public func save(_ activity: WalkActivity, route: [RoutePoint]?) async throws {
        try await store.upsertActivity(activity, route: route)
    }

    public func delete(id: UUID) async throws { try await store.removeActivity(id) }
    public func route(for id: UUID) async throws -> [RoutePoint] { await store.routes[id] ?? [] }
    public func deleteAll() async throws { try await store.removeAllActivities() }
}

public struct InMemoryGoalRepository: GoalRepository {
    let store: InMemoryStore
    public init(store: InMemoryStore) { self.store = store }
    public func goals(dogID: UUID?) async throws -> [Goal] {
        let all = await store.goals
        guard let dogID else { return all }
        return all.filter { $0.dogID == dogID || $0.dogID == nil }
    }
    public func activeGoals() async throws -> [Goal] { await store.goals.filter(\.isActive) }
    public func save(_ goal: Goal) async throws { try await store.upsertGoal(goal) }
    public func delete(id: UUID) async throws { try await store.removeGoal(id) }
}

public struct InMemoryAchievementRepository: AchievementRepository {
    let store: InMemoryStore
    public init(store: InMemoryStore) { self.store = store }
    public func unlocks() async throws -> [AchievementUnlock] { await store.unlocks }
    public func save(_ unlock: AchievementUnlock) async throws { try await store.upsertUnlock(unlock) }
    public func acknowledge(ids: [UUID]) async throws { try await store.acknowledgeUnlocks(Set(ids)) }
}

public struct InMemorySessionSnapshotStore: SessionSnapshotStore {
    let store: InMemoryStore
    public init(store: InMemoryStore) { self.store = store }
    public func save(_ session: WalkSession) async throws { try await store.setSession(session) }
    public func load() async throws -> WalkSession? { await store.session }
    public func clear() async throws { try await store.setSession(nil) }
}

public struct InMemoryImageStore: ImageStore {
    let store: InMemoryStore
    public init(store: InMemoryStore) { self.store = store }
    public func store(_ data: Data) async throws -> String { try await store.putImage(data) }
    public func data(for reference: String) async throws -> Data? { await store.images[reference] }
    public func delete(reference: String) async throws { try await store.removeImage(reference) }
}
