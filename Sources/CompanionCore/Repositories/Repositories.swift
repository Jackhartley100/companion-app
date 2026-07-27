import Foundation

/// Filters applied when listing activities.
public struct ActivityQuery: Sendable, Hashable {
    public var dogID: UUID?
    public var activityType: ActivityType?
    /// Inclusive lower bound on `startDate`.
    public var from: Date?
    /// Exclusive upper bound on `startDate`.
    public var until: Date?
    /// Case-insensitive match against title and notes.
    public var searchText: String?
    public var limit: Int?

    public init(
        dogID: UUID? = nil,
        activityType: ActivityType? = nil,
        from: Date? = nil,
        until: Date? = nil,
        searchText: String? = nil,
        limit: Int? = nil
    ) {
        self.dogID = dogID
        self.activityType = activityType
        self.from = from
        self.until = until
        self.searchText = searchText
        self.limit = limit
    }

    public static let all = ActivityQuery()

    /// Whether an activity satisfies this query. Kept here rather than in each
    /// repository so file-backed and in-memory stores cannot disagree.
    public func matches(_ activity: WalkActivity) -> Bool {
        if let dogID, !activity.dogIDs.contains(dogID) { return false }
        if let activityType, activity.activityType != activityType { return false }
        if let from, activity.startDate < from { return false }
        if let until, activity.startDate >= until { return false }
        if let searchText, !searchText.isEmpty {
            let haystack = [activity.title, activity.notes ?? ""].joined(separator: " ")
            if !haystack.localizedCaseInsensitiveContains(searchText) { return false }
        }
        return true
    }
}

public enum RepositoryError: Error, Sendable, Equatable {
    case notFound
    case writeFailed(String)
    case readFailed(String)
    case decodingFailed(String)

    public var userMessage: String {
        switch self {
        case .notFound:
            "That record could not be found. It may already have been deleted."
        case .writeFailed(let detail):
            "Your changes could not be written to this device: \(detail)"
        case .readFailed(let detail):
            "Saved data could not be read from this device: \(detail)"
        case .decodingFailed(let detail):
            "Some saved data is in an unexpected format and was skipped: \(detail)"
        }
    }
}

public protocol UserProfileRepository: Sendable {
    func load() async throws -> UserProfile?
    func save(_ profile: UserProfile) async throws
    /// Removes the profile, dogs, activities, goals and unlocks. Used by
    /// "delete my data" in Settings.
    func deleteEverything() async throws
}

public protocol DogRepository: Sendable {
    /// Non-archived dogs in `sortIndex` order.
    func active() async throws -> [Dog]
    func all() async throws -> [Dog]
    func dog(id: UUID) async throws -> Dog?
    func save(_ dog: Dog) async throws
    func delete(id: UUID) async throws
}

public protocol ActivityRepository: Sendable {
    /// Matching activities, newest first.
    func activities(matching query: ActivityQuery) async throws -> [WalkActivity]
    func activity(id: UUID) async throws -> WalkActivity?
    /// Saves the activity and, when `route` is non-nil, its route points.
    func save(_ activity: WalkActivity, route: [RoutePoint]?) async throws
    func delete(id: UUID) async throws
    /// Loads the full route. Separate from the activity so lists stay cheap.
    func route(for id: UUID) async throws -> [RoutePoint]
    /// Removes every activity and route. Used by "delete activity history".
    func deleteAll() async throws
}

public protocol GoalRepository: Sendable {
    func goals(dogID: UUID?) async throws -> [Goal]
    func activeGoals() async throws -> [Goal]
    func save(_ goal: Goal) async throws
    func delete(id: UUID) async throws
}

public protocol AchievementRepository: Sendable {
    func unlocks() async throws -> [AchievementUnlock]
    func save(_ unlock: AchievementUnlock) async throws
    func acknowledge(ids: [UUID]) async throws
}

public protocol PlaceRepository: Sendable {
    /// Places to show in Explore, nearest to `coordinate` first when supplied.
    func places(near coordinate: Coordinate?) async throws -> [Place]
    func savedPlaceIDs() async throws -> Set<UUID>
    func setSaved(_ saved: Bool, placeID: UUID) async throws
}

/// Persists an in-progress walk so that a crash, a low-memory termination or an
/// accidental force-quit does not lose an hour-long route.
public protocol SessionSnapshotStore: Sendable {
    func save(_ session: WalkSession) async throws
    func load() async throws -> WalkSession?
    func clear() async throws
}

/// Stores dog and activity photos outside the JSON records.
public protocol ImageStore: Sendable {
    /// Writes image data and returns the reference to persist on the model.
    func store(_ data: Data) async throws -> String
    func data(for reference: String) async throws -> Data?
    func delete(reference: String) async throws
}
