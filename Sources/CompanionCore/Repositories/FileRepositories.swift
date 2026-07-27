import Foundation

/// On-disk layout. Centralised so the paths are stated once.
enum StorePath {
    static let profile = "profile.json"
    static let dogs = "dogs.json"
    /// Activity metadata only — routes live in their own files.
    static let activityIndex = "activities/index.json"
    static let routesDirectory = "activities/routes"
    static let goals = "goals.json"
    static let achievements = "achievements.json"
    static let savedPlaces = "places/saved.json"
    static let session = "session.json"
    static let imagesDirectory = "images"

    static func route(_ id: UUID) -> String { "\(routesDirectory)/\(id.uuidString).json" }
    static func image(_ reference: String) -> String { "\(imagesDirectory)/\(reference)" }
}

public struct FileUserProfileRepository: UserProfileRepository {
    private let store: FileStore
    public init(store: FileStore) { self.store = store }

    public func load() async throws -> UserProfile? {
        try await store.read(UserProfile.self, from: StorePath.profile)
    }

    public func save(_ profile: UserProfile) async throws {
        var profile = profile
        profile.updatedAt = Date()
        try await store.write(profile, to: StorePath.profile)
    }

    public func deleteEverything() async throws {
        try await store.delete(path: StorePath.profile)
        try await store.delete(path: StorePath.dogs)
        try await store.delete(path: StorePath.goals)
        try await store.delete(path: StorePath.achievements)
        try await store.delete(path: StorePath.session)
        try await store.delete(path: StorePath.activityIndex)
        try await store.deleteDirectory(StorePath.routesDirectory)
        try await store.deleteDirectory(StorePath.imagesDirectory)
    }
}

public struct FileDogRepository: DogRepository {
    private let store: FileStore
    public init(store: FileStore) { self.store = store }

    private func loadAll() async throws -> [Dog] {
        try await store.read([Dog].self, from: StorePath.dogs) ?? []
    }

    public func all() async throws -> [Dog] {
        try await loadAll().sorted { $0.sortIndex < $1.sortIndex }
    }

    public func active() async throws -> [Dog] {
        try await all().filter { !$0.isArchived }
    }

    public func dog(id: UUID) async throws -> Dog? {
        try await loadAll().first { $0.id == id }
    }

    public func save(_ dog: Dog) async throws {
        var dogs = try await loadAll()
        var updated = dog
        updated.updatedAt = Date()
        if let index = dogs.firstIndex(where: { $0.id == dog.id }) {
            dogs[index] = updated
        } else {
            dogs.append(updated)
        }
        try await store.write(dogs, to: StorePath.dogs)
    }

    public func delete(id: UUID) async throws {
        let dogs = try await loadAll().filter { $0.id != id }
        try await store.write(dogs, to: StorePath.dogs)
    }
}

public struct FileActivityRepository: ActivityRepository {
    private let store: FileStore
    public init(store: FileStore) { self.store = store }

    private func loadIndex() async throws -> [WalkActivity] {
        try await store.read([WalkActivity].self, from: StorePath.activityIndex) ?? []
    }

    public func activities(matching query: ActivityQuery) async throws -> [WalkActivity] {
        var result = try await loadIndex()
            .filter(query.matches)
            .sorted { $0.startDate > $1.startDate }
        if let limit = query.limit, result.count > limit {
            result = Array(result.prefix(limit))
        }
        return result
    }

    public func activity(id: UUID) async throws -> WalkActivity? {
        try await loadIndex().first { $0.id == id }
    }

    public func save(_ activity: WalkActivity, route: [RoutePoint]?) async throws {
        // The route is written first: an activity in the index whose route file
        // is missing is a visible bug, whereas an orphaned route file is inert.
        if let route {
            try await store.write(route, to: StorePath.route(activity.id))
        }
        var index = try await loadIndex()
        var updated = activity
        updated.updatedAt = Date()
        if let position = index.firstIndex(where: { $0.id == activity.id }) {
            index[position] = updated
        } else {
            index.append(updated)
        }
        try await store.write(index, to: StorePath.activityIndex)
    }

    public func delete(id: UUID) async throws {
        let index = try await loadIndex().filter { $0.id != id }
        try await store.write(index, to: StorePath.activityIndex)
        try await store.delete(path: StorePath.route(id))
    }

    public func route(for id: UUID) async throws -> [RoutePoint] {
        try await store.read([RoutePoint].self, from: StorePath.route(id)) ?? []
    }

    public func deleteAll() async throws {
        try await store.delete(path: StorePath.activityIndex)
        try await store.deleteDirectory(StorePath.routesDirectory)
    }
}

public struct FileGoalRepository: GoalRepository {
    private let store: FileStore
    public init(store: FileStore) { self.store = store }

    private func loadAll() async throws -> [Goal] {
        try await store.read([Goal].self, from: StorePath.goals) ?? []
    }

    public func goals(dogID: UUID?) async throws -> [Goal] {
        let all = try await loadAll()
        guard let dogID else { return all }
        // A goal with no dog applies to every dog, so it is always included.
        return all.filter { $0.dogID == dogID || $0.dogID == nil }
    }

    public func activeGoals() async throws -> [Goal] {
        try await loadAll().filter(\.isActive)
    }

    public func save(_ goal: Goal) async throws {
        var goals = try await loadAll()
        if let index = goals.firstIndex(where: { $0.id == goal.id }) {
            goals[index] = goal
        } else {
            goals.append(goal)
        }
        try await store.write(goals, to: StorePath.goals)
    }

    public func delete(id: UUID) async throws {
        let goals = try await loadAll().filter { $0.id != id }
        try await store.write(goals, to: StorePath.goals)
    }
}

public struct FileAchievementRepository: AchievementRepository {
    private let store: FileStore
    public init(store: FileStore) { self.store = store }

    public func unlocks() async throws -> [AchievementUnlock] {
        try await store.read([AchievementUnlock].self, from: StorePath.achievements) ?? []
    }

    public func save(_ unlock: AchievementUnlock) async throws {
        var all = try await unlocks()
        if let index = all.firstIndex(where: { $0.id == unlock.id }) {
            all[index] = unlock
        } else {
            all.append(unlock)
        }
        try await store.write(all, to: StorePath.achievements)
    }

    public func acknowledge(ids: [UUID]) async throws {
        var all = try await unlocks()
        let idSet = Set(ids)
        for index in all.indices where idSet.contains(all[index].id) {
            all[index].acknowledged = true
        }
        try await store.write(all, to: StorePath.achievements)
    }
}

public struct FileSessionSnapshotStore: SessionSnapshotStore {
    private let store: FileStore
    public init(store: FileStore) { self.store = store }

    public func save(_ session: WalkSession) async throws {
        try await store.write(session, to: StorePath.session)
    }

    public func load() async throws -> WalkSession? {
        try await store.read(WalkSession.self, from: StorePath.session)
    }

    public func clear() async throws {
        try await store.delete(path: StorePath.session)
    }
}

public struct FileImageStore: ImageStore {
    private let store: FileStore
    public init(store: FileStore) { self.store = store }

    public func store(_ data: Data) async throws -> String {
        let reference = "\(UUID().uuidString).jpg"
        try await store.writeData(data, to: StorePath.image(reference))
        return reference
    }

    public func data(for reference: String) async throws -> Data? {
        try await store.readData(from: StorePath.image(reference))
    }

    public func delete(reference: String) async throws {
        try await store.delete(path: StorePath.image(reference))
    }
}
