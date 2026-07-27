import Testing
import Foundation
@testable import CompanionCore

private let ownerID = UUID()

/// A `FileStore` rooted in a fresh temporary directory, removed afterwards.
private func makeTemporaryStore() throws -> (store: FileStore, root: URL) {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("CompanionTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return (FileStore(root: root), root)
}

private func activity(
    id: UUID = UUID(),
    startDate: Date = Date(timeIntervalSince1970: 1_770_000_000),
    distance: Double = 2_000,
    dogs: [UUID],
    type: ActivityType = .walk,
    title: String = "Walk"
) -> WalkActivity {
    WalkActivity(
        id: id,
        title: title,
        activityType: type,
        startDate: startDate,
        endDate: startDate.addingTimeInterval(1_800),
        elapsedDuration: 1_800,
        movingDuration: 1_800,
        distance: distance,
        dogIDs: dogs,
        ownerID: ownerID
    )
}

@Suite("File-backed repositories")
struct FileRepositoryTests {
    @Test("A dog survives being written and read back")
    func createAndFetchDog() async throws {
        let (store, root) = try makeTemporaryStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let repository = FileDogRepository(store: store)
        let roxy = Dog(name: "Roxy", breedName: "Belgian Malinois", activityLevel: .veryActive)
        try await repository.save(roxy)

        let fetched = try await repository.dog(id: roxy.id)
        #expect(fetched?.name == "Roxy")
        #expect(fetched?.activityLevel == .veryActive)
    }

    /// The property that matters most: data written by one repository instance is
    /// still there for the next one, which is what happens across app launches.
    @Test("Data persists across repository instances")
    func persistsAcrossInstances() async throws {
        let (store, root) = try makeTemporaryStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let dog = Dog(name: "Bailey")
        try await FileDogRepository(store: store).save(dog)

        let freshStore = FileStore(root: root)
        let dogs = try await FileDogRepository(store: freshStore).all()
        #expect(dogs.count == 1)
        #expect(dogs.first?.name == "Bailey")
    }

    @Test("Saving an existing dog updates rather than duplicates it")
    func updateDog() async throws {
        let (store, root) = try makeTemporaryStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let repository = FileDogRepository(store: store)
        var dog = Dog(name: "Roxy", weightKilograms: 24)
        try await repository.save(dog)
        dog.weightKilograms = 27
        try await repository.save(dog)

        let all = try await repository.all()
        #expect(all.count == 1)
        #expect(all.first?.weightKilograms == 27)
    }

    @Test("An archived dog is excluded from the active list but keeps its record")
    func archiveDog() async throws {
        let (store, root) = try makeTemporaryStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let repository = FileDogRepository(store: store)
        var dog = Dog(name: "Roxy")
        try await repository.save(dog)
        dog.isArchived = true
        try await repository.save(dog)

        #expect(try await repository.active().isEmpty)
        #expect(try await repository.all().count == 1)
    }

    @Test("Dogs come back in sort order")
    func dogsSorted() async throws {
        let (store, root) = try makeTemporaryStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let repository = FileDogRepository(store: store)
        try await repository.save(Dog(name: "Second", sortIndex: 1))
        try await repository.save(Dog(name: "First", sortIndex: 0))
        #expect(try await repository.all().map(\.name) == ["First", "Second"])
    }

    @Test("An activity and its route are saved and read back together")
    func saveActivityWithRoute() async throws {
        let (store, root) = try makeTemporaryStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let repository = FileActivityRepository(store: store)
        let dogID = UUID()
        let route = SyntheticRoute.loop(pointCount: 80)
        let walk = activity(dogs: [dogID])

        try await repository.save(walk, route: route)

        #expect(try await repository.activity(id: walk.id)?.title == "Walk")
        #expect(try await repository.route(for: walk.id).count == 80)
    }

    /// Routes are stored separately precisely so that listing activities does not
    /// pay for them.
    @Test("Listing activities does not require their routes")
    func listingDoesNotLoadRoutes() async throws {
        let (store, root) = try makeTemporaryStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let repository = FileActivityRepository(store: store)
        let dogID = UUID()
        var saved: [WalkActivity] = []
        for index in 0..<5 {
            var walk = activity(
                startDate: Date(timeIntervalSince1970: 1_770_000_000 + Double(index) * 86_400),
                dogs: [dogID]
            )
            let route = SyntheticRoute.loop(pointCount: 200)
            walk.routePointCount = route.count
            saved.append(walk)
            try await repository.save(walk, route: route)
        }

        let listed = try await repository.activities(matching: .all)
        #expect(listed.count == 5)
        // The index carries only the point *count*; the points themselves are in
        // separate files, fetched only when a route is actually drawn.
        #expect(listed.allSatisfy { $0.routePointCount == 200 })
        #expect(listed.allSatisfy { $0.routePreview.isEmpty })
        #expect(try await repository.route(for: saved[0].id).count == 200)
    }

    @Test("Activities are returned newest first")
    func activitiesSortedNewestFirst() async throws {
        let (store, root) = try makeTemporaryStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let repository = FileActivityRepository(store: store)
        let dogID = UUID()
        let old = activity(startDate: Date(timeIntervalSince1970: 1_000_000), dogs: [dogID], title: "Old")
        let new = activity(startDate: Date(timeIntervalSince1970: 2_000_000), dogs: [dogID], title: "New")
        try await repository.save(old, route: nil)
        try await repository.save(new, route: nil)

        #expect(try await repository.activities(matching: .all).map(\.title) == ["New", "Old"])
    }

    @Test("Deleting an activity removes its route too")
    func deleteActivityRemovesRoute() async throws {
        let (store, root) = try makeTemporaryStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let repository = FileActivityRepository(store: store)
        let walk = activity(dogs: [UUID()])
        try await repository.save(walk, route: SyntheticRoute.loop(pointCount: 40))
        try await repository.delete(id: walk.id)

        #expect(try await repository.activity(id: walk.id) == nil)
        #expect(try await repository.route(for: walk.id).isEmpty)
    }

    @Test("Filtering by dog returns only that dog's walks")
    func filterByDog() async throws {
        let (store, root) = try makeTemporaryStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let repository = FileActivityRepository(store: store)
        let roxy = UUID()
        let bailey = UUID()
        try await repository.save(activity(dogs: [roxy], title: "Roxy only"), route: nil)
        try await repository.save(activity(dogs: [bailey], title: "Bailey only"), route: nil)
        try await repository.save(activity(dogs: [roxy, bailey], title: "Both"), route: nil)

        let roxyWalks = try await repository.activities(matching: ActivityQuery(dogID: roxy))
        #expect(roxyWalks.count == 2)
        #expect(Set(roxyWalks.map(\.title)) == ["Roxy only", "Both"])
    }

    @Test("Filtering by activity type and date range works together")
    func filterByTypeAndDate() async throws {
        let (store, root) = try makeTemporaryStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let repository = FileActivityRepository(store: store)
        let dogID = UUID()
        let day = 86_400.0
        let anchor = Date(timeIntervalSince1970: 1_770_000_000)

        try await repository.save(activity(startDate: anchor, dogs: [dogID], type: .walk), route: nil)
        try await repository.save(activity(startDate: anchor, dogs: [dogID], type: .hike), route: nil)
        try await repository.save(
            activity(startDate: anchor.addingTimeInterval(10 * day), dogs: [dogID], type: .hike),
            route: nil
        )

        let query = ActivityQuery(
            activityType: .hike,
            from: anchor.addingTimeInterval(-day),
            until: anchor.addingTimeInterval(day)
        )
        #expect(try await repository.activities(matching: query).count == 1)
    }

    @Test("Searching matches titles and notes")
    func search() async throws {
        let (store, root) = try makeTemporaryStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let repository = FileActivityRepository(store: store)
        let dogID = UUID()
        var withNote = activity(dogs: [dogID], title: "Evening Walk")
        withNote.notes = "Along the canal towpath"
        try await repository.save(withNote, route: nil)
        try await repository.save(activity(dogs: [dogID], title: "Morning Walk"), route: nil)

        #expect(try await repository.activities(matching: ActivityQuery(searchText: "canal")).count == 1)
        #expect(try await repository.activities(matching: ActivityQuery(searchText: "walk")).count == 2)
        #expect(try await repository.activities(matching: ActivityQuery(searchText: "beach")).isEmpty)
    }

    @Test("A limit truncates to the newest results")
    func limit() async throws {
        let (store, root) = try makeTemporaryStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let repository = FileActivityRepository(store: store)
        let dogID = UUID()
        for index in 0..<10 {
            try await repository.save(
                activity(
                    startDate: Date(timeIntervalSince1970: 1_770_000_000 + Double(index) * 86_400),
                    dogs: [dogID],
                    title: "Walk \(index)"
                ),
                route: nil
            )
        }
        let limited = try await repository.activities(matching: ActivityQuery(limit: 3))
        #expect(limited.count == 3)
        #expect(limited.first?.title == "Walk 9")
    }

    @Test("Deleting all activities clears the routes as well")
    func deleteAll() async throws {
        let (store, root) = try makeTemporaryStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let repository = FileActivityRepository(store: store)
        let walk = activity(dogs: [UUID()])
        try await repository.save(walk, route: SyntheticRoute.loop(pointCount: 40))
        try await repository.deleteAll()

        #expect(try await repository.activities(matching: .all).isEmpty)
        #expect(try await repository.route(for: walk.id).isEmpty)
    }

    @Test("A missing file reads as empty rather than throwing")
    func missingFileIsEmpty() async throws {
        let (store, root) = try makeTemporaryStore()
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(try await FileActivityRepository(store: store).activities(matching: .all).isEmpty)
        #expect(try await FileDogRepository(store: store).all().isEmpty)
        #expect(try await FileUserProfileRepository(store: store).load() == nil)
        #expect(try await FileSessionSnapshotStore(store: store).load() == nil)
    }

    @Test("An in-progress session snapshot round-trips and can be cleared")
    func sessionSnapshot() async throws {
        let (store, root) = try makeTemporaryStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let snapshots = FileSessionSnapshotStore(store: store)
        var session = WalkSession(startDate: Date(), dogIDs: [UUID()])
        for point in SyntheticRoute.loop(pointCount: 30) { session.append(point) }

        try await snapshots.save(session)
        let restored = try await snapshots.load()
        #expect(restored?.id == session.id)
        #expect(restored?.points.count == 30)

        try await snapshots.clear()
        #expect(try await snapshots.load() == nil)
    }

    @Test("Deleting everything leaves no profile, dogs or activities behind")
    func deleteEverything() async throws {
        let (store, root) = try makeTemporaryStore()
        defer { try? FileManager.default.removeItem(at: root) }

        try await FileUserProfileRepository(store: store).save(UserProfile(firstName: "Jack"))
        try await FileDogRepository(store: store).save(Dog(name: "Roxy"))
        try await FileActivityRepository(store: store).save(
            activity(dogs: [UUID()]), route: SyntheticRoute.loop(pointCount: 20)
        )

        try await FileUserProfileRepository(store: store).deleteEverything()

        #expect(try await FileUserProfileRepository(store: store).load() == nil)
        #expect(try await FileDogRepository(store: store).all().isEmpty)
        #expect(try await FileActivityRepository(store: store).activities(matching: .all).isEmpty)
    }

    @Test("Goals can be saved, listed by dog and deleted")
    func goalRepository() async throws {
        let (store, root) = try makeTemporaryStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let repository = FileGoalRepository(store: store)
        let roxy = UUID()
        let bailey = UUID()
        let roxyGoal = Goal(dogID: roxy, goalType: .distance, targetValue: 20_000)
        let householdGoal = Goal(dogID: nil, goalType: .walkCount, targetValue: 10)

        try await repository.save(roxyGoal)
        try await repository.save(Goal(dogID: bailey, goalType: .activeDays, targetValue: 5))
        try await repository.save(householdGoal)

        // A dog's goals include the ones that apply to every dog.
        #expect(try await repository.goals(dogID: roxy).count == 2)
        #expect(try await repository.activeGoals().count == 3)

        try await repository.delete(id: roxyGoal.id)
        #expect(try await repository.goals(dogID: roxy).count == 1)
    }

    @Test("Achievement unlocks are saved and can be acknowledged")
    func achievementRepository() async throws {
        let (store, root) = try makeTemporaryStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let repository = FileAchievementRepository(store: store)
        let unlock = AchievementUnlock(achievementID: "first_walk")
        try await repository.save(unlock)

        #expect(try await repository.unlocks().first?.acknowledged == false)
        try await repository.acknowledge(ids: [unlock.id])
        #expect(try await repository.unlocks().first?.acknowledged == true)
    }

    @Test("Images are stored and retrieved by reference")
    func imageStore() async throws {
        let (store, root) = try makeTemporaryStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let images = FileImageStore(store: store)
        let data = Data("not-really-a-jpeg".utf8)
        let reference = try await images.store(data)

        #expect(try await images.data(for: reference) == data)
        try await images.delete(reference: reference)
        #expect(try await images.data(for: reference) == nil)
    }
}

@Suite("In-memory repositories")
struct InMemoryRepositoryTests {
    /// The preview and test doubles must not be able to show behaviour the real
    /// store would not produce.
    @Test("In-memory querying matches the file-backed store")
    func queryParity() async throws {
        let (fileStore, root) = try makeTemporaryStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let roxy = UUID()
        let bailey = UUID()
        let walks = [
            activity(startDate: Date(timeIntervalSince1970: 1_000), dogs: [roxy], title: "A"),
            activity(startDate: Date(timeIntervalSince1970: 2_000), dogs: [bailey], title: "B"),
            activity(startDate: Date(timeIntervalSince1970: 3_000), dogs: [roxy, bailey], title: "C")
        ]

        let fileRepository = FileActivityRepository(store: fileStore)
        let memoryRepository = InMemoryActivityRepository(store: InMemoryStore())
        for walk in walks {
            try await fileRepository.save(walk, route: nil)
            try await memoryRepository.save(walk, route: nil)
        }

        for query in [
            ActivityQuery.all,
            ActivityQuery(dogID: roxy),
            ActivityQuery(searchText: "b"),
            ActivityQuery(limit: 2)
        ] {
            let fromFile = try await fileRepository.activities(matching: query).map(\.id)
            let fromMemory = try await memoryRepository.activities(matching: query).map(\.id)
            #expect(fromFile == fromMemory)
        }
    }

    @Test("An injected failure surfaces as a repository error")
    func injectedFailure() async throws {
        let store = InMemoryStore()
        await store.setInjectedFailure(.writeFailed("disk full"))
        let repository = InMemoryActivityRepository(store: store)

        await #expect(throws: RepositoryError.writeFailed("disk full")) {
            try await repository.save(activity(dogs: [UUID()]), route: nil)
        }
    }
}
